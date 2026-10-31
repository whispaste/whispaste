/// Schema v28 (WP-33a): app profiles and their matching rules. Runs the real
/// upgrade step from a v26 file database that already holds data, because
/// existing user databases take exactly that path.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/app_profile_consent.dart';
import 'package:whispaste/services/app_profiles/app_profile_storage.dart';

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wp33a_profiles_');
    dbFile = File('${tempDir.path}/history.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> openOnce(Future<void> Function(HistoryDatabase db) body) async {
    final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await body(db);
    await db.close();
  }

  /// Turns the file into a v26 database: no profile tables, version 26.
  Future<void> downgradeToV26() async {
    await openOnce((db) async {
      await db.customStatement('DROP TABLE IF EXISTS app_profile_rules');
      await db.customStatement('DROP TABLE IF EXISTS app_profiles');
      await db.customStatement('PRAGMA user_version = 26');
    });
  }

  test(
    'upgrading from v26 keeps existing data and adds the profile tables',
    () async {
      await openOnce((db) async {
        await db.upsertReplacementWithTriggers(
          id: 'mfg',
          triggers: ['mfg'],
          replacement: 'Mit freundlichen Grüßen',
          createdAt: DateTime(2026, 10, 1),
        );
      });
      await downgradeToV26();

      await openOnce((db) async {
        final replacements = await db.readAllReplacements();
        expect(replacements.single.row.replacement, 'Mit freundlichen Grüßen');
        expect(await db.readAppProfiles(), isEmpty);
        expect(await db.readAppProfileRules(), isEmpty);
      });
    },
  );

  test('upgrading from v27 adds the profile tables and keeps data', () async {
    await openOnce((db) async {
      await db.upsertReplacementWithTriggers(
        id: 'lg',
        triggers: ['lg'],
        replacement: 'Liebe Grüße',
        createdAt: DateTime(2026, 10, 1),
      );
    });
    // A v27 file: same as v26 but at version 27 (WP-32a's step, not in this
    // branch), without the profile tables.
    await openOnce((db) async {
      await db.customStatement('DROP TABLE IF EXISTS app_profile_rules');
      await db.customStatement('DROP TABLE IF EXISTS app_profiles');
      await db.customStatement('PRAGMA user_version = 27');
    });

    await openOnce((db) async {
      final replacements = await db.readAllReplacements();
      expect(replacements.single.row.replacement, 'Liebe Grüße');
      expect(await db.readAppProfiles(), isEmpty);
      await db.saveAppProfile(
        appProfileToCompanion(
          const AppProfile(id: 'a', name: 'A'),
          position: 0,
          createdAt: DateTime(2026, 10, 18),
          updatedAt: DateTime(2026, 10, 18),
        ),
        const [],
      );
      expect(await db.readAppProfiles(), hasLength(1));
    });
  });

  test(
    'the v28 step is idempotent when the profile tables already exist (DEV-259)',
    () async {
      const profile = AppProfile(
        id: 'keep',
        name: 'Keep',
        rules: [AppMatchRule(identifier: 'com.apple.mail')],
      );
      await openOnce((db) async {
        await db.saveAppProfile(
          appProfileToCompanion(
            profile,
            position: 0,
            createdAt: DateTime(2026, 10, 18),
            updatedAt: DateTime(2026, 10, 18),
          ),
          appProfileRulesToCompanions(profile),
        );
      });
      // Same file, but the version marker says v27 again: the v28 step runs
      // against tables that are already there and must change nothing.
      await openOnce((db) async {
        await db.customStatement('PRAGMA user_version = 27');
      });

      await openOnce((db) async {
        final profiles = await db.readAppProfiles();
        expect(profiles.map((row) => row.id), ['keep']);
        expect((await db.readAppProfileRules()).map((row) => row.identifier), [
          'com.apple.mail',
        ]);
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(version.data['user_version'], 31);
      });
    },
  );

  test('profiles and rules round-trip in their stored order', () async {
    final now = DateTime(2026, 10, 18);
    final consent = AppProfileConsent(
      providerId: 'openai',
      selectionCovered: false,
      clipboardCovered: true,
      textVersion: kAppProfileConsentTextVersion,
      givenAtUtc: DateTime.utc(2026, 10, 18, 9),
    );
    final profile = AppProfile(
      id: 'mail',
      name: 'Mail',
      rules: [
        const AppMatchRule(identifier: 'com.apple.mail', teamId: 'TEAM1'),
        const AppMatchRule(identifier: 'mail-alt'),
      ],
      smartMode: AppProfileSmartMode.concise,
      asrLanguage: 'de',
      contextSource: AppProfileContextSource.clipboard,
      consent: consent,
    );
    const second = AppProfile(id: 'notes', name: 'Notizen');

    await openOnce((db) async {
      for (final entry in [profile, second].indexed) {
        await db.saveAppProfile(
          appProfileToCompanion(
            entry.$2,
            position: entry.$1,
            createdAt: now,
            updatedAt: now,
          ),
          appProfileRulesToCompanions(entry.$2),
        );
      }
    });

    await openOnce((db) async {
      final loaded = appProfilesFromRows(
        await db.readAppProfiles(),
        await db.readAppProfileRules(),
      );
      expect(loaded, [profile, second]);
    });
  });

  test('saving again replaces the rules, and delete removes them', () async {
    final now = DateTime(2026, 10, 18);
    const first = AppProfile(
      id: 'p',
      name: 'P',
      rules: [
        AppMatchRule(identifier: 'a'),
        AppMatchRule(identifier: 'b'),
      ],
    );
    const edited = AppProfile(
      id: 'p',
      name: 'P',
      rules: [AppMatchRule(identifier: 'c')],
    );

    await openOnce((db) async {
      await db.saveAppProfile(
        appProfileToCompanion(
          first,
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
        appProfileRulesToCompanions(first),
      );
      await db.saveAppProfile(
        appProfileToCompanion(
          edited,
          position: 0,
          createdAt: now,
          updatedAt: now,
        ),
        appProfileRulesToCompanions(edited),
      );
      final rules = await db.readAppProfileRules();
      expect(rules.map((r) => r.identifier), ['c']);

      await db.deleteAppProfile('p');
      expect(await db.readAppProfiles(), isEmpty);
      expect(await db.readAppProfileRules(), isEmpty);
    });
  });

  test('unknown stored values read back as the safe fallbacks', () async {
    final now = DateTime(2026, 10, 18);
    await openOnce((db) async {
      await db.customStatement(
        'INSERT INTO app_profiles (id, name, position, smart_mode, context_source, '
        'created_at, updated_at) VALUES '
        "('x', 'X', 0, 'bogus', 'everything', ${now.millisecondsSinceEpoch}, "
        '${now.millisecondsSinceEpoch})',
      );
      final loaded = appProfilesFromRows(
        await db.readAppProfiles(),
        await db.readAppProfileRules(),
      );
      expect(loaded.single.smartMode, AppProfileSmartMode.standard);
      expect(loaded.single.contextSource, AppProfileContextSource.none);
    });
  });

  Future<Set<String>> columnsOf(HistoryDatabase db, String table) async {
    final rows = await db.customSelect("PRAGMA table_info('$table')").get();
    return {for (final row in rows) row.data['name'] as String};
  }

  const consentColumns = {
    'consent_provider',
    'consent_selection',
    'consent_clipboard',
    'consent_text_version',
    'consent_given_at',
  };

  test('v26 to v28 adds the consent and team id columns', () async {
    await downgradeToV26();
    await openOnce((db) async {
      expect(await columnsOf(db, 'app_profiles'), containsAll(consentColumns));
      expect(await columnsOf(db, 'app_profile_rules'), contains('team_id'));
    });
  });

  test(
    'a database written by e1b523d2 is repaired and keeps its profiles',
    () async {
      await openOnce((db) async {
        await db.customStatement('DROP TABLE IF EXISTS app_profile_rules');
        await db.customStatement('DROP TABLE IF EXISTS app_profiles');
        // The e1b523d2 shape: one consent flag, no consent_* columns.
        await db.customStatement(
          'CREATE TABLE app_profiles ('
          'id TEXT NOT NULL PRIMARY KEY, '
          'name TEXT NOT NULL, '
          'position INTEGER NOT NULL DEFAULT 0, '
          "smart_mode TEXT NOT NULL DEFAULT 'standard', "
          'asr_language TEXT, '
          'model_id TEXT, '
          "context_source TEXT NOT NULL DEFAULT 'none', "
          'context_consent_given INTEGER NOT NULL DEFAULT 0, '
          'created_at INTEGER NOT NULL, '
          'updated_at INTEGER NOT NULL)',
        );
        await db.customStatement(
          'INSERT INTO app_profiles (id, name, created_at, updated_at) '
          "VALUES ('old', 'Old', 0, 0)",
        );
        await db.customStatement('PRAGMA user_version = 28');
      });

      await openOnce((db) async {
        final columns = await columnsOf(db, 'app_profiles');
        expect(columns, containsAll(consentColumns));
        // Migrations are additive only (R7-3): the flag stays, unused.
        expect(columns, contains('context_consent_given'));
        expect(await columnsOf(db, 'app_profile_rules'), contains('team_id'));
        final profiles = await db.readAppProfiles();
        expect(profiles.map((row) => row.id), ['old']);
        expect(profiles.single.consentProvider, isNull);
        // The inert NOT NULL flag must not block writes through Drift, which
        // does not know the column and relies on its DEFAULT.
        await db.saveAppProfile(
          appProfileToCompanion(
            const AppProfile(id: 'new', name: 'New'),
            position: 1,
            createdAt: DateTime(2026, 10, 19),
            updatedAt: DateTime(2026, 10, 19),
          ),
          const [],
        );
        expect((await db.readAppProfiles()).map((row) => row.id), [
          'old',
          'new',
        ]);
      });
      // A second open repairs nothing more and keeps the data.
      await openOnce((db) async {
        expect((await db.readAppProfiles()).length, 2);
      });
    },
  );

  test(
    'the repair is idempotent on a database that already has the shape',
    () async {
      await openOnce((db) async {
        await db.customStatement('PRAGMA user_version = 27');
      });
      await openOnce((db) async {
        expect(
          await columnsOf(db, 'app_profiles'),
          containsAll(consentColumns),
        );
      });
    },
  );

  test(
    'a database from a newer app version is refused and left unchanged',
    () async {
      await openOnce((db) async {
        await db.saveAppProfile(
          appProfileToCompanion(
            const AppProfile(id: 'newer', name: 'Newer'),
            position: 0,
            createdAt: DateTime(2026, 10, 18),
            updatedAt: DateTime(2026, 10, 18),
          ),
          const [],
        );
        await db.customStatement('PRAGMA user_version = 99');
      });
      final bytesBefore = dbFile.readAsBytesSync();

      final db = HistoryDatabase.forTesting(NativeDatabase(dbFile));
      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(
          isA<DatabaseTooNewException>()
              .having((e) => e.storedVersion, 'storedVersion', 99)
              .having((e) => e.supportedVersion, 'supportedVersion', 31),
        ),
      );
      await db.close();
      expect(dbFile.readAsBytesSync(), bytesBefore);
    },
  );

  test('schemaVersion is the highest migration step in the code', () async {
    final source = File('lib/core/data/database.dart').readAsStringSync();
    final steps = RegExp(
      r'from\s*<\s*(\d+)',
    ).allMatches(source).map((m) => int.parse(m.group(1)!)).toList();
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(steps.reduce((a, b) => a > b ? a : b), db.schemaVersion);
  });

  test('the app-profile repair never drops a column (R7-3)', () {
    // Migrations are additive only. Older app versions and downgrades read
    // the same file, and a dropped column cannot be restored.
    final source = File('lib/core/data/database.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _ensureAppProfileSchema(');
    expect(start, isNonNegative);
    final end = source.indexOf('\n  }\n', start);
    expect(source.substring(start, end), isNot(contains('DROP COLUMN')));
  });

  test('HistoryDatabase carries the generated table set (DEV-299)', () async {
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // The generated mixin supplies the table getters; a misplaced annotation
    // would leave this empty.
    expect(
      db.allTables.map((t) => t.actualTableName),
      contains('app_profiles'),
    );
    expect(await db.readAppProfiles(), isEmpty);
  });

  test('the bundled SQLite supports DROP COLUMN on this host', () async {
    // sqlite3 3.x compiles SQLite itself on every desktop target (no system
    // library is opened), so the legacy-column drop is expected to run.
    final db = HistoryDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final row = await db
        .customSelect('SELECT sqlite_version() AS v')
        .getSingle();
    // DROP COLUMN needs SQLite 3.35.0 or newer.
    final parts = (row.data['v'] as String).split('.');
    final major = int.parse(parts[0]);
    final minor = int.parse(parts[1]);
    expect(
      major > 3 || (major == 3 && minor >= 35),
      isTrue,
      reason: 'bundled SQLite is ${row.data['v']}',
    );
  });
}
