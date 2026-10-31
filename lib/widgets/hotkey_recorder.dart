/// Hotkey recorder dialog — captures keyboard shortcuts via live key listening.
///
/// Premium modal with frosted glass backdrop, animated key cap display, and
/// smooth state transitions. Returns [WpHotkeyResult] on save, null on cancel.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/config/settings_labels.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/hotkey_self_heal.dart';
import '../services/floating_button/floating_button_support.dart'
    show LinuxSessionType, linuxSessionTypeFrom;
import '../services/hotkey_conflicts.dart';
import '../services/hotkey_key_resolver.dart' as key_resolver;
import '../services/modifier_key_monitor.dart';
import '../services/win_layout_label.dart';
import 'dialog.dart';
import 'wp_button.dart';
import 'wp_keycap.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

/// Result returned when the user saves a new hotkey combination.
class WpHotkeyResult {
  const WpHotkeyResult({
    required this.key,
    required this.modifiers,
    this.displayKey = '',
    this.singleKey = '',
  });

  /// The canonical non-modifier key token used by the registrar (e.g. `'D'`,
  /// `'F1'`, `'Space'`, `';'`).
  final String key;

  /// Modifier string in storage format, e.g. `'ctrl+shift'`.
  final String modifiers;

  /// User-visible label captured at recording time — non-empty only when the
  /// pressed key produced a layout-dependent character that differs from the
  /// canonical token (e.g. `'Ö'` for a DE-layout user whose physical
  /// `semicolon` position is stored as `key=';'`).
  final String displayKey;

  /// A [ModifierHotkey] name when the user pressed one key alone (only offered
  /// with [WpHotkeyRecorderDialog.singleKeys]); [key] and [modifiers] are then
  /// empty. Empty for a combination.
  final String singleKey;

  @override
  String toString() =>
      'WpHotkeyResult(key: $key, displayKey: $displayKey, modifiers: $modifiers, '
      'singleKey: $singleKey)';
}

// ---------------------------------------------------------------------------
// Dialog widget
// ---------------------------------------------------------------------------

/// A modal dialog that records a keyboard shortcut (modifier + key combo).
///
/// Opens with the current hotkey displayed as styled key caps. Listens for
/// key events and updates the display in real time. The user can save, cancel,
/// or clear the recorded combination.
///
/// Use [WpHotkeyRecorderDialog.show] for a convenient one-liner.
class WpHotkeyRecorderDialog extends StatefulWidget {
  const WpHotkeyRecorderDialog({
    super.key,
    this.initialKey = 'D',
    this.initialDisplayKey = '',
    this.initialModifiers = 'ctrl+shift',
    this.onSubmit,
    this.holderOf,
    this.isWayland,
    this.singleKeys,
    this.initialSingleKey = '',
    this.animation,
  });

  /// The dialog route's animation. Set by [show]: the recorder then wears the
  /// shared form card and footer ([WpFormDialogShell]).
  final Animation<double>? animation;

  /// The single keys this action may use on its own (the dictation trigger).
  /// Null records combinations only. When set, a modifier pressed and let go
  /// alone is recorded as that key, left and right apart; one outside the set
  /// shows why it cannot be used.
  final Set<ModifierHotkey>? singleKeys;

  /// The [ModifierHotkey] name in use when the dialog opens, or empty.
  final String initialSingleKey;

  /// Whether the desktop is a Linux Wayland session. Null reads it from the
  /// environment; tests pass a value. On Wayland the desktop, not WhisPaste,
  /// decides the shortcut, so the dialog says so before Save (PAR-060).
  final bool? isWayland;

  /// The current canonical non-modifier key token (e.g. `'D'`, `';'`).
  final String initialKey;

  /// User-visible label for [initialKey] (e.g. `'Ö'` when [initialKey] is
  /// `';'`). Empty when display matches the canonical token.
  final String initialDisplayKey;

  /// The current modifier string (e.g. `'ctrl+shift'`).
  final String initialModifiers;

  /// Optional callback invoked on Save when the recorder is embedded inline
  /// (i.e. NOT shown as a modal via [show]). When provided, the widget
  /// delivers the [WpHotkeyResult] to this callback instead of popping the
  /// route; Cancel becomes a no-op so the parent owns its lifecycle.
  ///
  /// Used by surfaces like the onboarding ReadyStep that embed the recorder
  /// next to a conflict warning rather than presenting it as a dialog.
  final ValueChanged<WpHotkeyResult>? onSubmit;

  /// Live check against the other WhisPaste actions. Returns the name of the
  /// action that already holds the canonical combination (modifiers, key), or
  /// null when it is free. While a holder exists, Save stays disabled and the
  /// holder is named under the key caps.
  final String? Function(String modifiers, String key)? holderOf;

  /// Platform-aware default modifier string.
  static String get _defaultModifiers =>
      Platform.isMacOS ? 'meta+shift' : 'ctrl+shift';

  /// Shows the dialog and returns the new [WpHotkeyResult], or `null` if
  /// the user cancelled.
  /// [isWayland] is passed through like on the constructor: null reads the
  /// session, a test passes a value to reach the Wayland hint (UX-109).
  static Future<WpHotkeyResult?> show(
    BuildContext context, {
    String? initialKey,
    String? initialDisplayKey,
    String? initialModifiers,
    String? Function(String modifiers, String key)? holderOf,
    bool? isWayland,
    Set<ModifierHotkey>? singleKeys,
    String initialSingleKey = '',
  }) {
    return showWpFormDialog<WpHotkeyResult>(
      context: context,
      builder: (ctx, a) => WpHotkeyRecorderDialog(
        initialKey: initialKey ?? 'D',
        initialDisplayKey: initialDisplayKey ?? '',
        initialModifiers: initialModifiers ?? _defaultModifiers,
        holderOf: holderOf,
        isWayland: isWayland,
        singleKeys: singleKeys,
        initialSingleKey: initialSingleKey,
        animation: a,
      ),
    );
  }

