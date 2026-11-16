/// #1130 device evidence for the data-key consent flow (#1071) against the
/// real secret store of the platform: macOS login keychain, Windows
/// flutter_secure_storage (DPAPI file), Linux Secret Service.
///
/// The real widgets ([OnboardingDataKeyRow], [DataKeyExplanationWatcher],
/// [PrivacySection]) are driven by their testIDs. A spy store counts every
/// secret-store call, so "nothing asks the system before the tap" and "the
/// second start does not ask again" are measured, not assumed.
///
/// Isolation: the user's real items are never touched. The key is stored
/// under a per-run name (`wp_itest_data_key_<ts>`), on macOS additionally in
/// an own keychain service (`whispaste-itest`), and the marker lives in a
/// temporary folder. Only these items are deleted afterwards.
///
/// Run: `wp-test.sh run <worktree> --host mac|win integration_test/data_key_consent_native_test.dart`
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/config/data_key_store.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/onboarding/data_key_explanation.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';

import '../test/fixtures/test_helpers.dart';
import '../test/test_helpers/nudge_gate_open.dart';
import '../test/test_helpers/test_deadline.dart';

const _storage = FlutterSecureStorage(
  mOptions: MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: 'whispaste-itest',
  ),
);

/// Real store under a per-run key name; counts calls and can simulate a
/// declined system prompt.
class _SpyStore extends SecureKeyStore {
  _SpyStore(this.keyName) : super(_storage);

  final String keyName;
  int reads = 0;
  int writes = 0;
  bool decline = false;

  int get calls => reads + writes;

  String _map(String key) {
    // No `expect` here: this runs inside the app's request chain, next to a
    // guarded pump, and flutter_test rejects nested guarded calls.
    if (key != dataKeyStorageName) {
      throw StateError('unexpected secure-storage key $key');
    }
    return keyName;
  }

  void _maybeDecline() {
    if (decline) {
      throw PlatformException(code: 'errSecUserCanceled', message: 'declined');
    }
  }

