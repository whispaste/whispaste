/// Hotkey recorder dialog — captures keyboard shortcuts via live key listening.
///
/// Premium modal with frosted glass backdrop, animated key cap display, and
/// smooth state transitions. Returns [WpHotkeyResult] on save, null on cancel.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_labels.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/hotkey_conflicts.dart';
import '../services/hotkey_key_resolver.dart' as key_resolver;
import '../services/win_layout_label.dart';
import 'dialog.dart';
import 'wp_button.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

/// Result returned when the user saves a new hotkey combination.
class WpHotkeyResult {
  const WpHotkeyResult({
    required this.key,
    required this.modifiers,
    this.displayKey = '',
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

  @override
  String toString() =>
      'WpHotkeyResult(key: $key, displayKey: $displayKey, modifiers: $modifiers)';
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
  });

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

  /// Platform-aware default modifier string.
  static String get _defaultModifiers =>
      Platform.isMacOS ? 'meta+shift' : 'ctrl+shift';

  /// Shows the dialog and returns the new [WpHotkeyResult], or `null` if
  /// the user cancelled.
  static Future<WpHotkeyResult?> show(
    BuildContext context, {
    String? initialKey,
    String? initialDisplayKey,
    String? initialModifiers,
  }) {
    return showWpFormDialog<WpHotkeyResult>(
      context: context,
      builder: (ctx, a) => WpHotkeyRecorderDialog(
        initialKey: initialKey ?? 'D',
        initialDisplayKey: initialDisplayKey ?? '',
        initialModifiers: initialModifiers ?? _defaultModifiers,
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

  /// True while the most recent key press was not recordable. Stays visible
  /// until the user presses a valid key or hits Clear — earlier auto-hide
  /// after 2 s was reported as too short for the feedback to register.
  bool _showInvalidKeyHint = false;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
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
    _focusNode.dispose();
    super.dispose();
  }

  // ── Key event handling ─────────────────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    final key = event.logicalKey;

    // Escape closes the dialog instead of being treated as an (invalid)
    // recordable key — without this, a keyboard-only user has no way out of
    // the recorder besides clicking Cancel with the mouse. Only relevant in
    // modal mode: embedded mode has no route to pop and no Cancel button.
    if (event is KeyDownEvent &&
        key == LogicalKeyboardKey.escape &&
        widget.onSubmit == null) {
      Navigator.of(context).pop();
      return;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_modifierKeys.contains(key)) {
        _heldModifiers.add(key);
        _detectAltGr(key);
      } else if (_heldModifiers.isNotEmpty ||
          singleKeyWhitelist.contains(key) ||
          key_resolver.canonicalRecordableKey(event) != null) {
        _recordKey(event, key);
      }
    } else if (event is KeyUpEvent) {
      _heldModifiers.remove(key);
      if (key == LogicalKeyboardKey.altRight) _isAltGr = false;
    }
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
    SemanticsService.sendAnnouncement(
      View.of(context),
      formatHotkeyShortcut(
        serializedMods,
        storageLabel,
        l10n: L10n.of(context),
        displayOverride: displayLabel != storageLabel ? displayLabel : null,
      ),
      Directionality.of(context),
    );
    // Windows: a key captured under a Ctrl/AltGr modifier arrives as its
    // US-canonical form — resolve the real layout label (Ö/Ä/Ü) for the cap.
    unawaited(_resolveLayoutLabel(canonical, storageLabel));
  }