  // ── Key-parsing helpers ──────────────────────────────────────────────

  /// Serializes a set of held modifier keys to storage format.
  ///
  /// Delegates to [key_resolver.serializeModifiers] — the canonical single
  /// source of truth lives next to [key_resolver.resolveModifiers] so the
  /// write- and read-paths share their token vocabulary.
  static String serializeModifiers(Set<LogicalKeyboardKey> mods) =>
      key_resolver.serializeModifiers(mods);

  /// Returns a human-readable label for a [LogicalKeyboardKey].
  ///
  /// Delegates to [key_resolver.labelForKey] for the canonical resolver table
  /// (letters A–Z, F1–F12, arrow keys, named keys). Falls back to Flutter's
  /// own [LogicalKeyboardKey.keyLabel] for any key not in the resolver's table
  /// (e.g. digit keys, media keys).
  static String keyLabel(LogicalKeyboardKey key) {
    // Canonical resolver table — single source of truth for stored keys.
    final resolved = key_resolver.labelForKey(key);
    if (resolved != null) return resolved;

    // Flutter's own key label for keys outside the resolver table.
    final label = key.keyLabel;
    if (label.isNotEmpty && label.length == 1) {
      return label.toUpperCase();
    }
    // Strip "Key " prefix Flutter sometimes adds, e.g. "Key A" → "A"
    if (label.startsWith('Key ')) return label.substring(4).toUpperCase();
    if (label.startsWith('Digit ')) return label.substring(6);
    return label.isNotEmpty ? label : key.debugName ?? '?';
  }

  @override
  State<WpHotkeyRecorderDialog> createState() => _WpHotkeyRecorderDialogState();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Well-known modifier keys — used to distinguish modifiers from regular keys.
final _modifierKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
};

/// The single key each physical modifier stands for, left and right apart.
final _singleKeyOf = <LogicalKeyboardKey, ModifierHotkey>{
  LogicalKeyboardKey.fn: ModifierHotkey.fn,
  LogicalKeyboardKey.shiftLeft: ModifierHotkey.leftShift,
  LogicalKeyboardKey.shiftRight: ModifierHotkey.rightShift,
  LogicalKeyboardKey.controlLeft: ModifierHotkey.leftControl,
  LogicalKeyboardKey.controlRight: ModifierHotkey.rightControl,
  LogicalKeyboardKey.altLeft: ModifierHotkey.leftAlt,
  LogicalKeyboardKey.altRight: ModifierHotkey.rightAlt,
  LogicalKeyboardKey.metaLeft: ModifierHotkey.leftMeta,
  LogicalKeyboardKey.metaRight: ModifierHotkey.rightMeta,
};

/// Keys that may be bound as hotkeys *without* any modifier key.
///
/// Kept intentionally narrow — function keys and a few media keys that
/// rarely appear in normal text input. All other keys require at least
/// one modifier to prevent accidental capture of letter/number keys.
///
/// Wp naming — deliberately unprefixed: this is hotkey *domain* data (which
/// keys the app considers bindable on their own), shared with the key
/// resolver in the service layer, not part of the shared component
/// vocabulary that the `Wp` prefix marks. It only sits in this file because
/// [WpHotkeyRecorderDialog] is where the rule is enforced.
final Set<LogicalKeyboardKey> singleKeyWhitelist = {
  // Function keys
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
  // Media keys
  LogicalKeyboardKey.mediaPlayPause,
  LogicalKeyboardKey.mediaStop,
  LogicalKeyboardKey.audioVolumeMute,
};

/// The card's own fixed width, regardless of how much width it is offered —
/// see [_IntrinsicWidthClamp], which stops `getMaxIntrinsicHeight` from
/// answering with the *offered* width instead of this one.
const double _kCardWidth = 420;

class _WpHotkeyRecorderDialogState extends State<WpHotkeyRecorderDialog> {
  /// User-visible label rendered inside the key cap (e.g. `'D'`, `'Ö'`,
  /// `'F1'`). May diverge from [_storageKey] when the user pressed a
  /// layout-dependent character.
  late String _keyLabel;

  /// Canonical storage token for the non-modifier key (e.g. `'D'`, `';'`).
  /// What the registrar reads back via `resolveKey`. Empty when no valid
  /// key is currently recorded.
  late String _storageKey;

  /// Canonical storage-format modifier string (e.g. `'ctrl+shift'`, `'altgr'`)
  /// captured at the moment the last valid combo was recorded. Display labels
  /// are derived from this at render time via [hotkeyModifierLabels] so they
  /// stay localized and platform-correct (Strg/Option/AltGr …). Persisted via
  /// [WpHotkeyResult] on save so registrar reads see canonical tokens.
  late String _modifiersStorage;

  /// Tracks currently held modifier keys during recording.
  final Set<LogicalKeyboardKey> _heldModifiers = {};

  /// True when the held Alt is AltGr (Windows RightAlt + synthetic LeftCtrl).
  /// Stored as plain `alt` (AltGr is not a registrable modifier) but displayed
  /// as `AltGr` so the cap matches what the user pressed (#39).
  bool _isAltGr = false;

