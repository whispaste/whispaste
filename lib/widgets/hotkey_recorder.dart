/// Hotkey recorder dialog — captures keyboard shortcuts via live key listening.
///
/// Premium modal with frosted glass backdrop, animated key cap display, and
/// smooth state transitions. Returns [HotkeyResult] on save, null on cancel.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_labels.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/hotkey_conflicts.dart';
import '../services/hotkey_key_resolver.dart' as key_resolver;
import 'dialog.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

/// Result returned when the user saves a new hotkey combination.
class HotkeyResult {
  const HotkeyResult({
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
      'HotkeyResult(key: $key, displayKey: $displayKey, modifiers: $modifiers)';
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
/// Use [HotkeyRecorderDialog.show] for a convenient one-liner.
class HotkeyRecorderDialog extends StatefulWidget {
  const HotkeyRecorderDialog({
    super.key,
    this.initialKey = 'D',
    this.initialDisplayKey = '',
    this.initialModifiers = 'ctrl+shift',
  });

  /// The current canonical non-modifier key token (e.g. `'D'`, `';'`).
  final String initialKey;

  /// User-visible label for [initialKey] (e.g. `'Ö'` when [initialKey] is
  /// `';'`). Empty when display matches the canonical token.
  final String initialDisplayKey;

  /// The current modifier string (e.g. `'ctrl+shift'`).
  final String initialModifiers;

  /// Platform-aware default modifier string.
  static String get _defaultModifiers =>
      Platform.isMacOS ? 'meta+shift' : 'ctrl+shift';

  /// Shows the dialog and returns the new [HotkeyResult], or `null` if
  /// the user cancelled.
  static Future<HotkeyResult?> show(
    BuildContext context, {
    String? initialKey,
    String? initialDisplayKey,
    String? initialModifiers,
  }) {
    return showWpFormDialog<HotkeyResult>(
      context: context,
      builder: (ctx, a) => HotkeyRecorderDialog(
        initialKey: initialKey ?? 'D',
        initialDisplayKey: initialDisplayKey ?? '',
        initialModifiers: initialModifiers ?? _defaultModifiers,
      ),
    );
  }

  // ── Key-parsing helpers ──────────────────────────────────────────────

  /// Parses a storage string like `'ctrl+shift'` into display labels.
  static List<String> parseModifiers(String modifiers) {
    return hotkeyModifierLabels(modifiers);
  }

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
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
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

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  late List<String> _modifierLabels;

  /// User-visible label rendered inside the key cap (e.g. `'D'`, `'Ö'`,
  /// `'F1'`). May diverge from [_storageKey] when the user pressed a
  /// layout-dependent character.
  late String _keyLabel;

  /// Canonical storage token for the non-modifier key (e.g. `'D'`, `';'`).
  /// What the registrar reads back via `resolveKey`. Empty when no valid
  /// key is currently recorded.
  late String _storageKey;

  /// Canonical storage-format modifier string (e.g. `'ctrl+shift'`) captured
  /// at the moment the last valid combo was recorded.
  ///
  /// Distinct from [_modifierLabels], which holds display labels for the UI.
  /// Persisted via [HotkeyResult] on save so registrar reads see canonical
  /// tokens, not localized display strings.
  late String _modifiersStorage;

  /// Tracks currently held modifier keys during recording.
  final Set<LogicalKeyboardKey> _heldModifiers = {};

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
    _modifierLabels = HotkeyRecorderDialog.parseModifiers(
      widget.initialModifiers,
    );
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
    _isSingleKey = _modifierLabels.isEmpty && _isWhitelistedLabel(_storageKey);
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
  /// Compares against the labels produced by [HotkeyRecorderDialog.keyLabel]
  /// for each whitelisted key.
  static bool _isWhitelistedLabel(String label) {
    return singleKeyWhitelist.any(
      (k) => HotkeyRecorderDialog.keyLabel(k) == label,
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

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (_modifierKeys.contains(key)) {
        _heldModifiers.add(key);
      } else if (_heldModifiers.isNotEmpty ||
          singleKeyWhitelist.contains(key) ||
          key_resolver.canonicalRecordableKey(event) != null) {
        // Resolve the canonical storage key (logical or via physical-position
        // fallback for layout-dependent chars like Ö/Ä/Ü on DE).
        // Display-vs-storage symmetry across platforms:
        // - macOS: Flutter reports a Unicode logical key for layout-dependent
        //   chars (e.g. 0xF6 for Ö) regardless of modifiers — the physical
        //   fallback below preserves the user-pressed display label `Ö`.
        // - Windows: layout-dependent chars work too, but Ctrl-combinations
        //   suppress the layout translation, so Flutter reports the canonical
        //   `LogicalKeyboardKey.semicolon` directly. The fast path then keeps
        //   the canonical label as both storage and display — functional, but
        //   the cap reads `;` instead of `Ö`. Tracking the layout char through
        //   `event.character` is intentionally not added here yet: it requires
        //   per-platform verification and the limitation is cosmetic.
        final canonical = key_resolver.canonicalRecordableKey(event);
        if (canonical == null) {
          setState(() {
            _showInvalidKeyHint = true;
          });
          return;
        }
        // Need either a held modifier OR a single-key whitelist member —
        // letters / punctuation alone must not be capturable as global
        // shortcuts (would swallow normal typing).
        final structurallyAllowed =
            _heldModifiers.isNotEmpty || singleKeyWhitelist.contains(canonical);
        if (!structurallyAllowed) {
          setState(() {
            _showInvalidKeyHint = true;
          });
          return;
        }
        final serializedMods = HotkeyRecorderDialog.serializeModifiers(
          _heldModifiers,
        );
        final storageLabel = HotkeyRecorderDialog.keyLabel(canonical);
        // Display label: prefer the original character the user pressed when
        // it differs from the canonical token (e.g. `Ö` ≠ `;`). For canonical
        // matches keep the resolver label so casing/symbols stay consistent.
        final pressedLabel = HotkeyRecorderDialog.keyLabel(key);
        final displayLabel =
            (canonical != key &&
                pressedLabel.isNotEmpty &&
                pressedLabel != storageLabel)
            ? pressedLabel
            : storageLabel;
        setState(() {
          _modifiersStorage = serializedMods;
          _modifierLabels = HotkeyRecorderDialog.parseModifiers(serializedMods);
          _storageKey = storageLabel;
          _keyLabel = displayLabel;
          _isSingleKey =
              _heldModifiers.isEmpty && singleKeyWhitelist.contains(canonical);
          _conflict = findConflict(serializedMods, storageLabel);
          _showInvalidKeyHint = false;
        });
      }
    } else if (event is KeyUpEvent) {
      _heldModifiers.remove(key);
    }
  }

  void _clear() {
    setState(() {
      _modifierLabels = [];
      _modifiersStorage = '';
      _keyLabel = '';
      _storageKey = '';
      _isSingleKey = false;
      _conflict = null;
      _heldModifiers.clear();
      _showInvalidKeyHint = false;
    });
  }

  void _save() {
    if (_storageKey.isEmpty) return;
    final displayForResult = _keyLabel != _storageKey ? _keyLabel : '';
    Navigator.of(context).pop(
      HotkeyResult(
        key: _storageKey,
        modifiers: _modifiersStorage,
        displayKey: displayForResult,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? WpColorsDark.surfaceElevated
        : WpColorsLight.surfaceElevated;
    final border = isDark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final l10n = L10n.of(context);

    // A valid combo requires a resolvable storage key plus either a modifier
    // or a whitelisted single key (F1–F12, media keys — stored in
    // _isSingleKey). Driven by the canonical storage key, not the display
    // label, so a stale DB value (e.g. `'Ö'`) that initState rejected keeps
    // Save disabled.
    final hasCombo =
        _storageKey.isNotEmpty && (_modifierLabels.isNotEmpty || _isSingleKey);

    return Center(
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: WpMotion.smooth,
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
                      Icon(
                        LucideIcons.keyboard,
                        size: WpIconSize.md,
                        color: accent,
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.settingsHotkeyRecorderTitle,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: WpSpacing.xs),
                  Text(
                    l10n.settingsHotkeyRecorderHint,
                    style: TextStyle(color: textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: WpSpacing.xl),

                  // ── Key cap display ─────────────────────────────
                  Center(
                    child: AnimatedSwitcher(
                      duration: WpMotion.fast,
                      switchInCurve: WpMotion.defaultCurve,
                      switchOutCurve: WpMotion.defaultCurve,
                      child: _KeyComboDisplay(
                        key: ValueKey('$_modifierLabels-$_keyLabel'),
                        modifiers: _modifierLabels,
                        keyLabel: _keyLabel,
                        isDark: isDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: WpSpacing.md),

                  // ── Modifier hint ───────────────────────────────
                  Center(
                    child: Text(
                      l10n.settingsHotkeyRecorderModifierHint,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textMuted, fontSize: 11),
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
                            color: isDark
                                ? WpColorsDark.warning
                                : WpColorsLight.warning,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: WpSpacing.xs),

                  // ── Conflict warning ─────────────────────────────
                  if (_conflict != null)
                    _ConflictWarning(
                      conflict: _conflict!,
                      isDark: isDark,
                      l10n: l10n,
                    ),
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
                      TextButton.icon(
                        onPressed: _clear,
                        icon: Icon(
                          LucideIcons.eraser,
                          size: WpIconSize.sm,
                          color: textMuted,
                        ),
                        label: Text(
                          l10n.settingsHotkeyRecorderClear,
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                      ),
                      // Cancel + Save grouped so they stay together when wrapping.
                      Wrap(
                        spacing: WpSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(
                              l10n.settingsHotkeyRecorderCancel,
                              style: TextStyle(color: textMuted, fontSize: 13),
                            ),
                          ),
                          // Save — accent background + white foreground gives
                          // WCAG-AA contrast in both light and dark themes;
                          // the previous accent-text-on-default-elevated bg
                          // failed contrast checks for the disabled label too.
                          ElevatedButton(
                            onPressed: hasCombo ? _save : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: isDark
                                  ? WpColorsDark.surfaceVariant
                                  : WpColorsLight.surfaceVariant,
                              disabledForegroundColor: textMuted,
                            ),
                            child: Text(
                              l10n.settingsHotkeyRecorderSave,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
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
    required this.isDark,
  });

  final List<String> modifiers;
  final String keyLabel;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    // Nothing recorded yet — show placeholder
    if (modifiers.isEmpty && keyLabel.isEmpty) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        child: Text('—', style: TextStyle(color: textMuted, fontSize: 18)),
      );
    }

    final caps = <Widget>[];

    for (var i = 0; i < modifiers.length; i++) {
      if (i > 0) caps.add(_PlusSeparator(isDark: isDark));
      caps.add(_KeyCap(label: modifiers[i], isDark: isDark));
    }

    if (keyLabel.isNotEmpty) {
      if (caps.isNotEmpty) caps.add(_PlusSeparator(isDark: isDark));
      caps.add(_KeyCap(label: keyLabel, isDark: isDark, isPrimary: true));
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
  const _KeyCap({
    required this.label,
    required this.isDark,
    this.isPrimary = false,
  });

  final String label;
  final bool isDark;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textColor = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final accentColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return AnimatedContainer(
      duration: WpMotion.fast,
      curve: WpMotion.defaultCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: isPrimary
            ? (isDark ? WpColorsDark.active : WpColorsLight.active)
            : bgColor,
        borderRadius: BorderRadius.circular(WpRadius.sm),
        border: Border.all(
          color: isPrimary ? accentColor.withValues(alpha: 0.4) : borderColor,
        ),
        boxShadow: WpShadows.subtle,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
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
  const _PlusSeparator({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
      child: Text(
        '+',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
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
  const _ConflictWarning({
    required this.conflict,
    required this.isDark,
    required this.l10n,
  });

  final ConflictEntry conflict;
  final bool isDark;
  final L10n l10n;

  static String _platformName() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'OS';
  }

  @override
  Widget build(BuildContext context) {
    final warningColor = isDark ? WpColorsDark.warning : WpColorsLight.warning;
    final warningBg = warningColor.withValues(alpha: isDark ? 0.12 : 0.10);
    final warningBorder = warningColor.withValues(alpha: isDark ? 0.35 : 0.30);

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
          Icon(
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
              style: TextStyle(color: warningColor, fontSize: 11, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
