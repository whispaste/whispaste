/// The tray's choice groups write the same settings as the dock. A click on a
/// speech-model entry is refused while a dictation runs, like the greyed-out
/// entry; Smart Mode and the after-transcription action always apply, and the
/// tooltip carries the current state.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/services/app_commands/tray_choice_commands.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_choice.dart';
import 'package:whispaste/services/app_profiles/app_profile_repository.dart';
import 'package:whispaste/services/app_profiles/app_profile_resolver.dart';
import 'package:whispaste/services/tray_host_probe.dart';
import 'package:whispaste/services/tray_service.dart';
import 'package:whispaste/services/window_activation.dart';

/// Serves a fixed profile list in tests, without touching the database.
class _FixedProfiles extends AppProfilesController {
  _FixedProfiles(this._profiles);
  final List<AppProfile> _profiles;

  @override
  Future<List<AppProfile>> build() async => _profiles;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tray_manager');
  late List<String> tooltips;

  setUp(() {
    tooltips = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setToolTip') {
            tooltips.add((call.arguments as Map)['toolTip'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<ProviderContainer> startTray() async {
    final container = ProviderContainer(
      overrides: [
        windowActivatorProvider.overrideWithValue(() async {}),
        settingsProvider.overrideWith(_FixedSettings.new),
      ],
    );
    addTearDown(container.dispose);
    final tray = container.read(trayServiceProvider.notifier);
    await tray.initDone;
    await _settle();
    return container;
  }

  test('a Smart Mode entry writes the standard preset', () async {
    final container = await startTray();
    final tray = container.read(trayServiceProvider.notifier);
    tray.onTrayMenuItemClick(MenuItem(key: 'smart:cleanup'));
    await _settle();
    final settings = container.read(settingsProvider).value!;
    expect(settings.smartMode.standardPreset, 'cleanup');
  });

  test('an output entry writes the after-transcription action', () async {
    final container = await startTray();
    final tray = container.read(trayServiceProvider.notifier);
    tray.onTrayMenuItemClick(MenuItem(key: 'output:paste'));
    await _settle();
    final settings = container.read(settingsProvider).value!;
    expect(settings.afterTranscriptionAction, AfterTranscriptionAction.paste);
  });

  test('a speech-model entry applies the choice while idle', () async {
    final container = await startTray();
    final tray = container.read(trayServiceProvider.notifier);
    tray.onTrayMenuItemClick(MenuItem(key: 'stt:parakeet'));
    await _settle();
    final settings = container.read(settingsProvider).value!;
    expect(sttChoiceValue(settings), 'parakeet');
  });

  test('a speech-model entry is refused while a dictation runs', () async {
    final container = await startTray();
    final tray = container.read(trayServiceProvider.notifier);
    tray.updateRecordingState(
      const RecordingState(phase: RecordingPhase.recording),
    );
    await _settle();
    final before = sttChoiceValue(container.read(settingsProvider).value!);
    tray.onTrayMenuItemClick(MenuItem(key: 'stt:parakeet'));
    await _settle();
    final after = sttChoiceValue(container.read(settingsProvider).value!);
    expect(after, before);
    expect(after, isNot('parakeet'));
  });

  test('Linux without a tray host raises the missing-tray flag', () async {
    final container = ProviderContainer(
      overrides: [
        windowActivatorProvider.overrideWithValue(() async {}),
        settingsProvider.overrideWith(_FixedSettings.new),
        trayHostProbeProvider.overrideWithValue(() async => false),
      ],
    );
    addTearDown(container.dispose);
    await container.read(trayServiceProvider.notifier).initDone;
    await _settle();
    expect(
      container.read(trayHostMissingProvider),
      Platform.isLinux,
      reason: 'the probe is only asked on Linux',
    );
  });

  test(
    'a profile entry sets the manual choice once and announces it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          windowActivatorProvider.overrideWithValue(() async {}),
          settingsProvider.overrideWith(_FixedSettings.new),
          appProfilesProvider.overrideWith(
            () => _FixedProfiles(const [AppProfile(id: 'mail', name: 'Mail')]),
          ),
        ],
      );
      addTearDown(container.dispose);
      final tray = container.read(trayServiceProvider.notifier);
      await tray.initDone;
      await _settle();

      tray.onTrayMenuItemClick(MenuItem(key: 'profile:mail'));
      await _settle();
      final choice = container.read(profileChoiceProvider);
      expect(choice, isA<ProfileChoiceProfile>());
      expect(
        container.read(profileSwitchFeedbackProvider)?.profileName,
        'Mail',
      );
      final serial = container.read(profileSwitchFeedbackProvider)?.serial;

      tray.onTrayMenuItemClick(MenuItem(key: 'profile:mail'));
      await _settle();
      expect(
        container.read(profileSwitchFeedbackProvider)?.serial,
        serial,
        reason: 'the same pick must not announce again',
      );

      tray.onTrayMenuItemClick(MenuItem(key: kTrayProfileAutomaticId));
      await _settle();
      expect(
        container.read(profileChoiceProvider),
        isA<ProfileChoiceAutomatic>(),
      );
    },
  );

  test('the tooltip names the speech model, Smart Mode and output', () async {
    await startTray();
    expect(tooltips, isNotEmpty);
    final parts = tooltips.last.split(' · ');
    expect(parts, hasLength(3));
    expect(parts[1], startsWith('Smart Mode'));
  });
}

/// Lets the async settings and the tray's listeners run to completion.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Settings at the defaults, updated in memory.
class _FixedSettings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings();

  /// Keeps the update in memory: the real path persists to disk.
  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? const AppSettings()));
  }
}