  /// True when the current [_keyLabel] was set by a whitelisted single key
  /// (F1–F12 or selected media keys) pressed without any modifier.
  bool _isSingleKey = false;

  /// Non-null when the current combo matches a known system-reserved shortcut.
  ConflictEntry? _conflict;

  /// The recorded single key ([ModifierHotkey] name), or empty. Set only
  /// with [WpHotkeyRecorderDialog.singleKeys]; a combination clears it.
  String _singleKey = '';

  /// The modifier pressed first while nothing else was down. Let go without
  /// any other key in between, it becomes [_singleKey].
  ModifierHotkey? _soloCandidate;

  /// Fn is not a combination modifier, so it is tracked apart.
  bool _fnHeld = false;

  /// A single key the user pressed alone that this action cannot use here.
  ModifierHotkey? _rejectedSingleKey;

  /// A key joined the held modifiers during this press, so the display shows
  /// the recorded combination instead of the live modifiers.
  bool _keyThisPress = false;

  /// Something was recorded or cleared since the dialog opened.
  bool _changed = false;

  /// True while the most recent key press was not recordable. Stays visible
  /// until the user presses a valid key or hits Clear — earlier auto-hide
  /// after 2 s was reported as too short for the feedback to register.
  bool _showInvalidKeyHint = false;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Takes the app's registered hotkeys off the system while the recorder
    // listens, so a combination that is already in use reaches it.
    HotkeyCaptureGuard.beginListening();
    _loadInitialCombo();
  }

  /// Loads the combo the recorder was opened with. Also the inline mode's
  /// Escape: it discards what was recorded and shows the saved combo again.
  void _loadInitialCombo() {
    _modifiersStorage = widget.initialModifiers;
    // Validate the persisted key before trusting it as a valid combo.
    // Pre-fix DBs may contain non-resolvable tokens (e.g. raw `'Ö'`) that the
    // recorder previously accepted but the registrar now rejects. Treat such
    // values as "no key recorded" so Save stays disabled until the user
    // presses a valid combo.
    final initialResolvable = _isResolvable(widget.initialKey);
    _storageKey = initialResolvable ? widget.initialKey : '';
    if (initialResolvable) {
      _keyLabel = widget.initialDisplayKey.trim().isNotEmpty
          ? widget.initialDisplayKey
          : widget.initialKey;
    } else {
      _keyLabel = '';
    }
    // When the dialog opens with a pre-existing whitelisted single-key binding
    // (no modifiers), mark it so the Save button is enabled immediately.
    _isSingleKey =
        _modifiersStorage.isEmpty && _isWhitelistedLabel(_storageKey);
    // Check initial combo against the system conflict list (use storage token
    // so the conflict table matches its US-layout keys).
    _conflict = _storageKey.isEmpty
        ? null
        : findConflict(widget.initialModifiers, _storageKey);
    _singleKey = widget.singleKeys == null ? '' : widget.initialSingleKey;
    _soloCandidate = null;
    _rejectedSingleKey = null;
  }

  static bool _isResolvable(String label) {
    if (label.isEmpty) return false;
    try {
      key_resolver.resolveKey(label);
      return true;
    } on ArgumentError {
      return false;
    }
  }

  /// Returns true when [label] matches a key in [singleKeyWhitelist].
  ///
  /// Compares against the labels produced by [WpHotkeyRecorderDialog.keyLabel]
  /// for each whitelisted key.
  static bool _isWhitelistedLabel(String label) {
    return singleKeyWhitelist.any(
      (k) => WpHotkeyRecorderDialog.keyLabel(k) == label,
    );
  }

  @override
  void dispose() {
    HotkeyCaptureGuard.endListening();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Key event handling ─────────────────────────────────────────────

  /// Enter confirms a recorded combination, like the default button of a
  /// dialog (UX-084). Enter without a modifier is never recordable, so while a
  /// valid combination is recorded it means Save; otherwise it falls through
  /// to the usual invalid-key hint. Held modifiers (e.g. Ctrl+Enter) keep
  /// recording Enter as part of a combination. This listener also sees events
  /// of the card's buttons: a focused button keeps its own Enter (R14-2), so
  /// Enter is consumed here only while the recorder itself has focus.
  /// Returns true when the event is consumed.
  bool _handleEnter(KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return false;
    }
    if (!_focusNode.hasPrimaryFocus) return true;
    final canSave =
        _heldModifiers.isEmpty &&
        (_singleKey.isNotEmpty ||
            (_storageKey.isNotEmpty &&
                (_modifiersStorage.isNotEmpty || _isSingleKey)));
    if (event is KeyDownEvent && canSave) {
      _save();
      return true;
    }
    return false;
  }

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // Escape closes the dialog instead of being treated as an (invalid)
    // recordable key — without this, a keyboard-only user has no way out of
    // the recorder besides clicking Cancel with the mouse. Embedded inline
    // there is no route to pop, so Escape discards the recorded combo and
    // restores the saved one instead (UIA-ONB-08).
    if (event is KeyDownEvent && key == LogicalKeyboardKey.escape) {
      if (widget.onSubmit == null) {
        // maybePop, so a recorded key asks before it is dropped.
        unawaited(Navigator.of(context).maybePop());
      } else {
        _heldModifiers.clear();
        _isAltGr = false;
        _fnHeld = false;
        setState(() {
          _loadInitialCombo();
          _showInvalidKeyHint = false;
        });
      }
      return;
    }

    if (_handleEnter(event)) return;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _onKeyDown(event, key);
    } else if (event is KeyUpEvent) {
      _onKeyUp(key);
    }
  }

  void _onKeyDown(KeyEvent event, LogicalKeyboardKey key) {
    final singleKeys = widget.singleKeys != null;
    final isFn = key == LogicalKeyboardKey.fn;
    if (!_modifierKeys.contains(key) && !(singleKeys && isFn)) {
      _soloCandidate = null;
      if (_heldModifiers.isNotEmpty ||
          singleKeyWhitelist.contains(key) ||
          key_resolver.canonicalRecordableKey(event) != null) {
        _recordKey(event, key);
      }
      return;
    }
    if (event is KeyDownEvent && singleKeys) _trackSolo(key);
    if (isFn) {
      _fnHeld = true;
      return;
    }
    // Rebuilt so the held modifiers show while the user builds the
    // combination.
    setState(() => _heldModifiers.add(key));
    _detectAltGr(key);
  }

  void _onKeyUp(LogicalKeyboardKey key) {
    final solo = _soloCandidate;
    if (solo != null && _singleKeyOf[key] == solo) {
      _soloCandidate = null;
      _recordSingleKey(solo);
    }
    if (key == LogicalKeyboardKey.fn) _fnHeld = false;
    if (_heldModifiers.contains(key)) {
      setState(() {
        _heldModifiers.remove(key);
        if (_heldModifiers.isEmpty) _keyThisPress = false;
      });
    }
    if (key == LogicalKeyboardKey.altRight) _isAltGr = false;
  }

  /// A modifier pressed while nothing else is down may become a single key;
  /// a second one joining turns the press into a combination.
  void _trackSolo(LogicalKeyboardKey key) {
    final alreadyHeld =
        _heldModifiers.contains(key) ||
        (key == LogicalKeyboardKey.fn && _fnHeld);
    if (alreadyHeld) return;
    _soloCandidate = _heldModifiers.isEmpty && !_fnHeld
        ? _singleKeyOf[key]
        : null;
  }

  /// Records [key] pressed and let go alone, or says why it cannot be used.
  void _recordSingleKey(ModifierHotkey key) {
    if (!widget.singleKeys!.contains(key)) {
      setState(() {
        _rejectedSingleKey = key;
        _showInvalidKeyHint = false;
      });
      return;
    }
    setState(() {
      _changed = true;
      _singleKey = key.name;
      _modifiersStorage = '';
      _storageKey = '';
      _keyLabel = '';
      _isSingleKey = false;
      _conflict = null;
      _rejectedSingleKey = null;
      _showInvalidKeyHint = false;
    });
    announce(
      View.of(context),
      modifierOnlyLabel(L10n.of(context), key.name),
      Directionality.of(context),
    );
  }

  /// Marks the held Alt as AltGr (Windows only). Pressing AltGr (physical
  /// RightAlt) makes Windows inject a synthetic LeftCtrl alongside RightAlt —
  /// that pairing distinguishes AltGr from a plain RightAlt. The combo is then
  /// stored as the distinct `altgr` token: registered as Ctrl+Alt (AltGr
  /// physically *is* Ctrl+Alt, so it actually fires) and shown as a localized
  /// "AltGr". Skipped when a RightCtrl is also held (the user genuinely wants
  /// Ctrl). Linux AltGr injects no control key, macOS has none — Windows-only.
  /// `defaultTargetPlatform` keeps this testable via the override.
  void _detectAltGr(LogicalKeyboardKey key) {
    if (defaultTargetPlatform == TargetPlatform.windows &&
        key == LogicalKeyboardKey.altRight &&
        _heldModifiers.contains(LogicalKeyboardKey.controlLeft) &&
        !_heldModifiers.contains(LogicalKeyboardKey.controlRight)) {
      _isAltGr = true;
    }
  }

  /// Records a non-modifier key press as the hotkey's main key (with the
  /// currently-held modifiers), or shows the invalid-key hint when it cannot be
  /// used. Storage stays canonical/layout-stable; the displayed cap prefers the
  /// real character the user pressed (e.g. `Ö`), resolved natively on Windows.
  void _recordKey(KeyEvent event, LogicalKeyboardKey key) {
    final canonical = key_resolver.canonicalRecordableKey(event);
    if (canonical == null) {
      setState(() => _showInvalidKeyHint = true);
      return;
    }
    // Need either a held modifier OR a single-key whitelist member — letters /
    // punctuation alone must not be capturable (would swallow normal typing).
    final structurallyAllowed =
        _heldModifiers.isNotEmpty || singleKeyWhitelist.contains(canonical);
    if (!structurallyAllowed) {
      setState(() => _showInvalidKeyHint = true);
      return;
    }
    final serializedMods = _isAltGr
        ? _altGrModifierStorage()
        : WpHotkeyRecorderDialog.serializeModifiers(_heldModifiers);
    final storageLabel = WpHotkeyRecorderDialog.keyLabel(canonical);
    // Display label: prefer the character the user actually pressed when it
    // differs from the canonical token (e.g. `Ö` ≠ `;`); otherwise the resolver
    // label so casing/symbols stay consistent.
    final pressedLabel = WpHotkeyRecorderDialog.keyLabel(key);
    final displayLabel =
        (canonical != key &&
            pressedLabel.isNotEmpty &&
            pressedLabel != storageLabel)
        ? pressedLabel
        : storageLabel;
    setState(() {
      _changed = true;
      _keyThisPress = true;
      _singleKey = '';
      _rejectedSingleKey = null;
      _modifiersStorage = serializedMods;
      _storageKey = storageLabel;
      _keyLabel = displayLabel;
      _isSingleKey =
          _heldModifiers.isEmpty && singleKeyWhitelist.contains(canonical);
      _conflict = findConflict(serializedMods, storageLabel);
      _showInvalidKeyHint = false;
    });
    // Screen-reader users can't see the key-cap display update — announce the
    // newly recorded combo so they know what was captured.
    announce(
      View.of(context),
      formatHotkeyShortcut(
        serializedMods,
        storageLabel,
        l10n: L10n.of(context),
        displayOverride: displayLabel != storageLabel ? displayLabel : null,
      ),
      Directionality.of(context),
    );
    // Windows: the physical key that just fired may not be the one the OS
    // actually binds for the ACTIVE keyboard layout — Windows reassigns the
    // VK_OEM_* codes per layout (e.g. the German driver maps the physical
    // `#` key to VK_OEM_2, not VK_OEM_5 as hotkey_manager's US-based
    // conversion assumes). Re-resolve and correct before the user saves (#108).
    unawaited(
      _correctForWindowsLayout(event.physicalKey, storageLabel, serializedMods),
    );
  }

  /// Re-derives the storage key from the physical key the ACTIVE Windows
  /// keyboard layout actually assigns it to, and refreshes the displayed cap
  /// with the real character — once the native lookup returns, and only if
  /// the same key is still selected. No-op off Windows or for layout-
  /// invariant keys (letters, digits, arrows, named keys) — see
  /// `resolveWindowsKey` (#108).
  Future<void> _correctForWindowsLayout(
    PhysicalKeyboardKey pressedPhysicalKey,
    String storageLabel,
    String serializedMods,
  ) async {
    final resolution = await resolveWindowsKey(pressedPhysicalKey);
    if (!mounted || _storageKey != storageLabel) return;
    final correctedLogical = key_resolver.logicalForPhysicalKey(
      resolution.physicalKey,
    );
    final correctedLabel = correctedLogical == null
        ? null
        : WpHotkeyRecorderDialog.keyLabel(correctedLogical);
    if (correctedLabel == null || correctedLabel == storageLabel) {
      // Physical position already matches what was registered — only the cap
      // character may still need the real-layout correction.
      if (resolution.displayLabel != null) {
        setState(() => _keyLabel = resolution.displayLabel!);
      }
      return;
    }
    setState(() {
      _storageKey = correctedLabel;
      _keyLabel = resolution.displayLabel ?? correctedLabel;
      _conflict = findConflict(serializedMods, correctedLabel);
    });
  }

  /// Builds the storage string for an AltGr combo: the distinct `altgr` token
  /// (resolves to Ctrl+Alt for registration, shows as a localized "AltGr"),
  /// preserving any other held modifier (e.g. Shift → `shift+altgr`).
  String _altGrModifierStorage() {
    final others = <LogicalKeyboardKey>{
      for (final k in _heldModifiers)
        if (k != LogicalKeyboardKey.altLeft &&
            k != LogicalKeyboardKey.altRight &&
            k != LogicalKeyboardKey.controlLeft &&
            k != LogicalKeyboardKey.controlRight)
          k,
    };
    final base = WpHotkeyRecorderDialog.serializeModifiers(others);
    return base.isEmpty ? 'altgr' : '$base+altgr';
  }

  void _clear() {
    setState(() {
      _changed = true;
      _modifiersStorage = '';
      _keyLabel = '';
      _storageKey = '';
      _isSingleKey = false;
      _conflict = null;
      _heldModifiers.clear();
      _isAltGr = false;
      _showInvalidKeyHint = false;
      _singleKey = '';
      _soloCandidate = null;
      _fnHeld = false;
      _rejectedSingleKey = null;
    });
  }

  /// The action that already holds the recorded combination, or null.
  String? _holderLabel() => _storageKey.isEmpty
      ? null
      : widget.holderOf?.call(_modifiersStorage, _storageKey);

  void _save() {
    if (_singleKey.isNotEmpty) {
      _deliver(WpHotkeyResult(key: '', modifiers: '', singleKey: _singleKey));
      return;
    }
    if (_storageKey.isEmpty || _holderLabel() != null) return;
    final displayForResult = _keyLabel != _storageKey ? _keyLabel : '';
    _deliver(
      WpHotkeyResult(
        key: _storageKey,
        modifiers: _modifiersStorage,
        displayKey: displayForResult,
      ),
    );
  }

  void _deliver(WpHotkeyResult result) {
    final onSubmit = widget.onSubmit;
    if (onSubmit != null) {
      // Inline mode (e.g. embedded in ReadyStep) — hand the result to the
      // parent and let it decide what to do (typically: persist + retry
      // registration). The widget stays mounted so the user can rebind again
      // if the new combo also fails.
      onSubmit(result);
    } else {
      Navigator.of(context).pop(result);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────

  /// The caps the field shows: the held modifiers live while a combination
  /// is still being built (a modifier held alone as its single key), else the
  /// recorded single key or combination.
  List<_Cap> _shownCaps(L10n l10n, {required bool live}) {
    final solo = _soloCandidate;
    if (live && solo != null) return [singleKeyCap(l10n, solo.name)];
    if (live) {
      return _capsOf(
        l10n,
        WpHotkeyRecorderDialog.serializeModifiers(_heldModifiers),
        '',
      );
    }
    if (_singleKey.isNotEmpty) return [singleKeyCap(l10n, _singleKey)];
    return _capsOf(l10n, _modifiersStorage, _keyLabel);
  }

  /// The keys in effect when the dialog opened.
  List<_Cap> _currentCaps(L10n l10n, {required bool dictation}) =>
      dictation && widget.initialSingleKey.isNotEmpty
      ? [singleKeyCap(l10n, widget.initialSingleKey)]
      : _capsOf(
          l10n,
          widget.initialModifiers,
          widget.initialDisplayKey.trim().isNotEmpty
              ? widget.initialDisplayKey
              : widget.initialKey,
        );

  @override
  Widget build(BuildContext context) {
    final bg = WpColors.surfaceElevated;
    final border = WpColors.borderDefault;
    final textPrimary = WpColors.textPrimary;
    final textMuted = WpColors.textMuted;
    final accent = WpColors.accent;
    final l10n = L10n.of(context);
    final dictation = widget.singleKeys != null;
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;

    // Modifier chips, derived from the canonical storage tokens at render time
    // so they stay localized AND platform-correct (Strg/Option/AltGr/Win …).
    // While the user still builds a combination, the held modifiers show
    // live; a modifier held alone shows as its single key.
    final live = _heldModifiers.isNotEmpty && !_keyThisPress;
    final caps = _shownCaps(l10n, live: live);
    // Until the first press the field waits, visibly empty: the key in
    // effect stands above it, so pressing that same key again still shows.
    final listening = !live && !_changed;
    final current = _currentCaps(l10n, dictation: dictation);
    final examples = hotkeyRecorderExamples(l10n: l10n);
    final holder = _holderLabel();
    final single = ModifierHotkey.values
        .where((k) => k.name == _singleKey)
        .firstOrNull;
    final rejected = _rejectedSingleKey;

    // A valid combo requires a resolvable storage key plus either a modifier
    // or a whitelisted single key (F1–F12, media keys — stored in
    // _isSingleKey). Driven by the canonical storage key, not the display
    // label, so a stale DB value (e.g. `'Ö'`) that initState rejected keeps
    // Save disabled.
    final hasCombo =
        _singleKey.isNotEmpty ||
        (_storageKey.isNotEmpty &&
            (_modifiersStorage.isNotEmpty || _isSingleKey));
    final muted = TextStyle(
      color: textMuted,
      fontSize: WpTypography.small,
      height: 1.4,
    );

    final inline = widget.onSubmit != null;
    final title = dictation
        ? l10n.settingsHotkeyRecorderDictationTitle
        : l10n.settingsHotkeyRecorderTitle;
    final subtitle = dictation
        ? l10n.settingsHotkeyRecorderDictationHint(
            modifierOnlyLabel(l10n, modifierOnlySuggestion(isMacOS: isMac)),
          )
        : l10n.settingsHotkeyRecorderHint;
    final canSave = hasCombo && holder == null && _changed;

    final fields = <Widget>[
      // ── The key in effect, then the field that records ──
      if (current.isNotEmpty) ...[
        _CurrentKeys(label: l10n.settingsHotkeyRecorderCurrent, caps: current),
        const SizedBox(height: WpSpacing.sm),
      ],
      _KeyField(
        caps: caps,
        listening: listening,
        lit: live,
        listeningText: l10n.settingsHotkeyRecorderListening,
      ),
      const SizedBox(height: WpSpacing.md),

      // ── Modifier hint ───────────────────────────────
      if (!dictation)
        Center(
          child: Text(
            l10n.settingsHotkeyRecorderModifierHint(
              examples[0],
              examples[1],
              examples[2],
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: textMuted, fontSize: WpTypography.caption),
          ),
        ),
      const SizedBox(height: WpSpacing.xs),

      // ── Invalid-key hint (non-blocking; auto-hides) ─────
      if (_showInvalidKeyHint)
        Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.xs),
          child: Center(
            child: Text(
              l10n.settingsHotkeyRecorderInvalidKey,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WpColors.warning,
                fontSize: WpTypography.caption,
              ),
            ),
          ),
        ),

      // ── Single key: why it cannot be used, or what to know ──
      if (rejected != null)
        Padding(
          padding: const EdgeInsets.only(bottom: WpSpacing.sm),
          child: Text(
            rejected == ModifierHotkey.fn && !isMac
                ? l10n.settingsTriggerKeyUnsupportedFn
                : l10n.settingsTriggerKeyUnsupportedWayland,
            key: const ValueKey('hotkey-recorder-single-unsupported'),
            style: muted.copyWith(color: WpColors.warning),
          ),
        ),
      if (single != null && _changed) ...[
        if (isMac)
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.xs),
            child: Text(l10n.settingsHotkeyRecorderSingleKeyMac, style: muted),
          ),
        if (single.isBusy)
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.xs),
            child: Text(l10n.settingsTriggerDoubleTapHint, style: muted),
          ),
        // Right Alt is AltGr on many layouts: every @ or € would start a
        // recording for a moment.
        if (single == ModifierHotkey.rightAlt && !isMac)
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.xs),
            child: Text(
              l10n.settingsTriggerRightAltAltGr,
              key: const ValueKey('hotkey-recorder-altgr'),
              style: muted,
            ),
          ),
        // A double tap the OS also uses (Fn on macOS): a warning with the way
        // out, never a block.
        if (findDoubleTapConflict(single.name) case final entry?)
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.xs),
            child: WpHotkeyConflictWarning(conflict: entry, l10n: l10n),
          ),
      ],

      // ── Conflict warning ─────────────────────────────
      if (_conflict != null && _changed) ...[
        const SizedBox(height: WpSpacing.xs),
        WpHotkeyConflictWarning(conflict: _conflict!, l10n: l10n),
      ],
      if (widget.isWayland ?? isLinuxWaylandSession())
        Padding(
          padding: const EdgeInsets.only(top: WpSpacing.xs),
          child: WpDesktopShortcutHint(l10n: l10n),
        ),
      if (holder != null && _changed)
        Padding(
          padding: const EdgeInsets.only(top: WpSpacing.xs),
          child: Text(
            l10n.settingsDictationHotkeyCollision(holder),
            key: const ValueKey('hotkey-recorder-holder'),
            style: TextStyle(color: textPrimary, fontSize: WpTypography.small),
          ),
        ),
    ];

    final animation = widget.animation;
    final Widget content;
    if (!inline && animation != null) {
      // As a dialog: the shared form card and footer, like every dialog. A
      // recorded key is input: a stray tap outside asks before dropping it.
      content = WpUnsavedInputGuard(
        dirty: _changed,
        child: WpFormDialogShell(
          animation: animation,
          title: title,
          subtitle: subtitle,
          fields: fields,
          actions: [
            WpDialogAction(
              label: l10n.settingsHotkeyRecorderCancel,
              testId: 'hotkey-recorder-cancel',
              role: WpDialogActionRole.cancel,
            ),
            // Clear. Not for the dictation key: the next press simply
            // replaces what was recorded, and an action needs a trigger.
            if (!dictation)
              WpDialogAction(
                label: l10n.settingsHotkeyRecorderClear,
                testId: 'hotkey-recorder-clear',
                onPressed: _clear,
              ),
            WpDialogAction(
              label: l10n.settingsHotkeyRecorderSave,
              testId: 'hotkey-recorder-save',
              role: WpDialogActionRole.primary,
              enabled: canSave,
              onPressed: _save,
            ),
          ],
        ),
      );
    } else {
      // Embedded on a page (onboarding's conflict branch): the recorder's own
      // card, with Clear and Save. There is no route to cancel.
      content = _IntrinsicWidthClamp(
        width: _kCardWidth,
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: _kCardWidth,
              padding: const EdgeInsets.all(WpSpacing.md),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: WpRadius.borderLg,
                border: Border.all(color: border),
                boxShadow: WpShadows.elevated,
              ),
              // Scrolls when the space is shorter than the card: the v6 rows
              // (current keys, holder line) make it taller than its frame at
              // large text sizes or small windows.
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.keyboard,
                          size: WpIconSize.md,
                          color: accent,
                        ),
                        const SizedBox(width: WpSpacing.sm),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: WpTypography.heading,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: WpSpacing.xs),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: textMuted,
                        fontSize: WpTypography.small,
                      ),
                    ),
                    const SizedBox(height: WpSpacing.md),
                    ...fields,
                    const SizedBox(height: WpSpacing.md),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: WpSpacing.sm,
                      runSpacing: WpSpacing.xs,
                      children: [
                        if (!dictation)
                          WpButton(
                            label: l10n.settingsHotkeyRecorderClear,
                            variant: WpButtonVariant.ghost,
                            tone: WpButtonTone.neutral,
                            icon: LucideIcons.eraser,
                            onPressed: _clear,
                          ),
                        WpButton(
                          testId: 'hotkey-recorder-save',
                          label: l10n.settingsHotkeyRecorderSave,
                          variant: WpButtonVariant.primary,
                          onPressed: canSave ? _save : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: content,
    );
  }
}

