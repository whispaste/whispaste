/// #1167 device evidence for restoring a lost data key (or knowingly
/// creating a new one) against the real secret store of the platform:
/// Windows flutter_secure_storage (DPAPI file), Linux Secret Service or the
/// owner-only file fallback, macOS login keychain.
///
/// The real [PrivacySection] and restore dialog are driven by their testIDs.
/// "Lost" is the state of a copied data folder on a new device: the marker
/// is there, the key item is gone. The sealed recording stands for the
/// readable history: it opens again only with the very same key.
///
/// Isolation: the user's real items are never touched. The key lives under
/// a per-run name, on macOS in an own keychain service, and the data folder
/// is a temporary one. Only these are deleted afterwards.
///
/// Drag & drop needs a real window manager gesture; the dropped path takes
/// the same route as the chosen one ([readDataKeyBackupFile]), which is
/// exercised here with a real file.
///
/// Run: `wp-test.sh run <worktree> --host mac|win integration_test/data_key_restore_native_test.dart`
/// or via `labctl test <guest> -- …`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/config/data_key_backup.dart';
import 'package:whispaste/core/config/data_key_store.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/features/settings/data_key_restore_flow.dart';
import 'package:whispaste/features/settings/sections/privacy_section.dart';
import 'package:whispaste/services/audio/encryption/recording_cipher.dart';

import '../test/fixtures/test_helpers.dart';
import '../test/test_helpers/nudge_gate_open.dart';
import '../test/test_helpers/test_deadline.dart';

const _storage = FlutterSecureStorage(
  mOptions: MacOsOptions(
    usesDataProtectionKeychain: false,
    accountName: 'whispaste-itest',
  ),
);

/// Real store under a per-run key name.
class _RunStore extends SecureKeyStore {
  _RunStore(this.keyName) : super(_storage);

  final String keyName;

  String _map(String key) {
    if (key != dataKeyStorageName) {
      throw StateError('unexpected secure-storage key $key');
    }
    return keyName;
  }

  @override
  Future<String?> readKey(String key) => super.readKey(_map(key));

  @override
  Future<void> writeKey(String key, String value) =>
      super.writeKey(_map(key), value);
}

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings(
    onboarding: OnboardingSettings(
      onboardingCompleted: true,
      dataKeyExplained: true,
    ),
  );

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? await build()));
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  final deadline = TestDeadline(const Duration(seconds: 30));
  while (!done()) {
    if (deadline.expired) fail('condition not met');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pump();
}

Finder _id(String testId) => find.byKey(ValueKey<String>(testId));

