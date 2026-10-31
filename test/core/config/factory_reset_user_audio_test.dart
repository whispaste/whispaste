import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/factory_reset/factory_reset_coordinator.dart';
import 'package:whispaste/services/path_service.dart' as paths;

/// Secure storage that accepts every delete, so the reset runs to its end.
class _AcceptingSecureKeyStore extends SecureKeyStore {
  @override
  Future<void> deleteKey(String key) async {}
}

/// Subprocess that is already stopped, so the reset does not wait on it.
class _StoppedSubprocess implements SubprocessController {
  @override
  Future<void> kill() async {}

  @override
  Future<void> forceKill() async {}

  @override
  Future<bool> waitForExit({required Duration timeout}) async => true;
}

void main() {
  late HistoryDatabase db;
  late ProviderContainer container;
  late Directory appData;

  setUp(() async {
    appData = Directory.systemTemp.createTempSync('wp71-reset-audio-');
    paths.appDataDirOverride = appData.path;
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        secureKeyStoreProvider.overrideWithValue(_AcceptingSecureKeyStore()),
      ],
    );
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).secureKeysFuture;
  });

  tearDown(() {
    container.dispose();
    paths.appDataDirOverride = null;
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  test('coordinator reset with production wiring removes retained WAVs, '
      'the recovery journal and import scratch', () async {
    final recordings = Directory(p.join(appData.path, 'recordings'));
    final journal = Directory(p.join(recordings.path, 'journal'));
    await journal.create(recursive: true);
    File(p.join(recordings.path, 'whispaste_1.wav')).writeAsStringSync('pcm');
    File(p.join(journal.path, 'entry.json')).writeAsStringSync('{}');
    final importWork = Directory(p.join(appData.path, 'imports', 'work'));
    await importWork.create(recursive: true);
    File(p.join(importWork.path, 'source.m4a')).writeAsStringSync('audio');

    final settings = container.read(settingsProvider.notifier);
    final coordinator = FactoryResetCoordinator(
      subprocess: _StoppedSubprocess(),
      modelDirPath: paths.sttDir(),
      logsDirPath: p.join(appData.path, 'logs'),
      eraseDatabase: () => db.deleteAllData(),
      eraseSecureStore: settings.eraseSecureStore,
      resetSettings: settings.factoryResetFinalize,
    );

    await coordinator.run().drain<void>();

    expect(recordings.existsSync(), isFalse);
    expect(Directory(p.join(appData.path, 'imports')).existsSync(), isFalse);
  });

  test('the reset also empties the review prompt counters (XP-6-12)', () async {
    SharedPreferences.setMockInitialValues({
      'review_prompt_unpasted_dictations': 3,
      'bundle_id_migration_done': true,
    });
    final settings = container.read(settingsProvider.notifier);
    final coordinator = FactoryResetCoordinator(
      subprocess: _StoppedSubprocess(),
      modelDirPath: paths.sttDir(),
      logsDirPath: p.join(appData.path, 'logs'),
      eraseDatabase: () => db.deleteAllData(),
      eraseSecureStore: settings.eraseSecureStore,
      resetSettings: settings.factoryResetFinalize,
    );

    await coordinator.run().drain<void>();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('review_prompt_unpasted_dictations'), isNull);
    expect(prefs.getBool('bundle_id_migration_done'), isTrue);
  });
}
