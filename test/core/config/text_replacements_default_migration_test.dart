/// Text replacements default of 2026-10-30: on for a fresh install; an
/// existing install without a stored choice keeps them off (one-time pin, see
/// `_migrateTextReplacementsDefault`).
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

ProviderContainer _container(HistoryDatabase db) => ProviderContainer(
  overrides: [
    historyDatabaseProvider.overrideWithValue(db),
    secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
    systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
  ],
);

/// Loads the settings from the stored rows and returns the container.
Future<ProviderContainer> _load(HistoryDatabase db) async {
  final c = _container(db);
  await c.read(settingsProvider.future);
  await c.read(settingsProvider.notifier).secureKeysFuture;
  return c;
}

void main() {
  test('a fresh install starts with text replacements on', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final c = await _load(db);
    addTearDown(c.dispose);

    expect(
      c.read(settingsProvider).value!.behavior.textReplacementsEnabled,
      isTrue,
    );
    final rows = await db.readAppSettings();
    expect(rows[kTextReplacementsDefaultMigrationKey], '1');
  });

  test('an existing install without the key keeps replacements off, '
      'written once with the marker', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeAppSettings({'onboarding_completed': 'true', 'locale': 'en'});
    final c = await _load(db);
    addTearDown(c.dispose);

    expect(
      c.read(settingsProvider).value!.behavior.textReplacementsEnabled,
      isFalse,
    );
    final rows = await db.readAppSettings();
    expect(rows['text_replacements_enabled'], 'false');
    expect(rows[kTextReplacementsDefaultMigrationKey], '1');
  });

  test('a stored choice is kept, and a later start never pins again', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeAppSettings({
      'onboarding_completed': 'true',
      'locale': 'en',
      'text_replacements_enabled': 'true',
    });
    final first = await _load(db);
    expect(
      first.read(settingsProvider).value!.behavior.textReplacementsEnabled,
      isTrue,
    );
    first.dispose();

    final rows = await db.readAppSettings();
    expect(rows['text_replacements_enabled'], 'true');
    expect(rows[kTextReplacementsDefaultMigrationKey], '1');

    // The user switches replacements off; a later start keeps that choice.
    await db.writeAppSettings({'text_replacements_enabled': 'false'});
    final second = await _load(db);
    addTearDown(second.dispose);
    expect(
      second.read(settingsProvider).value!.behavior.textReplacementsEnabled,
      isFalse,
    );
  });
}