Future<void> _tap(WidgetTester tester, String testId) async {
  await _pumpUntil(tester, () => _id(testId).evaluate().isNotEmpty);
  await tester.ensureVisible(_id(testId));
  await tester.tap(_id(testId));
  await tester.pump();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final keyNames = <String>[];
  final dirs = <Directory>[];

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

  /// A data folder with a real key, one sealed "history" file, and the key
  /// then lost on this device.
  Future<
    ({
      DataKeyStore store,
      Directory dir,
      String keyName,
      List<int> keyBytes,
      String fingerprint,
      Uint8List sealed,
    })
  >
  lostSetup() async {
    final name = 'wp_itest_data_key_${DateTime.now().microsecondsSinceEpoch}';
    keyNames.add(name);
    final dir = Directory.systemTemp.createTempSync('wp_itest_restore_');
    dirs.add(dir);
    final store = DataKeyStore(_RunStore(name), dataDir: () => dir.path);
    final created = await store.obtain();
    expect(created, isA<DataKeyReady>());
    final key = (created as DataKeyReady).key;
    final bytes = key.bytes;
    final sealed = sealRecording(
      Uint8List.fromList('history line'.codeUnits),
      deriveRecordingKey(bytes),
    );
    // New device: the marker came along with the folder, the key did not.
    await _storage.delete(key: name);
    final fallback = File(p.join(dir.path, dataKeyFallbackFileName));
    if (fallback.existsSync()) fallback.deleteSync();
    // A fresh store, as after a restart: the first one caches the key.
    final fresh = DataKeyStore(_RunStore(name), dataDir: () => dir.path);
    final lost = await fresh.obtain();
    expect(lost, isA<DataKeyLost>(), reason: 'setup must reach "lost"');
    return (
      store: fresh,
      dir: dir,
      keyName: name,
      keyBytes: bytes,
      fingerprint: _fp(bytes),
      sealed: sealed,
    );
  }

  Future<ProviderContainer> pumpPrivacy(
    WidgetTester tester,
    DataKeyStore store,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: PrivacySection()),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          dataKeyStoreProvider.overrideWithValue(store),
          nudgeGateOpenOverride(),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PrivacySection)),
    );
    // The app learns "lost" from the first deliberate need; do the same.
    await tester.runAsync(
      () => container.read(dataKeyAccessProvider.notifier).request(),
    );
    await tester.pump();
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.lost);
    return container;
  }

  void expectReadable(DataKeyReady ready, Uint8List sealed) {
    final opened = openRecording(sealed, deriveRecordingKey(ready.key.bytes));
    expect(String.fromCharCodes(opened), 'history line');
  }

  testWidgets('lost: the recovery code restores the same key and history', (
    tester,
  ) async {
    final s = await lostSetup();
    final container = await pumpPrivacy(tester, s.store);

    await _tap(tester, 'privacy-data-key-restore');
    await _pumpUntil(
      tester,
      () => _id('data-key-restore-code').evaluate().isNotEmpty,
    );
    await tester.enterText(
      _id('data-key-restore-code'),
      dataKeyRecoveryCode(s.keyBytes),
    );
    await tester.pump();
    await _tap(tester, 'data-key-restore-confirm');
    await _pumpUntil(
      tester,
      () => container.read(dataKeyAccessProvider) != DataKeyAccessStatus.lost,
    );
    await tester.pump(const Duration(milliseconds: 500));

    final again = await tester.runAsync(() => s.store.obtain());
    expect(again, isA<DataKeyReady>());
    final ready = again! as DataKeyReady;
    expect(_fp(ready.key.bytes), s.fingerprint);
    expectReadable(ready, s.sealed);
    debugPrint('NATIVE #1167 code: restored, fingerprint equal, history open');
  });

  testWidgets('lost: a backup file restores the same key and history', (
    tester,
  ) async {
    final s = await lostSetup();
    final file = File(
      p.join(s.dir.path, 'key.$dataKeyBackupExtension'),
    )..writeAsStringSync(dataKeyBackupFileContents(s.keyBytes, DateTime.now()));
    // The route of "choose" and of "drop": path → parser → access → store.
    final parsed = await readDataKeyBackupFile(file.path);
    expect(parsed, isA<DataKeyBackupValid>());

    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_Settings.new),
        dataKeyStoreProvider.overrideWithValue(s.store),
      ],
    );
    addTearDown(container.dispose);
    final result = await container
        .read(dataKeyAccessProvider.notifier)
        .restore((parsed as DataKeyBackupValid).bytes);
    expect(result, isA<DataKeyRestored>());
    final ready = (await s.store.obtain()) as DataKeyReady;
    expect(_fp(ready.key.bytes), s.fingerprint);
    expectReadable(ready, s.sealed);
    debugPrint('NATIVE #1167 file: restored, fingerprint equal, history open');
  });

  testWidgets('wrong or damaged backups change nothing', (tester) async {
    final semantics = tester.ensureSemantics();
    final s = await lostSetup();
    final markerBefore = File(
      p.join(s.dir.path, dataKeyMarkerFileName),
    ).readAsStringSync();
    final container = await pumpPrivacy(tester, s.store);

    // A well-formed code of ANOTHER key.
    await _tap(tester, 'privacy-data-key-restore');
    await _pumpUntil(
      tester,
      () => _id('data-key-restore-code').evaluate().isNotEmpty,
    );
    await tester.enterText(
      _id('data-key-restore-code'),
      dataKeyRecoveryCode(List<int>.generate(dataKeyLength, (i) => 255 - i)),
    );
    await tester.pump();
    await _tap(tester, 'data-key-restore-confirm');
    await _pumpUntil(
      tester,
      () => find
          .bySemanticsIdentifier('data-key-restore-error')
          .evaluate()
          .isNotEmpty,
    );

    // A mistyped code (checksum fails).
    final code = dataKeyRecoveryCode(s.keyBytes);
    final typo = (code[0] == '0' ? '1' : '0') + code.substring(1);
    await tester.enterText(_id('data-key-restore-code'), typo);
    await tester.pump();
    await _tap(tester, 'data-key-restore-confirm');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.bySemanticsIdentifier('data-key-restore-error'),
      findsOneWidget,
    );

    // A damaged file.
    final bad = File(p.join(s.dir.path, 'bad.$dataKeyBackupExtension'))
      ..writeAsBytesSync([0xff, 0xfe, 0x00, 0xc3]);
    final parsed = await readDataKeyBackupFile(bad.path);
    expect(parsed, isA<DataKeyBackupInvalid>());

    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.lost);
    expect(
      File(p.join(s.dir.path, dataKeyMarkerFileName)).readAsStringSync(),
      markerBefore,
    );
    expect(await _storage.read(key: s.keyName), isNull);
    debugPrint('NATIVE #1167 wrong: refused, marker and store untouched');
    semantics.dispose();
  });

  testWidgets('"Create new key" warns first and keeps the old files', (
    tester,
  ) async {
    final s = await lostSetup();
    final container = await pumpPrivacy(tester, s.store);

    await _tap(tester, 'privacy-data-key-restore');
    await _tap(tester, 'data-key-restore-new');
    await _pumpUntil(
      tester,
      () => _id('confirm-dialog-cancel').evaluate().isNotEmpty,
    );
    // Warning is up; nothing replaced yet.
    expect(container.read(dataKeyAccessProvider), DataKeyAccessStatus.lost);
    expect(await _storage.read(key: s.keyName), isNull);
    await _tap(tester, 'confirm-dialog-confirm');
    await _pumpUntil(
      tester,
      () => const {
        DataKeyAccessStatus.ready,
        DataKeyAccessStatus.fileFallback,
      }.contains(container.read(dataKeyAccessProvider)),
    );

    final now = container.read(dataKeyAccessProvider);
    expect(
      now == DataKeyAccessStatus.ready ||
          now == DataKeyAccessStatus.fileFallback,
      isTrue,
    );
    final names = s.dir.listSync().map((e) => p.basename(e.path)).toList();
    expect(
      names.where((n) => n.contains('.lost.')),
      isNotEmpty,
      reason: 'old marker must be kept under an archive name: $names',
    );
    final fresh = (await s.store.obtain()) as DataKeyReady;
    expect(_fp(fresh.key.bytes), isNot(s.fingerprint));
    // Old encrypted data stays unreadable, as the warning says.
    expect(
      () => openRecording(s.sealed, deriveRecordingKey(fresh.key.bytes)),
      throwsA(isA<RecordingCipherException>()),
    );
    debugPrint('NATIVE #1167 new: warned, archived, old history unreadable');
  });
}

String _fp(List<int> bytes) => sha256.convert(bytes).toString();
