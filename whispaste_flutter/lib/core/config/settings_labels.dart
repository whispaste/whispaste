/// Shared presentation helpers for settings-driven UI labels.
library;

import '../l10n/generated/app_localizations.dart';
import 'settings_enums.dart';
import 'settings_provider.dart';

/// Immutable presentation snapshot for the bottom status bar.
///
/// Only carries essential **runtime** info — static config (overlay mode,
/// hotkey, after-action) belongs in Settings, not the status bar.
class StatusBarModel {
  const StatusBarModel({
    required this.sttModeLabel,
    this.postProcessingLabel,
  });

  /// Active speech-to-text mode, e.g. "On device" or "OpenAI".
  final String sttModeLabel;

  /// Active post-processing preset label, or `null` when disabled.
  final String? postProcessingLabel;
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
    postProcessingLabel: settings.postProcessEnabled
        ? postProcessingStatusLabel(settings: settings, l10n: l10n)
        : null,
  );
}

/// Returns display labels for the modifier portion of a shortcut.
///
/// When [l10n] is provided, labels are localized (e.g. "Strg" for German).
/// Without l10n, falls back to English labels.
List<String> hotkeyModifierLabels(String modifiers, {L10n? l10n}) {
  if (modifiers.isEmpty) return const [];
  return modifiers
      .split('+')
      .map((modifier) => modifier.trim())
      .where((modifier) => modifier.isNotEmpty)
      .map(
        (modifier) => switch (modifier.toLowerCase()) {
          'ctrl' || 'control' => l10n?.modifierCtrl ?? 'Ctrl',
          'shift' => l10n?.modifierShift ?? 'Shift',
          'alt' => l10n?.modifierAlt ?? 'Alt',
          'meta' || 'win' || 'super' => l10n?.modifierWin ?? 'Win',
          'cmd' => l10n?.modifierCmd ?? 'Cmd',
          _ => modifier,
        },
      )
      .toList();
}

/// Returns shortcut display parts ordered as modifier chips + primary key.
List<String> hotkeyDisplayParts(String modifiers, String key, {L10n? l10n}) {
  return [
    ...hotkeyModifierLabels(modifiers, l10n: l10n),
    if (key.trim().isNotEmpty) key.trim().toUpperCase(),
  ];
}

/// Formats a shortcut like `ctrl+shift` + `D` into `Ctrl+Shift+D`.
String formatHotkeyShortcut(
  String modifiers,
  String key, {
  String separator = '+',
  L10n? l10n,
}) {
  return hotkeyDisplayParts(modifiers, key, l10n: l10n).join(separator);
}

/// Returns a short, localized status label for the active overlay mode.
String overlayModeStatusLabel(OverlayMode mode, L10n l10n) {
  return switch (mode) {
    OverlayMode.inWindow => l10n.statusBarOverlayInWindow,
    OverlayMode.floating => l10n.statusBarOverlayFloating,
    OverlayMode.off => l10n.statusBarOverlayOff,
  };
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

/// Returns a concise, localized label for the active post-processing preset.
String postProcessingStatusLabel({
  required AppSettings settings,
  required L10n l10n,
}) {
  if (!settings.postProcessEnabled) return l10n.settingsOff;
  return switch (settings.postProcessPresetType) {
    PostProcessPreset.cleanup => l10n.statusBarPresetCleanup,
    PostProcessPreset.concise => l10n.statusBarPresetConcise,
    PostProcessPreset.translate => l10n.statusBarPresetTranslate,
  };
}
