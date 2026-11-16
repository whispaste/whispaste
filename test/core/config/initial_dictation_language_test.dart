/// First start (Onboarding v6, 1a): the dictation language comes from the
/// system's preferred languages: the first one Whisper writes is stored once,
/// never automatic detection by default; a stored choice is never touched.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';

class _EmptySecureKeyStore extends SecureKeyStore {
  @override
  Future<String?> readKey(String key) async => null;

  @override
  Future<void> writeKey(String key, String value) async {}

  @override
  Future<void> deleteKey(String key) async {}

  @override
  Future<Map<String, String>> readAllApiKeys() async => {};
}

class _FailingWriteDatabase extends HistoryDatabase {
  _FailingWriteDatabase(super.e) : super.forTesting();

  @override
  Future<void> writeAppSettings(Map<String, String> values) =>
      throw Exception('simulated persist failure');
}

/// Loads the settings from [stored] on a system whose Flutter locales are
/// [systemLocales] and whose platform preferences are [systemPreferences],
/// and returns the loaded dictation language and every stored row.
Future<(String, Map<String, String>)> _loadRows(
  Map<String, String> stored,
  List<Locale> systemLocales, {
  List<String> systemPreferences = const [],
}) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  if (stored.isNotEmpty) await db.writeAppSettings(stored);
  final container = ProviderContainer(
    overrides: [
      historyDatabaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
      systemLocalesProvider.overrideWithValue(systemLocales),
      systemPreferredLanguagesProvider.overrideWith(
        (ref) async => systemPreferences,
      ),
    ],
  );
  addTearDown(container.dispose);
  final settings = await container.read(settingsProvider.future);
  await container.read(settingsProvider.notifier).secureKeysFuture;
  return (settings.sttLanguageCode, await db.readAppSettings());
}

/// The dictation language and the stored `stt_language` row.
Future<(String, String?)> _load(
  Map<String, String> stored,
  List<Locale> systemLocales, {
  List<String> systemPreferences = const [],
}) async {
  final (loaded, rows) = await _loadRows(
    stored,
    systemLocales,
    systemPreferences: systemPreferences,
  );
  return (loaded, rows['stt_language']);
}

void main() {
  group('first start sets the dictation language from the system', () {
    test('one system language is stored', () async {
      final (loaded, row) = await _load(const {}, const [Locale('ja', 'JP')]);
      expect(loaded, 'ja');
      expect(row, 'ja');
    });

    test('of several system languages the first is stored', () async {
      final (loaded, _) = await _load(const {}, const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ]);
      expect(loaded, 'de');
    });

    test(
      'the idle-migration marker is stored with the first-start languages',
      () async {
        final (_, rows) = await _loadRows(const {}, const [Locale('de', 'DE')]);
        expect(rows['stt_language'], 'de');
        expect(rows[kSttIdleDefaultMigrationKey], '1');
      },
    );

    test('a failed write still starts with the system language and stores '
        'nothing, so the next start retries', () async {
      final db = _FailingWriteDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) => db),
          secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
          systemLocalesProvider.overrideWithValue(const [Locale('de', 'DE')]),
        ],
      );
      addTearDown(container.dispose);
      final settings = await container.read(settingsProvider.future);
      await container.read(settingsProvider.notifier).secureKeysFuture;
      expect(settings.sttLanguageCode, 'de');
      expect(await db.readAppSettings(), isEmpty);
    });

    test('an existing install keeps its stored choice', () async {
      final (loaded, row) = await _load(
        const {'locale': 'en', 'stt_language': 'auto'},
        const [Locale('ja', 'JP')],
      );
      expect(loaded, 'auto');
      expect(row, 'auto');
    });

    test('an existing install without a dictation row stays on '
        'automatic detection', () async {
      final (loaded, _) = await _load(
        const {'locale': 'de'},
        const [Locale('ja', 'JP')],
      );
      expect(loaded, 'auto');
    });
    test(
      'platform preferences take over when the Flutter locale is C',
      () async {
        final (loaded, row) = await _load(
          const {},
          const [Locale('C')],
          systemPreferences: const ['de-DE', 'en-US'],
        );
        expect(loaded, 'de');
        expect(row, 'de');
      },
    );

    test('no system language at all stores English, never automatic', () async {
      final (loaded, row) = await _load(const {}, const []);
      expect(loaded, 'en');
      expect(row, 'en');
    });

    test(
      'an install with settings but no locale row is not switched',
      () async {
        final (loaded, row) = await _load(
          const {'onboarding_completed': 'true'},
          const [Locale('ja', 'JP')],
        );
        expect(loaded, 'auto');
        expect(row, isNull);
      },
    );
  });
}
