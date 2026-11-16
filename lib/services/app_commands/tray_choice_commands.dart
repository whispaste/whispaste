/// Radio groups of the tray that mirror the dock's choice sets (ticket 13,
/// part 1): speech model, Smart Mode preset and the after-transcription
/// action. Each group offers the same options as the dock, and the tray writes
/// the same settings when one is picked (see `TrayService`). The lock is the
/// dock's: only the speech model is locked while a dictation runs.
library;

import '../../core/config/settings_enums.dart' show AfterTranscriptionAction;
import '../../core/config/stt_choice.dart';
import '../app_profiles/app_profile.dart';
import '../app_profiles/app_profile_resolver.dart';
import '../tray_submenu_builder.dart' show TrayRadioOption, buildRadioCommands;
import 'app_command.dart';

/// Id namespace of speech-model entries; the rest is the [SttChoice.value].
const kTraySpeechModelPrefix = 'stt:';

/// Id namespace of Smart Mode entries; the rest is the preset name.
const kTraySmartModePrefix = 'smart:';

/// Id namespace of after-transcription entries; the rest is the action value.
const kTrayOutputPrefix = 'output:';

/// Id namespace of profile entries; the rest is the profile id.
const kTrayProfilePrefix = 'profile:';

/// Ids of the two non-profile entries: follow the rules, or use no profile.
const kTrayProfileAutomaticId = 'profile-auto';
const kTrayProfileNoneId = 'profile-none';

/// Id of the disabled reason line shown above a locked speech-model group.
const kTraySpeechModelLockedId = 'stt-locked';

/// Presets offered by Smart Mode, as in the dock and Settings.
const kTraySmartModePresets = ['off', 'cleanup', 'concise', 'translate'];

/// Label key of a Smart Mode preset, as the dock names it.
String smartModePresetLabelKey(String preset) => switch (preset) {
  'cleanup' => 'smartModePresetCleanup',
  'concise' => 'smartModePresetConcise',
  'translate' => 'smartModePresetTranslate',
  _ => 'smartModePresetOff',
};

/// The downloaded speech models and the engines that work now, with the one
/// in effect checked. Choices that still need a download are left out: the
/// tray never starts a download, the dock and Settings do. While [locked] is
/// true (a dictation runs) every entry is greyed out behind a reason line.
List<AppCommand> buildSpeechModelCommands({
  required List<SttChoice> choices,
  required String current,
  required bool locked,
}) {
  return [
    if (locked) ...const [
      AppCommand(
        id: kTraySpeechModelLockedId,
        labelKey: 'dockMenuSttLockedReason',
        enabled: false,
      ),
      AppCommand.separator(),
    ],
    for (final choice in choices)
      if (!choice.needsDownload)
        AppCommand(
          id: '$kTraySpeechModelPrefix${choice.value}',
          labelKey: choice.label,
          checked: choice.value == current,
          enabled: !locked,
        ),
  ];
}

/// The Smart Mode presets with the standard preset checked.
List<AppCommand> buildSmartModeCommands({required String current}) =>
    buildRadioCommands(
      keyPrefix: kTraySmartModePrefix,
      selected: current,
      options: [
        for (final preset in kTraySmartModePresets)
          TrayRadioOption(
            value: preset,
            labelKey: smartModePresetLabelKey(preset),
          ),
      ],
    );

/// The after-transcription actions, with [current] checked. Like the dock, the
/// paste actions are left out where the build cannot paste (MAS sandbox).
/// [labelFor] gives the final text of an action, see
/// `afterTranscriptionStatusLabel`.
List<AppCommand> buildOutputCommands({
  required AfterTranscriptionAction current,
  required String Function(AfterTranscriptionAction action) labelFor,
  required bool autoPasteSupported,
}) => [
  for (final action in AfterTranscriptionAction.values)
    if (autoPasteSupported || !_needsAutoPaste(action))
      AppCommand(
        id: '$kTrayOutputPrefix${action.value}',
        labelKey: labelFor(action),
        checked: action == current,
      ),
];

bool _needsAutoPaste(AfterTranscriptionAction action) =>
    action == AfterTranscriptionAction.paste ||
    action == AfterTranscriptionAction.clipboardAndPaste;

/// The tray tooltip line: speech model, Smart Mode and output, joined by a
/// middle dot.
String trayTooltipText({
  required String speechModel,
  required String smartMode,
  required String output,
}) => [speechModel, smartMode, output].join(' · ');

/// The Profil submenu: automatic (the per-app rules), no profile, then each
/// stored profile. [current] is the active choice and is checked.
List<AppCommand> buildProfileCommands({
  required List<AppProfile> profiles,
  required ProfileChoice current,
}) {
  if (profiles.isEmpty) return const [];
  return [
    AppCommand(
      id: kTrayProfileAutomaticId,
      labelKey: 'trayProfileAutomatic',
      checked: current is ProfileChoiceAutomatic,
    ),
    AppCommand(
      id: kTrayProfileNoneId,
      labelKey: 'trayProfileNone',
      checked: current is ProfileChoiceNone,
    ),
    const AppCommand.separator(),
    for (final profile in profiles)
      AppCommand(
        id: '$kTrayProfilePrefix${profile.id}',
        labelKey: profile.name,
        checked:
            current is ProfileChoiceProfile && current.profileId == profile.id,
      ),
  ];
}