/// Clamps the width an intrinsic-height query is answered for to [width],
/// regardless of how much width the query itself offers.
///
/// [WpHotkeyRecorderDialog] renders its card at a fixed [_kCardWidth]
/// (`AnimatedContainer(width: _kCardWidth, …)`), but `Center`'s default
/// `computeMaxIntrinsicHeight(width)` passes the *offered* width straight
/// through to its child — an [IntrinsicHeight] ancestor asking "how tall are
/// you at 640 px?" got an answer sized for a 640-px-wide box, 17 px short of
/// what the card's own fixed 420-px width actually needs. Wrapping the whole
/// subtree in this clamp makes every intrinsic-height query answer as if it
/// had been asked at [width], which is what a box that never actually grows
/// past [width] should do.
class _IntrinsicWidthClamp extends SingleChildRenderObjectWidget {
  const _IntrinsicWidthClamp({required this.width, required super.child});

  final double width;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderIntrinsicWidthClamp(width: width);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderIntrinsicWidthClamp).width = width;
  }
}

class _RenderIntrinsicWidthClamp extends RenderProxyBox {
  // `this._width` would make the constructor's named parameter `_width`
  // itself — callable from outside this class within the library, which
  // reads as accidental privacy leakage at the one call site above.
  // ignore: prefer_initializing_formals
  _RenderIntrinsicWidthClamp({required double width}) : _width = width;

