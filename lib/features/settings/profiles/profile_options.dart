/// The choices the profile editor offers per field. Each list reads the source
/// the dock and the tray read: the speech-model choices (`sttChoices`), the
/// recognition languages (`whisperLanguages`), the Smart Mode presets
/// (`kTraySmartModePresets`), the after-transcription actions and the
/// microphone devices. The Smart Mode labels repeat the switch in
/// `smart_mode_section.dart`, since no feature file may import `app.dart`.
library;

import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import '../../../core/config/build_config.dart' show kAutoPasteSupported;
import '../../../core/config/settings_enums.dart' show AfterTranscriptionAction;
import '../../../core/config/settings_labels.dart'
    show afterTranscriptionSettingsLabel;
import '../../../core/config/selectable_speech_models.dart';
import '../../../core/config/stt_choice.dart';
import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../services/app_commands/tray_choice_commands.dart'
    show kTraySmartModePresets;
import '../../../services/app_profiles/app_profile.dart';
import '../../../services/microphone_selection_service.dart'
    show micDefaultLabel;

/// Value of the "Unverändert lassen" entry. It never reaches the stored
/// profile: the editor writes `null` (or [AppProfileSmartMode.standard]).
const kProfileKeepValue = 'keep';

/// One entry of a profile field's dropdown.
typedef ProfileOption = ({String value, String label});

/// [options] behind the leading "Unverändert lassen" entry.
List<ProfileOption> withKeepEntry(
  String keepLabel,
  List<ProfileOption> options,
) => [(value: kProfileKeepValue, label: keepLabel), ...options];

/// [options], plus [stored] when the stored value is no longer offered (a
/// model that was removed, a microphone that is unplugged), so the dropdown
/// still shows the value the profile holds.
List<ProfileOption> withStoredEntry(
  List<ProfileOption> options,
  String? stored,
  String Function(String value) unavailableLabel,
) {
  if (stored == null || options.any((o) => o.value == stored)) return options;
  return [...options, (value: stored, label: unavailableLabel(stored))];
}

/// Speech-model choices a profile can select: the downloaded models and the
/// engines that work now. Choices that still need a download are left out, as
/// in the tray. The stored value is the dock's choice value.
List<ProfileOption> profileSpeechModelOptions({
  required List<SelectableSpeechModel> models,
  required L10n l10n,
}) => [
  for (final choice in sttChoicesFrom(models, l10n))
    (value: choice.value, label: choice.label),
];

/// Recognition languages: auto-detect first, then every catalogue language in
/// the UI language, sorted by name, as the dock lists them.
List<ProfileOption> profileLanguageOptions({
  required L10n l10n,
  required LocaleNames? localeNames,
}) {
  final named = [
    for (final code in whisperLanguages.keys)
      (
        value: code,
        label: localeNames?.nameOf(code) ?? whisperLanguages[code]!,
      ),
  ]..sort((a, b) => a.label.compareTo(b.label));
  return [(value: 'auto', label: l10n.settingsLanguageAutoDetect), ...named];
}

/// Smart Mode presets, as the dock and the tray name them.
List<ProfileOption> profileSmartModeOptions(L10n l10n) => [
  for (final preset in kTraySmartModePresets)
    (value: preset, label: smartModePresetLabel(preset, l10n)),
];

/// The label of one Smart Mode preset in the UI language.
String smartModePresetLabel(String preset, L10n l10n) => switch (preset) {
  'cleanup' => l10n.smartModePresetCleanup,
  'concise' => l10n.smartModePresetConcise,
  'translate' => l10n.smartModePresetTranslate,
  _ => l10n.smartModePresetOff,
};

/// After-transcription actions. The paste actions are left out where this
/// build cannot paste (the store sandbox), as in the dock.
List<ProfileOption> profileAfterTranscriptionOptions(
  L10n l10n, {
  bool autoPasteSupported = kAutoPasteSupported,
}) => [
  for (final action in AfterTranscriptionAction.values)
    if (autoPasteSupported ||
        (action != AfterTranscriptionAction.paste &&
            action != AfterTranscriptionAction.clipboardAndPaste))
      (
        value: action.value,
        label: afterTranscriptionSettingsLabel(action, l10n),
      ),
];

/// Microphones: the system default, then the enumerated devices.
List<ProfileOption> profileMicrophoneOptions({
  required L10n l10n,
  required List<String> devices,
}) => [
  (value: micDefaultLabel, label: l10n.settingsMicSystemDefault),
  for (final device in devices)
    if (device != micDefaultLabel && device.isNotEmpty)
      (value: device, label: device),
];
