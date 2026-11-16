/// Activating a profile (ticket 13, part 2): the fields a profile sets are
/// written into the settings, the others keep their value.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/stt_choice.dart';
import 'app_profile.dart';
import 'app_profile_choice.dart';
import 'app_profile_repository.dart';
import 'app_profile_resolver.dart';

/// [settings] with the non-null fields of [profile] applied. A profile's
/// [AppProfile.modelId] is a speech-model choice in the dock's format (see
/// `SttChoice`), so the engine and provider follow it as well.
AppSettings settingsWithProfile(AppSettings settings, AppProfile profile) {
  final preset = profile.smartMode.preset;
  final choice = profile.modelId;
  final withModel = choice == null
      ? settings
      : applySttChoice(settings, choice);
  return withModel.copyWithSections(
    stt: profile.asrLanguage == null
        ? null
        : withModel.stt.copyWith(language: profile.asrLanguage),
    audioInput: profile.microphone == null
        ? null
        : settings.audioInput.copyWith(microphone: profile.microphone),
    afterTranscriptionSection: profile.afterTranscription == null
        ? null
        : settings.afterTranscriptionSection.copyWith(
            afterTranscription: profile.afterTranscription,
          ),
    smartMode: preset == null
        ? null
        : settings.smartMode.copyWith(standardPreset: preset.name),
  );
}

/// Makes a profile the active choice: persists the choice, writes the
/// profile's fields into the settings and announces the switch once.
class ProfileActivator {
  ProfileActivator(this._ref);

  final Ref _ref;

  /// Activates [profile]. Repeating the activation of the active profile
  /// changes nothing and announces nothing.
  Future<void> activate(AppProfile profile) async {
    final changed = _ref
        .read(profileChoiceProvider.notifier)
        .select(ProfileChoiceProfile(profile.id));
    await _ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => settingsWithProfile(s, profile));
    if (!changed) return;
    _ref
        .read(profileSwitchFeedbackProvider.notifier)
        .announce(
          choice: ProfileChoiceProfile(profile.id),
          profileName: profile.name,
        );
  }

  /// Activates the stored profile with [profileId], if it still exists.
  Future<void> activateById(String profileId) async {
    final profiles =
        _ref.read(appProfilesProvider).value ?? const <AppProfile>[];
    for (final profile in profiles) {
      if (profile.id == profileId) {
        await activate(profile);
        return;
      }
    }
  }
}

final profileActivatorProvider = Provider<ProfileActivator>(
  ProfileActivator.new,
);

/// Whether [settings] still holds every value [profile] sets. A field the
/// profile leaves unchanged (null) never ends the profile.
bool profileStillApplies(AppProfile profile, AppSettings settings) {
  final preset = profile.smartMode.preset;
  return (profile.asrLanguage == null ||
          settings.stt.language == profile.asrLanguage) &&
      (profile.modelId == null ||
          sttChoiceValue(settings) == profile.modelId) &&
      (profile.microphone == null ||
          settings.audioInput.microphone == profile.microphone) &&
      (profile.afterTranscription == null ||
          settings.afterTranscriptionSection.afterTranscription ==
              profile.afterTranscription) &&
      (preset == null || settings.smartMode.standardPreset == preset.name);
}

/// Ends the "active profile" marker (ticket 13, part 2) when a manual change
/// in the dock, the tray or Settings moves a field the active profile set.
/// The choice then returns to automatic, so the rules decide again. Watch it
/// once, from the service bootstrap.
final profileMarkerProvider = Provider<void>((ref) {
  ref.listen(settingsProvider, (_, next) {
    final settings = next.value;
    final choice = ref.read(profileChoiceProvider);
    if (settings == null || choice is! ProfileChoiceProfile) return;
    final profiles = ref.read(appProfilesProvider).value;
    final profile = profiles
        ?.where((p) => p.id == choice.profileId)
        .firstOrNull;
    if (profile == null || profileStillApplies(profile, settings)) return;
    ref
        .read(profileChoiceProvider.notifier)
        .select(const ProfileChoiceAutomatic());
  });
});
