/// Default for push-to-talk (V05, maintainer decision R-V05-1 = a): a fresh
/// install starts in hold mode, while an install that finished onboarding
/// before keeps toggle mode, because it never stored `push_to_talk`.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/secure_key_store.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/initial_locale.dart';
import 'package:whispaste/services/settings_portability_service.dart';

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

/// Loads the settings from [stored] (empty = fresh install) and returns the
/// container and database.
Future<(ProviderContainer, HistoryDatabase)> _load(
  Map<String, String> stored,
) async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  if (stored.isNotEmpty) await db.writeAppSettings(stored);
  final container = _container(db);
  await container.read(settingsProvider.future);
  await container.read(settingsProvider.notifier).secureKeysFuture;
  return (container, db);
}

/// Fails only the one-time marker write, like a locked or full database.
class _FailingMarkerDatabase extends HistoryDatabase {
  _FailingMarkerDatabase() : super.forTesting(NativeDatabase.memory());

  @override
  Future<void> writeAppSettings(Map<String, String> values) async {
    if (values.containsKey(kPushToTalkDefaultMigrationKey)) {
      throw StateError('database locked');
    }
    await super.writeAppSettings(values);
  }
}

bool _pushToTalk(ProviderContainer c) =>
    c.read(settingsProvider).value!.audioInput.pushToTalk;

void main() {
  test('the built-in default is hold mode', () {
    expect(AudioInputSettings.defaults.pushToTalk, isTrue);
  });

  test(
    'a fresh install starts in hold mode and stores it with the marker',
    () async {
      final (c, db) = await _load(const {});
      addTearDown(c.dispose);

      expect(_pushToTalk(c), isTrue);
      final rows = await db.readAppSettings();
      expect(rows['push_to_talk'], 'true');
      expect(rows[kPushToTalkDefaultMigrationKey], '1');
    },
  );

  test('an install that finished onboarding without a stored push_to_talk '
      'keeps toggle mode and gets the marker', () async {
    final (c, db) = await _load({
      'onboarding_completed': 'true',
      'locale': 'en',
    });
    addTearDown(c.dispose);

    expect(_pushToTalk(c), isFalse);
    final rows = await db.readAppSettings();
    expect(rows['push_to_talk'], 'false');
    expect(rows[kPushToTalkDefaultMigrationKey], '1');
  });

  test(
    'an install with a stored push_to_talk keeps its value (true)',
    () async {
      final (c, db) = await _load({
        'onboarding_completed': 'true',
        'locale': 'en',
        'push_to_talk': 'true',
      });
      addTearDown(c.dispose);

      expect(_pushToTalk(c), isTrue);
      expect((await db.readAppSettings())['push_to_talk'], 'true');
    },
  );

  test(
    'an install with a stored push_to_talk keeps its value (false)',
    () async {
      final (c, db) = await _load({
        'onboarding_completed': 'true',
        'locale': 'en',
        'push_to_talk': 'false',
      });
      addTearDown(c.dispose);

      expect(_pushToTalk(c), isFalse);
      expect((await db.readAppSettings())['push_to_talk'], 'false');
    },
  );

  test('a stored value an earlier start had not yet onboarded is kept', () async {
    // Not finished onboarding, but the user already stored a mode (for example
    // through an import): the stored value wins over the fresh-install default.
    final (c, _) = await _load({'push_to_talk': 'false', 'locale': 'en'});
    addTearDown(c.dispose);

    expect(_pushToTalk(c), isFalse);
  });

  test('the marker stops the migration from firing again', () async {
    // Existing install: migrated to toggle mode on the first start.
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.writeAppSettings({'onboarding_completed': 'true', 'locale': 'en'});

    final first = _container(db);
    addTearDown(first.dispose);
    await first.read(settingsProvider.future);
    await first.read(settingsProvider.notifier).secureKeysFuture;
    expect(_pushToTalk(first), isFalse);

    // The user switches to hold mode; the next start keeps that choice.
    await first
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            audioInput: s.audioInput.copyWith(pushToTalk: true),
          ),
        );

    final second = _container(db);
    addTearDown(second.dispose);
    await second.read(settingsProvider.future);
    await second.read(settingsProvider.notifier).secureKeysFuture;
    expect(_pushToTalk(second), isTrue);
  });

  test('a failed marker write keeps the migrated default in memory '
      '(the next start retries)', () async {
    final db = _FailingMarkerDatabase();
    addTearDown(db.close);
    await db.writeAppSettings({'onboarding_completed': 'true', 'locale': 'en'});
    final container = _container(db);
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    await container.read(settingsProvider.notifier).secureKeysFuture;

    expect(_pushToTalk(container), isFalse);
    expect(
      (await db.readAppSettings()).containsKey(kPushToTalkDefaultMigrationKey),
      isFalse,
    );
  });

  group('settings import', () {
    test('a profile without push_to_talk keeps the current mode (hold)', () {
      final current = AppSettings.defaults.copyWithSections(
        audioInput: AudioInputSettings.defaults.copyWith(pushToTalk: true),
      );
      final merged = mergeImportedSettings(current, {'input_gain': '1.5'});
      expect(merged.audioInput.pushToTalk, isTrue);
      expect(merged.audioInput.inputGain, 1.5);
    });

    test('a profile without push_to_talk keeps the current mode (toggle)', () {
      final current = AppSettings.defaults.copyWithSections(
        audioInput: AudioInputSettings.defaults.copyWith(pushToTalk: false),
      );
      final merged = mergeImportedSettings(current, {'input_gain': '1.5'});
      expect(merged.audioInput.pushToTalk, isFalse);
    });

    test('a profile with push_to_talk takes that value', () {
      final current = AppSettings.defaults;
      final merged = mergeImportedSettings(current, {'push_to_talk': 'false'});
      expect(merged.audioInput.pushToTalk, isFalse);
    });
  });

  group('holdModeInEffect', () {
    AppSettings settingsWith({bool? pushToTalk, String? doubleTapKey}) =>
        AppSettings.defaults.copyWithSections(
          audioInput: AudioInputSettings.defaults.copyWith(
            pushToTalk: pushToTalk ?? true,
          ),
          hotkey: AppSettings.defaults.hotkey.copyWith(
            hotkeyDoubleTapKey: doubleTapKey ?? '',
          ),
        );

    test('hold mode needs push-to-talk and key-up', () {
      expect(holdModeInEffect(settingsWith(), supportsKeyUp: true), isTrue);
      expect(holdModeInEffect(settingsWith(), supportsKeyUp: false), isFalse);
      expect(
        holdModeInEffect(settingsWith(pushToTalk: false), supportsKeyUp: true),
        isFalse,
      );
    });

    test('a double-tap trigger replaces the hold mode', () {
      expect(
        holdModeInEffect(
          settingsWith(doubleTapKey: 'rightCtrl'),
          supportsKeyUp: true,
        ),
        isFalse,
      );
    });
  });
}