  @override
  Future<String?> readKey(String key) async {
    reads++;
    _maybeDecline();
    try {
      return await super.readKey(_map(key));
    } catch (e) {
      debugPrint('NATIVE #1130 read failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> writeKey(String key, String value) async {
    writes++;
    _maybeDecline();
    try {
      await super.writeKey(_map(key), value);
    } catch (e, st) {
      debugPrint('NATIVE #1130 write failed: $e\n$st');
      rethrow;
    }
  }
}

class _Settings extends SettingsNotifier {
  _Settings(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

AppSettings _settingsWith({required bool onboardingCompleted}) => AppSettings(
  onboarding: OnboardingSettings(onboardingCompleted: onboardingCompleted),
);

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final deadline = TestDeadline(const Duration(seconds: 30));
  while (!done()) {
    if (deadline.expired) fail('condition not met');
    // Real time for the platform channel, outside the fake-async guard.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String testId) async {
  final finder = find.byKey(ValueKey<String>(testId));
  await _pumpUntil(tester, () => finder.evaluate().isNotEmpty);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final keyNames = <String>[];
  final dirs = <Directory>[];

  ({_SpyStore spy, DataKeyStore store, Directory dir}) fresh() {
    final name = 'wp_itest_data_key_${DateTime.now().microsecondsSinceEpoch}';
    keyNames.add(name);
    final dir = Directory.systemTemp.createTempSync('wp_itest_data_key_');
    dirs.add(dir);
    final spy = _SpyStore(name);
    return (
      spy: spy,
      store: DataKeyStore(spy, dataDir: () => dir.path),
      dir: dir,
    );
  }

  bool markerExists(Directory dir) =>
      File(p.join(dir.path, dataKeyMarkerFileName)).existsSync();

  tearDownAll(() async {
    for (final k in keyNames) {
      try {
        await _storage.delete(key: k);
      } catch (_) {
        // best-effort teardown
      }
    }
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  testWidgets('new installation: onboarding explains, the tap creates, '
      'the second start does not ask', (tester) async {
    final f = fresh();
    final settings = _Settings(_settingsWith(onboardingCompleted: false));
    await tester.pumpWidget(
      makeTestable(
        // As in the app, the closing onboarding page only appears once the
        // settings are loaded.
        Consumer(
          builder: (context, ref, _) => ref.watch(settingsProvider).hasValue
              ? const SingleChildScrollView(child: OnboardingDataKeyRow())
              : const SizedBox.shrink(),
        ),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(() => settings),
          dataKeyStoreProvider.overrideWithValue(f.store),
        ],
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('onboarding-privacy-data-key-allow'))
          .evaluate()
          .isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 200));

    // Explained by being on screen, but nothing asked the system yet.
    expect(settings.state.value!.onboarding.dataKeyExplained, isTrue);
    expect(f.spy.calls, 0, reason: 'secret store asked before the tap');
    expect(markerExists(f.dir), isFalse);
    expect(await _storage.read(key: f.spy.keyName), isNull);

    await _tap(tester, 'onboarding-privacy-data-key-allow');
    final container = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingDataKeyRow)),
    );
    await _pumpUntil(
      tester,
      () =>
          container.read(dataKeyAccessProvider) !=
          DataKeyAccessStatus.requesting,
    );
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.ready);
    expect(markerExists(f.dir), isTrue);
    final stored = await _storage.read(key: f.spy.keyName);
    expect(stored, isNotNull);
    debugPrint('NATIVE #1130 new-install: created, calls=${f.spy.calls}');

    // Second start: a new container over the same data folder and item.
    final spy2 = _SpyStore(f.spy.keyName);
    final second = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => settings),
        dataKeyStoreProvider.overrideWithValue(
          DataKeyStore(spy2, dataDir: () => f.dir.path),
        ),
      ],
    );
    addTearDown(second.dispose);
    expect(second.read(dataKeyAccessProvider), DataKeyAccessStatus.ready);
    expect(spy2.calls, 0, reason: 'second start asked the secret store');

    // A later need reads the same key and never writes a new one.
    final again = await second.read(dataKeyStoreProvider).obtain();
    expect(again, isA<DataKeyReady>());
    expect((again as DataKeyReady).created, isFalse);
    expect(spy2.writes, 0);
    expect(await _storage.read(key: f.spy.keyName), stored);
    debugPrint('NATIVE #1130 second-start: ready without asking');
  });

  Future<({_SpyStore spy, Directory dir, _Settings settings})> pumpExisting(
    WidgetTester tester,
  ) async {
    final f = fresh();
    final settings = _Settings(_settingsWith(onboardingCompleted: true));
    await tester.pumpWidget(
      makeTestable(
        const DataKeyExplanationWatcher(
          child: SingleChildScrollView(child: PrivacySection()),
        ),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(() => settings),
          dataKeyStoreProvider.overrideWithValue(f.store),
          nudgeGateOpenOverride(),
        ],
      ),
    );
    await _pumpUntil(
      tester,
      () => find
          .byKey(const ValueKey('data-key-explanation-later'))
          .evaluate()
          .isNotEmpty,
    );
    expect(f.spy.calls, 0, reason: 'secret store asked before the dialog');
    return (spy: f.spy, dir: f.dir, settings: settings);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PrivacySection)));

  testWidgets('existing user: "Later" asks nothing, the dialog stays away, '
      'Privacy offers the way back', (tester) async {
    final e = await pumpExisting(tester);
    await _tap(tester, 'data-key-explanation-later');
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('data-key-explanation-later')),
      findsNothing,
    );
    expect(e.settings.state.value!.onboarding.dataKeyExplained, isTrue);
    expect(e.spy.calls, 0);
    expect(markerExists(e.dir), isFalse);
    expect(
      containerOf(tester).read(dataKeyAccessProvider),
      DataKeyAccessStatus.notRequested,
    );

    // Exactly once: a rebuild does not bring the dialog back.
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.byKey(const ValueKey('data-key-explanation-later')),
      findsNothing,
    );

    await _tap(tester, 'privacy-data-key-allow');
    final container = containerOf(tester);
    await _pumpUntil(
      tester,
      () =>
          container.read(dataKeyAccessProvider) !=
          DataKeyAccessStatus.requesting,
    );
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.ready);
    expect(await _storage.read(key: e.spy.keyName), isNotNull);
    debugPrint('NATIVE #1130 existing-later: privacy allow -> ready');
  });

  testWidgets('existing user: "Create key" in the dialog creates the key', (
    tester,
  ) async {
    final e = await pumpExisting(tester);
    await _tap(tester, 'data-key-explanation-allow');
    final container = containerOf(tester);
    await _pumpUntil(
      tester,
      () =>
          container.read(dataKeyAccessProvider) !=
          DataKeyAccessStatus.requesting,
    );
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.ready);
    expect(find.byKey(const ValueKey('data-key-outcome-close')), findsNothing);
    expect(markerExists(e.dir), isTrue);
    debugPrint('NATIVE #1130 existing-allow: ready');
  });

  testWidgets('existing user: a declined prompt leaves a calm state, '
      'nothing written, retry in Privacy', (tester) async {
    final e = await pumpExisting(tester);
    e.spy.decline = true;
    await _tap(tester, 'data-key-explanation-allow');
    await _tap(tester, 'data-key-outcome-close');
    final container = containerOf(tester);
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.declined);
    expect(markerExists(e.dir), isFalse);
    expect(await _storage.read(key: e.spy.keyName), isNull);

    e.spy.decline = false;
    await _tap(tester, 'privacy-data-key-allow');
    await _pumpUntil(
      tester,
      () =>
          container.read(dataKeyAccessProvider) !=
          DataKeyAccessStatus.requesting,
    );
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.ready);
    debugPrint('NATIVE #1130 existing-declined: retry -> ready');
  });

  testWidgets('a missing key is reported, never silently replaced', (
    tester,
  ) async {
    final f = fresh();
    expect(await f.store.obtain(), isA<DataKeyReady>());
    await _storage.delete(key: f.spy.keyName);

    final spy2 = _SpyStore(f.spy.keyName);
    final result = await DataKeyStore(spy2, dataDir: () => f.dir.path).obtain();
    expect(result, isA<DataKeyLost>());
    expect(spy2.writes, 0);
    expect(await _storage.read(key: f.spy.keyName), isNull);
    debugPrint('NATIVE #1130 lost: reported, not replaced');
  });
}