  /// Replaces the displayed key cap with the active-layout character (e.g. `Ö`)
  /// once the native lookup returns, if the same key is still selected.
  Future<void> _resolveLayoutLabel(
    LogicalKeyboardKey canonical,
    String storageLabel,
  ) async {
    final resolved = await resolveWindowsLayoutLabel(canonical);
    if (resolved != null && mounted && _storageKey == storageLabel) {
      setState(() => _keyLabel = resolved);
    }
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
      _modifiersStorage = '';
      _keyLabel = '';
      _storageKey = '';
      _isSingleKey = false;
      _conflict = null;
      _heldModifiers.clear();
      _isAltGr = false;
      _showInvalidKeyHint = false;
    });
  }

  void _save() {
    if (_storageKey.isEmpty) return;
    final displayForResult = _keyLabel != _storageKey ? _keyLabel : '';
    final result = WpHotkeyResult(
      key: _storageKey,
      modifiers: _modifiersStorage,
      displayKey: displayForResult,
    );
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

  @override
  Widget build(BuildContext context) {
    const bg = WpColors.surfaceElevated;
    const border = WpColors.borderDefault;
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;
    const accent = WpColors.accent;
    final l10n = L10n.of(context);

    // Modifier chips, derived from the canonical storage tokens at render time
    // so they stay localized AND platform-correct (Strg/Option/AltGr/Win …).
    final modifierLabels = hotkeyModifierLabels(_modifiersStorage, l10n: l10n);

    // A valid combo requires a resolvable storage key plus either a modifier
    // or a whitelisted single key (F1–F12, media keys — stored in
    // _isSingleKey). Driven by the canonical storage key, not the display
    // label, so a stale DB value (e.g. `'Ö'`) that initState rejected keeps
    // Save disabled.
    final hasCombo =
        _storageKey.isNotEmpty &&
        (_modifiersStorage.isNotEmpty || _isSingleKey);

    final card = Material(
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: WpMotion.durationFor(context, WpMotion.smooth),
        curve: WpMotion.defaultCurve,
        width: 420,
        padding: const EdgeInsets.all(WpSpacing.xl),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: WpRadius.borderLg,
          border: Border.all(color: border),
          boxShadow: WpShadows.elevated,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────
            Row(
              children: [
                const Icon(
                  LucideIcons.keyboard,
                  size: WpIconSize.md,
                  color: accent,
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.settingsHotkeyRecorderTitle,
                    style: const TextStyle(
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
              l10n.settingsHotkeyRecorderHint,
              style: const TextStyle(
                color: textMuted,
                fontSize: WpTypography.small,
              ),
            ),
            const SizedBox(height: WpSpacing.xl),

            // ── Key cap display ─────────────────────────────
            Center(
              child: AnimatedSwitcher(
                duration: WpMotion.durationFor(context, WpMotion.fast),
                switchInCurve: WpMotion.defaultCurve,
                switchOutCurve: WpMotion.defaultCurve,
                child: _KeyComboDisplay(
                  key: ValueKey('$modifierLabels-$_keyLabel'),
                  modifiers: modifierLabels,
                  keyLabel: _keyLabel,
                ),
              ),
            ),
            const SizedBox(height: WpSpacing.md),

            // ── Modifier hint ───────────────────────────────
            Center(
              child: Text(
                l10n.settingsHotkeyRecorderModifierHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: textMuted,
                  fontSize: WpTypography.caption,
                ),
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
                    style: const TextStyle(
                      color: WpColors.warning,
                      fontSize: WpTypography.caption,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: WpSpacing.xs),

            // ── Conflict warning ─────────────────────────────
            if (_conflict != null)
              _ConflictWarning(conflict: _conflict!, l10n: l10n),
            if (_conflict != null) const SizedBox(height: WpSpacing.md),

            // ── Action buttons ──────────────────────────────
            // Wrap (not Row) so long translations (e.g. DE
            // "Speichern"/"Abbrechen"/"Zurücksetzen") flow to a second
            // line instead of overflowing the 420 px dialog and pushing
            // the Save button off-screen.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: WpSpacing.sm,
              runSpacing: WpSpacing.xs,
              children: [
                // Clear
                WpButton(
                  label: l10n.settingsHotkeyRecorderClear,
                  variant: WpButtonVariant.ghost,
                  tone: WpButtonTone.neutral,
                  icon: LucideIcons.eraser,
                  onPressed: _clear,
                ),
                // Cancel + Save grouped so they stay together when wrapping.
                Wrap(
                  spacing: WpSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Cancel only makes sense in modal mode — when the
                    // recorder is embedded inline (no enclosing route to
                    // pop), there is nothing to dismiss, so the button is
                    // hidden to avoid a dead control.
                    if (widget.onSubmit == null)
                      WpButton(
                        label: l10n.settingsHotkeyRecorderCancel,
                        variant: WpButtonVariant.ghost,
                        tone: WpButtonTone.neutral,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    WpButton(
                      label: l10n.settingsHotkeyRecorderSave,
                      variant: WpButtonVariant.primary,
                      onPressed: hasCombo ? _save : null,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return Center(
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        // The blur backdrop only makes sense in modal mode, where it frosts
        // the modal barrier behind the card. Two exceptions render the card
        // bare instead:
        //   • Windows — BackdropFilter + ImageFilter.blur is broken on
        //     frameless windows (see _WpDialogBarrier in dialog.dart), so the
        //     blur would show up as a visibly broken dialog.
        //   • Inline mode (onSubmit != null, e.g. the onboarding trigger page)
        //     — there is no barrier back there, just real page content. The
        //     blur would smear the heading and the conflict warning that
        //     explain why the recorder appeared in the first place.
        child: Platform.isWindows || widget.onSubmit != null
            ? card
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: card,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Key cap combo display
// ---------------------------------------------------------------------------

/// Renders modifier + key labels as styled key caps with "+" separators.
class _KeyComboDisplay extends StatelessWidget {
  const _KeyComboDisplay({
    super.key,
    required this.modifiers,
    required this.keyLabel,
  });

  final List<String> modifiers;
  final String keyLabel;

  @override
  Widget build(BuildContext context) {
    const textMuted = WpColors.textMuted;

    // Nothing recorded yet — show placeholder
    if (modifiers.isEmpty && keyLabel.isEmpty) {
      return Container(
        // `minHeight`, not a fixed `height` — the populated branch below
        // already uses the constraint form, and a hard 48 clipped this text
        // once the system font scaler pushed the 17 px placeholder past the
        // box. Both branches now reserve the same 48 dp floor and grow.
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.center,
        child: const Text(
          '—',
          style: TextStyle(color: textMuted, fontSize: WpTypography.title),
        ),
      );
    }

    final caps = <Widget>[];

    for (var i = 0; i < modifiers.length; i++) {
      if (i > 0) caps.add(const _PlusSeparator());
      caps.add(_KeyCap(label: modifiers[i]));
    }

    if (keyLabel.isNotEmpty) {
      if (caps.isNotEmpty) caps.add(const _PlusSeparator());
      caps.add(_KeyCap(label: keyLabel, isPrimary: true));
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.center,
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WpSpacing.xxs,
        runSpacing: WpSpacing.xs,
        children: caps,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual key cap
// ---------------------------------------------------------------------------

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.label, this.isPrimary = false});

  final String label;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    const bgColor = WpColors.surfaceVariant;
    const borderColor = WpColors.borderSubtle;
    const textColor = WpColors.textPrimary;
    const accentColor = WpColors.accent;

    return AnimatedContainer(
      duration: WpMotion.durationFor(context, WpMotion.fast),
      curve: WpMotion.defaultCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: isPrimary ? (WpColors.active) : bgColor,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(
          color: isPrimary ? accentColor.withValues(alpha: 0.4) : borderColor,
        ),
        boxShadow: WpShadows.subtle,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: WpTypography.body,
          fontWeight: FontWeight.w700,
          color: isPrimary ? accentColor : textColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Plus separator
// ---------------------------------------------------------------------------

class _PlusSeparator extends StatelessWidget {
  const _PlusSeparator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
      child: Text(
        '+',
        style: TextStyle(
          fontSize: WpTypography.subheading,
          fontWeight: FontWeight.w600,
          color: WpColors.textMuted,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conflict warning banner
// ---------------------------------------------------------------------------

/// Visible warning shown when the recorded hotkey is a known system shortcut.
///
/// Non-blocking: the Save button remains enabled. The user retains full
/// control over whether to accept the potential conflict.
class _ConflictWarning extends StatelessWidget {
  const _ConflictWarning({required this.conflict, required this.l10n});

  final ConflictEntry conflict;
  final L10n l10n;

  static String _platformName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'OS';
  }

  @override
  Widget build(BuildContext context) {
    const warningColor = WpColors.warning;
    final warningBg = warningColor.withValues(alpha: 0.12);
    final warningBorder = warningColor.withValues(alpha: 0.35);

    return Container(
      key: const Key('hotkeyConflictWarning'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: warningBg,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(color: warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            LucideIcons.triangleAlert,
            size: WpIconSize.sm,
            color: warningColor,
          ),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Text(
              l10n.hotkeyConflictWarning(
                _platformName(),
                conflict.note.isNotEmpty ? conflict.note : conflict.key,
              ),
              style: const TextStyle(
                color: warningColor,
                fontSize: WpTypography.caption,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