  double _width;

  set width(double value) {
    if (_width == value) return;
    _width = value;
    markNeedsLayout();
  }

  double _clamp(double width) => width < _width ? width : _width;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_clamp(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_clamp(width));
}

typedef _Cap = ({String cap, String? side});

/// Key caps for a stored modifier string and key label.
List<_Cap> _capsOf(L10n l10n, String modifiers, String key) => [
  for (final m in hotkeyModifierLabels(modifiers, l10n: l10n))
    (cap: m, side: null),
  if (key.isNotEmpty) (cap: key, side: null),
];

/// "Aktuell: ⇧ ⌘ D" — the key in effect, small, above the field.
class _CurrentKeys extends StatelessWidget {
  const _CurrentKeys({required this.label, required this.caps});

  final String label;
  final List<_Cap> caps;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('hotkey-recorder-current'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.xxs,
      runSpacing: WpSpacing.xxs,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: WpSpacing.xxs),
          child: Text(
            label,
            style: TextStyle(
              color: WpColors.textMuted,
              fontSize: WpTypography.small,
            ),
          ),
        ),
        for (final c in caps)
          WpKeycap(label: c.side == null ? c.cap : '${c.cap} ${c.side}'),
      ],
    );
  }
}

/// The recording field: empty and waiting with an accent rim, then the
/// pressed keys as large caps that light while held.
class _KeyField extends StatelessWidget {
  const _KeyField({
    required this.caps,
    required this.listening,
    required this.lit,
    required this.listeningText,
  });

