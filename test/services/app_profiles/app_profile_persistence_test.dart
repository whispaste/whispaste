/// Round trip of the profile fields that quick switching adds (hotkey,
/// after-transcription action, microphone): written through the real
/// database, read back through the storage converter.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_storage.dart';

void main() {
  test(
    'hotkey, after-transcription action and microphone survive a save',
    () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      const profile = AppProfile(
        id: 'schnell',
        name: 'Schnell',
        hotkeyKey: 'F5',
        hotkeyModifiers: 'ctrl+shift',
        afterTranscription: 'clipboard',
        microphone: 'USB Mic',
      );
      final now = DateTime.utc(2026, 10, 19);
      await db.saveAppProfile(
        appProfileToCompanion(
          profile,
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
        appProfileRulesToCompanions(profile),
      );

      final loaded = appProfilesFromRows(
        await db.readAppProfiles(),
        await db.readAppProfileRules(),
      ).single;

      expect(loaded, profile);
      expect(loaded.hasHotkey, isTrue);
    },
  );

  test('a profile without the new fields keeps them empty', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const profile = AppProfile(id: 'plain', name: 'Plain');
    final now = DateTime.utc(2026, 10, 19);
    await db.saveAppProfile(
      appProfileToCompanion(
        profile,
        position: 0,
        createdAt: now,
        updatedAt: now,
      ),
      appProfileRulesToCompanions(profile),
    );

    final loaded = appProfilesFromRows(
      await db.readAppProfiles(),
      await db.readAppProfileRules(),
    ).single;

    expect(loaded.hasHotkey, isFalse);
    expect(loaded.afterTranscription, isNull);
    expect(loaded.microphone, isNull);
  });
}
