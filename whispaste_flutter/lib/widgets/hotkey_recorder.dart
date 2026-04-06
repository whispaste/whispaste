/// Hotkey recorder dialog — captures keyboard shortcuts via live key listening.
///
/// Premium modal with frosted glass backdrop, animated key cap display, and
/// smooth state transitions. Returns [HotkeyResult] on save, null on cancel.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

// ---------------------------------------------------------------------------
// Data class
// ---------------------------------------------------------------------------

/// Result returned when the user saves a new hotkey combination.
class HotkeyResult {
  const HotkeyResult({required this.key, required this.modifiers});

  /// The non-modifier key label, e.g. `'D'`, `'F1'`, `'Space'`.
  final String key;

  /// Modifier string in storage format, e.g. `'ctrl+shift'`.
  final String modifiers;

  @override
  String toString() => 'HotkeyResult(key: $key, modifiers: $modifiers)';
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
    this.initialModifiers = 'ctrl+shift',
  });

  /// The current non-modifier key label.
  final String initialKey;

  /// The current modifier string (e.g. `'ctrl+shift'`).
  final String initialModifiers;

  /// Shows the dialog and returns the new [HotkeyResult], or `null` if
  /// the user cancelled.
  static Future<HotkeyResult?> show(
    BuildContext context, {
    String? initialKey,
    String? initialModifiers,
  }) {
    return showDialog<HotkeyResult>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => HotkeyRecorderDialog(
        initialKey: initialKey ?? 'D',
        initialModifiers: initialModifiers ?? 'ctrl+shift',
      ),
    );
  }

  // ── Key-parsing helpers ──────────────────────────────────────────────

  /// Parses a storage string like `'ctrl+shift'` into display labels.
  static List<String> parseModifiers(String modifiers) {
    if (modifiers.isEmpty) return [];
    return modifiers
        .split('+')
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .map((m) => switch (m.toLowerCase()) {
              'ctrl' || 'control' => 'Ctrl',
              'shift' => 'Shift',
              'alt' => 'Alt',
              'meta' || 'win' || 'cmd' || 'super' => 'Win',
              _ => m,
            })
        .toList();
  }

  /// Serializes a set of held modifier keys to storage format.
  static String serializeModifiers(Set<LogicalKeyboardKey> mods) {
    final parts = <String>[];
    if (mods.contains(LogicalKeyboardKey.controlLeft) ||
        mods.contains(LogicalKeyboardKey.controlRight)) {
      parts.add('ctrl');
    }
    if (mods.contains(LogicalKeyboardKey.shiftLeft) ||
        mods.contains(LogicalKeyboardKey.shiftRight)) {
      parts.add('shift');
    }
    if (mods.contains(LogicalKeyboardKey.altLeft) ||
        mods.contains(LogicalKeyboardKey.altRight)) {
      parts.add('alt');
    }
    if (mods.contains(LogicalKeyboardKey.metaLeft) ||
        mods.contains(LogicalKeyboardKey.metaRight)) {
      parts.add('meta');
    }
    return parts.join('+');
  }

  /// Returns a human-readable label for a [LogicalKeyboardKey].
  static String keyLabel(LogicalKeyboardKey key) {
    // Named function keys
    final label = key.keyLabel;
    if (label.isNotEmpty && label.length == 1) {
      return label.toUpperCase();
    }
    // Strip "Key " prefix Flutter sometimes adds, e.g. "Key A" → "A"
    if (label.startsWith('Key ')) return label.substring(4).toUpperCase();
    if (label.startsWith('Digit ')) return label.substring(6);
    // Common key names
    return switch (key) {
      LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey.enter => 'Enter',
      LogicalKeyboardKey.escape => 'Esc',
      LogicalKeyboardKey.backspace => 'Backspace',
      LogicalKeyboardKey.tab => 'Tab',
      LogicalKeyboardKey.delete => 'Delete',
      LogicalKeyboardKey.insert => 'Insert',
      LogicalKeyboardKey.home => 'Home',
      LogicalKeyboardKey.end => 'End',
      LogicalKeyboardKey.pageUp => 'PageUp',
      LogicalKeyboardKey.pageDown => 'PageDown',
      LogicalKeyboardKey.arrowUp => '↑',
      LogicalKeyboardKey.arrowDown => '↓',
      LogicalKeyboardKey.arrowLeft => '←',
      LogicalKeyboardKey.arrowRight => '→',
      LogicalKeyboardKey.f1 => 'F1',
      LogicalKeyboardKey.f2 => 'F2',
      LogicalKeyboardKey.f3 => 'F3',
      LogicalKeyboardKey.f4 => 'F4',
      LogicalKeyboardKey.f5 => 'F5',
      LogicalKeyboardKey.f6 => 'F6',
      LogicalKeyboardKey.f7 => 'F7',
      LogicalKeyboardKey.f8 => 'F8',
      LogicalKeyboardKey.f9 => 'F9',
      LogicalKeyboardKey.f10 => 'F10',
      LogicalKeyboardKey.f11 => 'F11',
      LogicalKeyboardKey.f12 => 'F12',
      _ => label.isNotEmpty ? label : key.debugName ?? '?',
    };
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

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  late List<String> _modifierLabels;
  late String _keyLabel;

  /// Tracks currently held modifier keys during recording.
  final Set<LogicalKeyboardKey> _heldModifiers = {};

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _modifierLabels =
        HotkeyRecorderDialog.parseModifiers(widget.initialModifiers);
    _keyLabel = widget.initialKey;
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
      } else if (_heldModifiers.isNotEmpty) {
        // At least one modifier + a non-modifier → record the combo.
        setState(() {
          _modifierLabels = HotkeyRecorderDialog.parseModifiers(
            HotkeyRecorderDialog.serializeModifiers(_heldModifiers),
          );
          _keyLabel = HotkeyRecorderDialog.keyLabel(key);
        });
      }
    } else if (event is KeyUpEvent) {
      _heldModifiers.remove(key);
    }
  }

  void _clear() {
    setState(() {
      _modifierLabels = [];
      _keyLabel = '';
      _heldModifiers.clear();
    });
  }

  void _save() {
    if (_keyLabel.isEmpty) return;
    final modString = _modifierLabels
        .map((l) => l.toLowerCase())
        .join('+');
    Navigator.of(context).pop(
      HotkeyResult(key: _keyLabel, modifiers: modString),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        isDark ? WpColorsDark.surfaceElevated : WpColorsLight.surfaceElevated;
    final border =
        isDark ? WpColorsDark.borderDefault : WpColorsLight.borderDefault;
    final textPrimary =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final l10n = L10n.of(context);

    final hasCombo = _modifierLabels.isNotEmpty && _keyLabel.isNotEmpty;

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
                      Text(
                        l10n.settingsHotkeyRecorderTitle,
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
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
                  const SizedBox(height: WpSpacing.xl),

                  // ── Action buttons ──────────────────────────────
                  Row(
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
                      const Spacer(),
                      // Cancel
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          l10n.settingsHotkeyRecorderCancel,
                          style: TextStyle(color: textMuted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: WpSpacing.sm),
                      // Save
                      ElevatedButton(
                        onPressed: hasCombo ? _save : null,
                        child: Text(
                          l10n.settingsHotkeyRecorderSave,
                          style: TextStyle(
                            color: hasCombo ? accent : textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
    final textMuted =
        isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    // Nothing recorded yet — show placeholder
    if (modifiers.isEmpty && keyLabel.isEmpty) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        child: Text(
          '—',
          style: TextStyle(color: textMuted, fontSize: 18),
        ),
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
    final bgColor =
        isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant;
    final borderColor =
        isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle;
    final textColor =
        isDark ? WpColorsDark.textPrimary : WpColorsLight.textPrimary;
    final accentColor = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return AnimatedContainer(
      duration: WpMotion.fast,
      curve: WpMotion.defaultCurve,
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: isPrimary ? (isDark ? WpColorsDark.active : WpColorsLight.active) : bgColor,
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
