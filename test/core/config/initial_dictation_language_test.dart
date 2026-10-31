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

/// Loads the settings from [stored] on a system with [systemLocales] and
/// returns the loaded dictation language and the stored row.
Future<(String, String?)> _load(
  Map<String, String> stored,
  List<Locale> systemLocales,
) async {
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
    ],
  );
  addTearDown(container.dispose);
  final settings = await container.read(settingsProvider.future);
  await container.read(settingsProvider.notifier).secureKeysFuture;
  return (
    settings.sttLanguageCode,
    (await db.readAppSettings())['stt_language'],
  );
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
  });
}
