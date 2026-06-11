/// Shared presentation helpers for settings-driven UI labels.
library;

import 'dart:io';

import '../l10n/generated/app_localizations.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';

/// Immutable presentation snapshot for the bottom status bar.
///
/// Only carries essential **runtime** info — static config (overlay mode,
/// hotkey, after-action) belongs in Settings, not the status bar.
class StatusBarModel {
  const StatusBarModel({required this.sttModeLabel});

  /// Active speech-to-text mode, e.g. "On device" or "OpenAI".
  final String sttModeLabel;
}

/// Builds a consistent [StatusBarModel] from the current [settings].
StatusBarModel buildStatusBarModel({
  required AppSettings settings,
  required L10n l10n,
}) {
  return StatusBarModel(
    sttModeLabel: settings.sttProviderType.isLocal
        ? l10n.statusBarOnDevice
        : settings.sttProvider,
  );
}

/// Returns display labels for the modifier portion of a shortcut.
///
/// When [l10n] is provided, labels are localized (e.g. "Strg" for German).
/// On macOS, `meta` shows as "Cmd" and `alt` as "Option".
/// Without l10n, falls back to English labels.
List<String> hotkeyModifierLabels(String modifiers, {L10n? l10n}) {
  if (modifiers.isEmpty) return const [];
  final isMac = _isMacOS;
  return modifiers
      .split('+')
      .map((modifier) => modifier.trim())
      .where((modifier) => modifier.isNotEmpty)
      .map(
        (modifier) => switch (modifier.toLowerCase()) {
          'ctrl' || 'control' => l10n?.modifierCtrl ?? 'Ctrl',
          'shift' => l10n?.modifierShift ?? 'Shift',
          'alt' =>
            isMac
                ? (l10n?.modifierOption ?? 'Option')
                : (l10n?.modifierAlt ?? 'Alt'),
          'meta' || 'win' || 'super' =>
            isMac ? (l10n?.modifierCmd ?? 'Cmd') : (l10n?.modifierWin ?? 'Win'),
          'cmd' => l10n?.modifierCmd ?? 'Cmd',
          _ => modifier,
        },
      )
      .toList();
}

/// Cached platform check to avoid repeated dart:io calls.
bool get _isMacOS => Platform.isMacOS;

/// Returns a localized label for the primary key portion of a shortcut.
///
/// When [displayOverride] is non-empty (e.g. `'Ö'` captured by the recorder
/// for a DE-layout user pressing the physical `semicolon` position), it is
/// preferred over the canonical [key] token (`';'`). Single non-empty
/// override characters are returned upper-cased to match the recorder's
/// own key-cap rendering.
String hotkeyKeyLabel(String key, {L10n? l10n, String? displayOverride}) {
  final override = displayOverride?.trim() ?? '';
  if (override.isNotEmpty) {
    return override.length == 1 ? override.toUpperCase() : override;
  }
  final trimmed = key.trim();
  if (trimmed.isEmpty) return '';

  final normalized = trimmed.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  return switch (normalized) {
    'space' => l10n?.shortcutKeySpace ?? 'Space',
    'enter' => l10n?.shortcutKeyEnter ?? 'Enter',
    'escape' || 'esc' => l10n?.shortcutKeyEscape ?? 'Esc',
    'backspace' => l10n?.shortcutKeyBackspace ?? 'Backspace',
    'tab' => l10n?.shortcutKeyTab ?? 'Tab',
    'delete' || 'del' => l10n?.shortcutKeyDelete ?? 'Del',
    'insert' || 'ins' => l10n?.shortcutKeyInsert ?? 'Insert',
    'home' => l10n?.shortcutKeyHome ?? 'Home',
    'end' => l10n?.shortcutKeyEnd ?? 'End',
    'pageup' || 'pgup' => l10n?.shortcutKeyPageUp ?? 'Page Up',
    'pagedown' || 'pgdn' => l10n?.shortcutKeyPageDown ?? 'Page Down',
    'arrowup' || 'up' => '↑',
    'arrowdown' || 'down' => '↓',
    'arrowleft' || 'left' => '←',
    'arrowright' || 'right' => '→',
    _ => trimmed.toUpperCase(),
  };
}

/// Returns shortcut display parts ordered as modifier chips + primary key.
List<String> hotkeyDisplayParts(
  String modifiers,
  String key, {
  L10n? l10n,
  String? displayOverride,
}) {
  return [
    ...hotkeyModifierLabels(modifiers, l10n: l10n),
    if (key.trim().isNotEmpty || (displayOverride?.trim().isNotEmpty ?? false))
      hotkeyKeyLabel(key, l10n: l10n, displayOverride: displayOverride),
  ];
}

/// Formats a shortcut like `ctrl+shift` + `D` into `Ctrl+Shift+D`.
String formatHotkeyShortcut(
  String modifiers,
  String key, {
  String separator = '+',
  L10n? l10n,
  String? displayOverride,
}) {
  return hotkeyDisplayParts(
    modifiers,
    key,
    l10n: l10n,
    displayOverride: displayOverride,
  ).join(separator);
}

/// Returns a short, localized label for the post-transcription action.
String afterTranscriptionStatusLabel(
  AfterTranscriptionAction action,
  L10n l10n,
) {
  return switch (action) {
    AfterTranscriptionAction.clipboard => l10n.statusBarAfterCopy,
    AfterTranscriptionAction.paste => l10n.statusBarAfterPaste,
    AfterTranscriptionAction.clipboardAndPaste => l10n.statusBarAfterBoth,
    AfterTranscriptionAction.nothing => l10n.statusBarAfterNothing,
  };
}