  final List<_Cap> caps;
  final bool listening;
  final bool lit;
  final String listeningText;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final Widget child;
    if (listening || caps.isEmpty) {
      child = Column(
        key: const ValueKey('hotkey-recorder-listening'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.keyboard, size: WpIconSize.lg, color: accent),
          const SizedBox(height: WpSpacing.xs),
          Text(
            listeningText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: WpColors.textPrimary,
              fontSize: WpTypography.body,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    } else {
      // Shortcut order is left to right in every locale (UX-024).
      child = Directionality(
        key: ValueKey(caps.map((c) => '${c.cap}${c.side}').join('+')),
        textDirection: TextDirection.ltr,
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WpSpacing.sm,
          runSpacing: WpSpacing.sm,
          children: [
            for (final c in caps)
              WpKeycap.large(
                label: c.cap,
                sublabel: c.side,
                lit: lit,
                extent: 64,
              ),
          ],
        ),
      );
    }
    final waiting = listening || caps.isEmpty;
    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.fast),
      curve: WpMotion.defaultCurve,
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.all(WpSpacing.md),
      decoration: BoxDecoration(
        color: waiting ? accent.withValues(alpha: 0.06) : WpColors.surface,
        borderRadius: WpRadius.borderLg,
        border: Border.all(
          color: waiting
              ? accent.withValues(alpha: 0.6)
              : WpColors.borderDefault,
          width: waiting ? 1.5 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: WpMotion.durationFor(context, WpMotion.fast),
        switchInCurve: WpMotion.defaultCurve,
        switchOutCurve: WpMotion.defaultCurve,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conflict warning banner
// ---------------------------------------------------------------------------

/// Linux Wayland: the desktop sets the shortcut (GlobalShortcuts portal, or the
/// desktop's own binding), so the dialog says so before the user saves. Same
/// sentence as the Settings notice after the binding (`waylandHotkeyBoundNoTrigger`).
/// Left-aligned at body size like the other hints in the dialog (UX-108): a
/// centred caption between them read as an afterthought.
class WpDesktopShortcutHint extends StatelessWidget {
  const WpDesktopShortcutHint({super.key, required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) => Text(
    l10n.waylandHotkeyBoundNoTrigger,
    key: const Key('hotkeyDesktopBindingHint'),
    textAlign: TextAlign.start,
    style: TextStyle(
      color: WpColors.textMuted,
      fontSize: WpTypography.body,
      height: 1.4,
    ),
  );
}

/// True in a Linux Wayland session (XDG_SESSION_TYPE, WAYLAND_DISPLAY fallback).
bool isLinuxWaylandSession() =>
    Platform.isLinux &&
    linuxSessionTypeFrom(Platform.environment) == LinuxSessionType.wayland;

/// Warning for a reserved hotkey: what the OS reserves, and the next steps
/// ([conflictActionLines]). Non-blocking; the user may still save.
class WpHotkeyConflictWarning extends StatelessWidget {
  const WpHotkeyConflictWarning({
    super.key,
    required this.conflict,
    required this.l10n,
    this.isLinux,
  });

  final ConflictEntry conflict;
  final L10n l10n;

  /// Linux reserves through the desktop, so the text names the desktop (no
  /// "reserved by Linux"). Null reads [Platform.isLinux].
  final bool? isLinux;

  String _warningText() {
    final note = conflict.note == null
        ? conflict.key
        : conflictNoteLabel(l10n, conflict.note!);
    if (isLinux ?? Platform.isLinux) {
      return l10n.hotkeyConflictWarningDesktop(note);
    }
    return l10n.hotkeyConflictWarning(_platformName(), note);
  }

  static String _platformName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'OS';
  }

  @override
  Widget build(BuildContext context) {
    final warningColor = WpColors.warning;
    final warningBg = warningColor.withValues(alpha: 0.12);
    final warningBorder = warningColor.withValues(alpha: 0.35);

    // Compact on purpose (UX-107): a thin frame and one line per way out, so
    // the box plus the buttons fit the 800 px window at text scale 1.3.
    return Container(
      key: const Key('hotkeyConflictWarning'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: WpIconSize.sm,
            color: warningColor,
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _warningText(),
                  style: TextStyle(
                    color: warningColor,
                    fontSize: WpTypography.caption,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: WpSpacing.xxs),
                // One line per way out: the system switch first, then the
                // other combination (UX-107).
                Column(
                  key: const Key('hotkeyConflictAction'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in conflictActionLines(l10n, conflict))
                      Text(
                        line,
                        style: TextStyle(
                          color: warningColor,
                          fontSize: WpTypography.caption,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
