/// Tests confirming the `retainRecentAudio` toggle in [PrivacySection]
/// writes through to `privacy.retainRecentAudio` — the setting that gates
/// the rotating WAV-retention feature in `RecordingOrchestrator`.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/encryption_preference.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/logging/crash_reporter.dart';
import 'package:whispaste/core/logging/crash_reporting_consent.dart';
import 'package:whispaste/features/settings/data_key/data_key_flows.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/services/app_restart_service.dart';
import 'package:whispaste/services/path_service.dart' as paths;
import 'package:whispaste/widgets/wp_dropdown.dart';

import '../../../fixtures/test_helpers.dart';

class FakeSettingsNotifier extends SettingsNotifier {
  FakeSettingsNotifier([AppSettings? settings])
    : _settings = settings ?? AppSettings.defaults;

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

/// Data-key status fixed for a test; counts the taps on "Create key"/"Try
/// again" instead of asking the system.
class _FixedDataKeyAccess extends DataKeyAccessNotifier {
  _FixedDataKeyAccess(this._status);

  final DataKeyAccessStatus _status;
  int requests = 0;
  int replacements = 0;

  @override
  DataKeyAccessStatus build() => _status;

  @override
  Future<DataKeyAccessStatus> request() async {
    requests++;
    return _status;
  }

  @override
  Future<DataKeyAccessStatus> replaceLostKey() async {
    replacements++;
    return DataKeyAccessStatus.ready;
  }
}

/// No backup recorded; keeps the row away from the real marker on disk.
class _NeverBackedUp extends DataKeyBackupNotifier {
  @override
  DateTime? build() => null;
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('PrivacySection retain-recent-audio toggle', () {
    testWidgets('defaults to off', (tester) async {
      final notifier = FakeSettingsNotifier();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey('settings-row-privacy-retain-audio'),
      );
      expect(row, findsOneWidget);
      final toggle = tester.widget<Switch>(
        find.descendant(of: row, matching: find.byType(Switch)),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets('toggling it writes privacy.retainRecentAudio', (tester) async {
      final notifier = FakeSettingsNotifier(
        const AppSettings(privacy: PrivacySettings(retainRecentAudio: false)),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(
        const ValueKey('settings-row-privacy-retain-audio'),
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(notifier.state.value!.privacy.retainRecentAudio, isTrue);
    });
  });

  testWidgets(
    'audio count is disabled until retention is on and saves choices',
    (tester) async {
      final notifier = FakeSettingsNotifier();
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('privacy-retained-audio-count'));
      expect(tester.widget<WpDropdown<String>>(picker).onChanged, isNull);
      final row = find.byKey(
        const ValueKey('settings-row-privacy-retain-audio'),
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('privacy-retained-audio-count-item-50')).last,
      );
      await tester.pumpAndSettle();
      expect(notifier.state.value!.privacy.retainedAudioCount, 50);
    },
  );

  group('PrivacySection error-reporting toggle', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp_privacy_');
    });

    tearDown(() async {
      await CrashReporter.instance?.dispose();
      dir.deleteSync(recursive: true);
    });

    testWidgets('opting back in says it takes effect after a restart', (
      tester,
    ) async {
      final marker = CrashReportingConsentMarker(directory: dir.path)
        ..record(granted: false);
      // Launched after an opt-out: Sentry was never started.
      CrashReporter.init(consentGranted: false, consentMarker: marker);
      final notifier = FakeSettingsNotifier(
        const AppSettings(behavior: BehaviorSettings(errorReporting: false)),
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [settingsProvider.overrideWith(() => notifier)],
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(l10n.settingsErrorReportingRestartHint),
        findsNothing,
      );

      final row = find.byKey(
        const ValueKey('settings-row-privacy-error-reporting'),
      );
      await tester.tap(find.descendant(of: row, matching: find.byType(Switch)));
      await tester.pumpAndSettle();

      expect(notifier.state.value!.behavior.errorReporting, isTrue);
      expect(CrashReporter.instance!.consentGranted, isTrue);
      expect(marker.optedOut, isFalse);
      expect(
        find.textContaining(l10n.settingsErrorReportingRestartHint),
        findsOneWidget,
      );
    });
  });

