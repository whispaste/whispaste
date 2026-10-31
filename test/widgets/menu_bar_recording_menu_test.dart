import 'dart:async' show Completer;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/app_profiles/app_profile_choice.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';
import 'package:whispaste/services/app_commands/menu_bar_adapter.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/audio_service.dart';
import 'package:whispaste/services/tray_service.dart' show trayCommandTree;
import 'package:whispaste/widgets/app_menu_bar.dart';

/// Recording notifier whose state a test sets directly.
class _FakeRecording extends RecordingNotifier {
  @override
  RecordingState build() => const RecordingState();

  void setPhase(RecordingPhase phase) => state = RecordingState(phase: phase);
}

class _FixedProfileChoice extends ProfileChoiceController {
  @override
  ProfileChoice build() => const ProfileChoiceAutomatic();
}

/// Settings that never load, so the menu has no settings-dependent entries.
class _PendingSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() => Completer<AppSettings>().future;
}

class _NoProfiles extends AppProfilesController {
  @override
  Future<List<AppProfile>> build() async => const [];
}

void main() {
  test('the Aufnahme menu follows the recording state live', () {
    final container = ProviderContainer(
      overrides: [
        recordingProvider.overrideWith(_FakeRecording.new),
        localeProvider.overrideWithValue(const Locale('en')),
        profileChoiceProvider.overrideWith(_FixedProfileChoice.new),
        appProfilesProvider.overrideWith(_NoProfiles.new),
        audioInputDevicesProvider.overrideWith(
          (ref) async => const ['Default'],
        ),
        settingsProvider.overrideWith(_PendingSettings.new),
      ],
    );
    addTearDown(container.dispose);
    final l10n = lookupL10n(const Locale('en'));

    MenuBarNode toggle() => container
        .read(menuBarRecordingCommandsProvider)
        .firstWhere((n) => n.id == 'toggle_recording');

    expect(toggle().label, l10n.trayStartRecording);

    (container.read(recordingProvider.notifier) as _FakeRecording).setPhase(
      RecordingPhase.recording,
    );

    expect(toggle().label, l10n.trayStopRecording);
  });

  test('the tray tree and the menu bar read the same toggle entry', () {
    final l10n = lookupL10n(const Locale('en'));
    final tray = trayCommandTree(
      l10n,
      recording: const RecordingState(),
      micDeviceLabels: const ['Default'],
      settings: null,
      choices: null,
      profiles: const [],
      profileChoice: const ProfileChoiceAutomatic(),
      actionNeeded: null,
      sidePanelAvailable: false,
    );

    expect(
      tray.firstWhere((c) => c.id == 'toggle_recording').labelKey,
      'trayStartRecording',
    );
  });
}
