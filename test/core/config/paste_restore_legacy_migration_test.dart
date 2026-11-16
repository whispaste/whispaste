/// One-time default for the legacy clipboard restore (W-E1): an install that
/// finished onboarding before this version keeps the previous release's
/// restore after a receipt timeout; a fresh install gets receipt-only.
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

/// Loads the settings from [stored] and returns the container and database.
Future<(ProviderContainer, HistoryDatabase)> _load(
  Map<String, String> stored,
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
      systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
    ],
  );
  await container.read(settingsProvider.future);
  await container.read(settingsProvider.notifier).secureKeysFuture;
  return (container, db);
}

/// Fails only the one-time migration write, like a locked or full database.
class _FailingMarkerDatabase extends HistoryDatabase {
  _FailingMarkerDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> writeAppSettings(Map<String, String> values) async {
    if (values.containsKey(kPasteRestoreLegacyMigrationKey)) {
      throw StateError('database locked');
    }
    await super.writeAppSettings(values);
  }
}

void main() {
  test('an install that finished onboarding keeps the restore after a timeout '
      'and gets the marker', () async {
    final (c, db) = await _load({
      'onboarding_completed': 'true',
      'locale': 'en',
    });
    addTearDown(c.dispose);

    expect(
      c.read(settingsProvider).value!.behavior.restoreClipboardWithoutReceipt,
      isTrue,
    );
    final rows = await db.readAppSettings();
    expect(rows['restore_clipboard_without_receipt'], 'true');
    expect(rows.containsKey(kPasteRestoreLegacyMigrationKey), isTrue);
  });

  test('a fresh install stays receipt-only and stamps the marker', () async {
    final (c, db) = await _load(const {});
    addTearDown(c.dispose);

    expect(
      c.read(settingsProvider).value!.behavior.restoreClipboardWithoutReceipt,
      isFalse,
    );
    expect((await db.readAppSettings())[kPasteRestoreLegacyMigrationKey], '1');
  });

  test(
    'a fresh install that completes onboarding later is not migrated',
    () async {
      // The first load stamps the marker; a later completed onboarding must
      // not turn the install into a legacy one. One database serves both.
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ProviderContainer container() => ProviderContainer(
        overrides: [
          historyDatabaseProvider.overrideWithValue(db),
          secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
          systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
        ],
      );

      final first = container();
      addTearDown(first.dispose);
      await first.read(settingsProvider.future);
      await first.read(settingsProvider.notifier).secureKeysFuture;
      await db.writeAppSettings({'onboarding_completed': 'true'});

      final second = container();
      addTearDown(second.dispose);
      await second.read(settingsProvider.future);
      await second.read(settingsProvider.notifier).secureKeysFuture;

      expect(
        second
            .read(settingsProvider)
            .value!
            .behavior
            .restoreClipboardWithoutReceipt,
        isFalse,
      );
    },
  );

  test('a failed marker write keeps the migrated restore default in memory '
      '(the next start retries)', () async {
    final db = _FailingMarkerDatabase();
    addTearDown(db.close);
    await db.writeAppSettings({'onboarding_completed': 'true', 'locale': 'en'});
    final container = ProviderContainer(
      overrides: [
        historyDatabaseProvider.overrideWithValue(db),
        secureKeyStoreProvider.overrideWithValue(_EmptySecureKeyStore()),
        systemLocalesProvider.overrideWithValue(const [Locale('en', 'US')]),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).secureKeysFuture;

    expect(
      container
          .read(settingsProvider)
          .value!
          .behavior
          .restoreClipboardWithoutReceipt,
      isTrue,
    );
    expect(
      (await db.readAppSettings()).containsKey(kPasteRestoreLegacyMigrationKey),
      isFalse,
    );
  });
}