  group('PrivacySection data-key row (#1165)', () {
    const backup = ValueKey('privacy-data-key-backup');
    const restore = ValueKey('privacy-data-key-restore');
    const allow = ValueKey('privacy-data-key-allow');

    late _FixedDataKeyAccess access;
    late List<String> flows;

    Future<void> pump(
      WidgetTester tester,
      DataKeyAccessStatus status, {
      bool realFlows = false,
    }) async {
      access = _FixedDataKeyAccess(status);
      flows = [];
      // The section is taller than the default 800x600 surface; the buttons
      // would sit off-screen and taps would miss.
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [
            settingsProvider.overrideWith(FakeSettingsNotifier.new),
            dataKeyAccessProvider.overrideWith(() => access),
            dataKeyBackupProvider.overrideWith(_NeverBackedUp.new),
            if (!realFlows)
              dataKeyRestoreFlowProvider.overrideWithValue(
                (_) async => flows.add('restore'),
              ),
          ],
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final status in [
      DataKeyAccessStatus.ready,
      DataKeyAccessStatus.fileFallback,
    ]) {
      testWidgets('${status.name}: only "Back up", which opens the backup', (
        tester,
      ) async {
        await pump(tester, status);
        expect(find.byKey(restore), findsNothing);
        expect(find.byKey(allow), findsNothing);

        await tester.tap(find.byKey(backup));
        await tester.pumpAndSettle();
        const cancel = ValueKey('data-key-backup-cancel');
        expect(find.byKey(cancel), findsOneWidget);
        await tester.tap(find.byKey(cancel));
        await tester.pumpAndSettle();
        expect(access.requests, 0);
      });
    }

    testWidgets('lost: only "Restore", which opens the restore', (
      tester,
    ) async {
      await pump(tester, DataKeyAccessStatus.lost);
      expect(find.byKey(backup), findsNothing);
      expect(find.byKey(allow), findsNothing);

      await tester.tap(find.byKey(restore));
      await tester.pumpAndSettle();
      expect(flows, ['restore']);
      expect(access.requests, 0, reason: 'never asks for a new key');
    });

    for (final status in [
      DataKeyAccessStatus.keyringLocked,
      DataKeyAccessStatus.declined,
      DataKeyAccessStatus.notRequested,
    ]) {
      testWidgets('${status.name}: only the retry, which asks again', (
        tester,
      ) async {
        await pump(tester, status);
        expect(find.byKey(backup), findsNothing);
        expect(find.byKey(restore), findsNothing);

        await tester.tap(find.byKey(allow));
        await tester.pumpAndSettle();
        expect(access.requests, 1);
        expect(flows, isEmpty);
      });
    }

    group('restore flow (#1167)', () {
      const cancel = ValueKey('data-key-restore-cancel');
      const newKey = ValueKey('data-key-restore-new');
      const confirmNew = ValueKey('confirm-dialog-confirm');
      const keepOld = ValueKey('confirm-dialog-cancel');

      Future<void> openRestore(WidgetTester tester) async {
        await pump(tester, DataKeyAccessStatus.lost, realFlows: true);
        await tester.tap(find.byKey(restore));
        await tester.pumpAndSettle();
      }

      testWidgets('"Restore" opens the dialog; cancel changes nothing', (
        tester,
      ) async {
        await openRestore(tester);
        expect(find.byKey(cancel), findsOneWidget);
        await tester.tap(find.byKey(cancel));
        await tester.pumpAndSettle();
        expect(find.byKey(cancel), findsNothing);
        expect(access.replacements, 0);
        expect(access.requests, 0);
      });

      testWidgets('"Create new key" warns first; declining keeps the key', (
        tester,
      ) async {
        await openRestore(tester);
        await tester.tap(find.byKey(newKey));
        await tester.pumpAndSettle();
        expect(find.byKey(keepOld), findsOneWidget);
        await tester.tap(find.byKey(keepOld));
        await tester.pumpAndSettle();
        expect(access.replacements, 0);
      });

      testWidgets('"Create new key" replaces only after the confirmation', (
        tester,
      ) async {
        await openRestore(tester);
        await tester.tap(find.byKey(newKey));
        await tester.pumpAndSettle();
        expect(access.replacements, 0);
        await tester.tap(find.byKey(confirmNew));
        await tester.pumpAndSettle();
        expect(access.replacements, 1);
        expect(access.requests, 0);
      });
    });
  });

  // The encryption switch (#1022): on by default, a change applies at the
  // next start, and the row offers that restart.
  group('encryption switch', () {
    // Own folder: the switch writes its marker below the app data folder.
    late Directory sandbox;
    String? previousOverride;
    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('wp_enc_switch_');
      previousOverride = paths.appDataDirOverride;
      paths.appDataDirOverride = sandbox.path;
      resetEncryptionSessionForTesting();
    });
    tearDown(() {
      paths.appDataDirOverride = previousOverride;
      resetEncryptionSessionForTesting();
      sandbox.deleteSync(recursive: true);
    });

    testWidgets('off, restart, back on: the whole click sequence', (
      tester,
    ) async {
      var relaunches = 0;
      final restart = AppRestartService(
        isDictationBusy: () => false,
        shutdown: () async {},
        releaseInstanceLock: () async {},
        macRelaunch: () async => relaunches++,
        spawn: (_, _) async => relaunches++,
        endProcess: () {},
      );
      await tester.pumpWidget(
        makeTestable(
          const SingleChildScrollView(child: PrivacySection()),
          overrides: [
            settingsProvider.overrideWith(FakeSettingsNotifier.new),
            appRestartServiceProvider.overrideWithValue(restart),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('privacy-encryption-toggle'));
      final restartButton = find.byKey(
        const ValueKey('privacy-encryption-restart'),
      );
      Text subtitle() => tester.widget<Text>(
        find.byKey(const ValueKey('privacy-encryption-subtitle')),
      );
      final preference = EncryptionPreference(paths.appDataDir());

      // Default on, nothing to restart.
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(restartButton, findsNothing);
      expect(subtitle().data, l10n.settingsEncryptionSubtitleOn);

      // Off: saved for the next start, the restart is offered.
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isFalse);
      expect(preference.wanted, isFalse);
      expect(preference.switchPending, isTrue);
      expect(
        subtitle().data,
        '${l10n.settingsEncryptionSubtitleOff} '
        '${l10n.settingsEncryptionRestartHint}',
      );
      expect(restartButton, findsOneWidget);
      expect(
        find.descendant(
          of: restartButton,
          matching: find.text(l10n.actionRestartApp),
        ),
        findsOneWidget,
      );

      await tester.tap(restartButton);
      await tester.pumpAndSettle();
      expect(relaunches, 1);

      // Back on before the restart: the wish is taken back.
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(toggle).value, isTrue);
      expect(preference.wanted, isTrue);
      expect(restartButton, findsNothing);
    });
  });
}
