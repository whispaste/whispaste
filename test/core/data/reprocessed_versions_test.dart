/// Results of reprocessing an entry with another mode (#680): each is a
/// version of its own with its instruction, the raw transcript stays, and
/// undo steps back one result at a time.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/entry_version_rules.dart';
import 'package:whispaste/services/smart_mode/smart_mode_presets.dart';

void main() {
  late HistoryDatabase db;
  final t0 = DateTime(2026, 11, 11, 10);

  setUp(() async {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'e1',
        timestamp: t0,
        content: const Value('raw text'),
      ),
    );
  });

  tearDown(() => db.close());

  Future<String?> edited() async =>
      (await db.getEntry('e1'))!.smartModeEditedContent;

  Future<void> record(String result, String instruction, int minute) async {
    expect(
      await db.recordReprocessResult(
        'e1',
        result: result,
        instruction: instruction,
        now: t0.add(Duration(minutes: minute)),
      ),
      isTrue,
    );
  }

  test('results stack up and undo steps back to the raw text', () async {
    await record('clean', 'cleanup', 1);
    await record('short', 'concise', 2);

    expect(await edited(), 'short');
    expect((await db.getEntry('e1'))!.content, 'raw text');
    expect(
      [for (final v in await db.reprocessedVersionsFor('e1')) v.instruction],
      ['concise', 'cleanup'],
    );

    expect(await db.undoReprocessResult('e1'), isTrue);
    expect(await edited(), 'clean');
    expect(await db.undoReprocessResult('e1'), isTrue);
    expect(await edited(), isNull);
    expect(await db.undoReprocessResult('e1'), isFalse);
    expect((await db.getEntry('e1'))!.content, 'raw text');
  });

  test('an edited version from before v44 comes back on undo', () async {
    await db.updateEntry(
      'e1',
      const HistoryEntriesCompanion(smartModeEditedContent: Value('legacy')),
    );
    expect(await db.undoReprocessResult('e1'), isFalse);

    await record('new', 'cleanup', 1);
    expect(await db.undoReprocessResult('e1'), isTrue);

    expect(await edited(), 'legacy');
    final rows = await db.reprocessedVersionsFor('e1');
    expect(rows.single.instruction, isNull);
  });

  test('keeps at most the cap, newest first', () async {
    for (var i = 0; i < HistoryDatabase.maxReprocessedVersions + 3; i++) {
      await record('r$i', 'cleanup', i);
    }
    final rows = await db.reprocessedVersionsFor('e1');
    expect(rows, hasLength(HistoryDatabase.maxReprocessedVersions));
    expect(
      rows.first.content,
      'r${HistoryDatabase.maxReprocessedVersions + 2}',
    );
  });

  test('refuses a trashed entry and a too long result', () async {
    final tooLong = 'x' * (EntryVersionLimits.standard.maxChars + 1);
    expect(
      await db.recordReprocessResult('e1', result: tooLong, instruction: null),
      isFalse,
    );
    await db.softDeleteEntry('e1');
    expect(
      await db.recordReprocessResult('e1', result: 'r', instruction: null),
      isFalse,
    );
    expect(await db.reprocessedVersionsFor('e1'), isEmpty);
  });

  test('deleting the entry deletes its results', () async {
    await record('clean', 'cleanup', 1);
    await db.permanentDeleteEntry('e1');
    expect(await db.reprocessedVersionsFor('e1'), isEmpty);
  });

  for (final from in [42, 43]) {
    test('v$from upgrades with previews and reprocessing intact', () async {
      final dir = await Directory.systemTemp.createTemp('reprocess_migration_');
      final file = File('${dir.path}/history.db');
      final seed = HistoryDatabase.forTesting(NativeDatabase(file));
      await seed.insertHistoryEntry(
        HistoryEntriesCompanion.insert(
          id: 'old',
          timestamp: t0,
          content: const Value('original transcript'),
          smartModeEditedContent: const Value('legacy edit'),
        ),
      );
      await seed.customStatement('DROP TABLE reprocessed_versions');
      if (from < 43) {
        await seed.customStatement(
          'ALTER TABLE history_entries DROP COLUMN preview',
        );
      }
      await seed.customStatement('PRAGMA user_version = $from');
      await seed.close();

      final upgraded = HistoryDatabase.forTesting(NativeDatabase(file));
      addTearDown(() async {
        await upgraded.close();
        await dir.delete(recursive: true);
      });
      expect((await upgraded.getEntry('old'))!.preview, 'original transcript');
      expect(await upgraded.reprocessedVersionsFor('old'), isEmpty);
      expect(
        await upgraded.recordReprocessResult(
          'old',
          result: 'new result',
          instruction: 'cleanup',
        ),
        isTrue,
      );
      expect(await upgraded.undoReprocessResult('old'), isTrue);
      final restored = (await upgraded.getEntry('old'))!;
      expect(restored.content, 'original transcript');
      expect(restored.smartModeEditedContent, 'legacy edit');
      expect(restored.preview, 'original transcript');
    });
  }

  test('the stored instruction names the mode and target language', () {
    for (final preset in [SmartModePreset.cleanup, SmartModePreset.concise]) {
      final parsed = parseReprocessInstruction(reprocessInstruction(preset));
      expect(parsed?.preset, preset);
      expect(parsed?.targetLanguage, isNull);
    }
    final translate = parseReprocessInstruction(
      reprocessInstruction(
        SmartModePreset.translate,
        targetLanguage: SmartModeTargetLanguage.french,
      ),
    );
    expect(translate?.preset, SmartModePreset.translate);
    expect(translate?.targetLanguage, SmartModeTargetLanguage.french);
    expect(parseReprocessInstruction(null), isNull);
    expect(parseReprocessInstruction('off'), isNull);
    expect(parseReprocessInstruction('translate'), isNull);
    expect(parseReprocessInstruction('unknown'), isNull);
  });
}
