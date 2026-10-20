/// Activating a profile (ticket 13, part 2): the fields a profile sets are
/// written into the settings, the others keep their value.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import 'app_profile.dart';
import 'app_profile_choice.dart';
import 'app_profile_repository.dart';
import 'app_profile_resolver.dart';

/// [settings] with the non-null fields of [profile] applied.
AppSettings settingsWithProfile(AppSettings settings, AppProfile profile) {
  final preset = profile.smartMode.preset;
  return settings.copyWithSections(
    stt: profile.asrLanguage == null && profile.modelId == null
        ? null
        : settings.stt.copyWith(
            language: profile.asrLanguage,
            model: profile.modelId,
          ),
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
