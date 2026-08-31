import 'package:drift/native.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/services/replacements/vocabulary_import_scanner.dart';
import 'package:whispaste/services/replacements/vocabulary_import_service.dart';

void main() {
  late HistoryDatabase db;

  setUp(() {
    db = HistoryDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  VocabularyImportService serviceFor(MemoryFileSystem fs) {
    return VocabularyImportService(
      fileSystem: fs,
      // Run extraction inline instead of via a real isolate -- keeps the
      // unit test fast and deterministic.
      extract: (files) async => extractIdentifiers(files),
    );
  }

  test('scans matching source files and inserts new identifiers as fuzzy '
      'replacements with origin "imported"', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    await fs
        .file('/project/user_service.dart')
        .writeAsString('class RecordingOrchestrator {}\n');

    final summary = await serviceFor(fs).importFrom('/project', db);

    expect(summary.found, 1);
    expect(summary.added, 1);
    expect(summary.skipped, 0);

    final rows = await db.readAllReplacements();
    expect(rows, hasLength(1));
    expect(rows.single.triggers, ['RecordingOrchestrator']);
    expect(rows.single.row.replacement, 'RecordingOrchestrator');
    expect(rows.single.row.matchMode, 'fuzzy');
    expect(
      rows.single.row.fuzzyThreshold,
      vocabularyImportDefaultFuzzyThreshold,
    );
    expect(rows.single.row.origin, 'imported');
  });

  test(
    'ignores files whose extension is not a recognized source type',
    () async {
      final fs = MemoryFileSystem();
      await fs.directory('/project').create(recursive: true);
      await fs
          .file('/project/notes.txt')
          .writeAsString('class NotActuallyScanned {}\n');

      final summary = await serviceFor(fs).importFrom('/project', db);

      expect(summary.found, 0);
      expect(summary.added, 0);
      expect(await db.readAllReplacements(), isEmpty);
    },
  );

  test('recurses into subdirectories', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project/lib/nested').create(recursive: true);
    await fs
        .file('/project/lib/nested/deep.dart')
        .writeAsString('class DeeplyNestedClass {}\n');

    final summary = await serviceFor(fs).importFrom('/project', db);

    expect(summary.added, 1);
    final rows = await db.readAllReplacements();
    expect(rows.single.triggers, ['DeeplyNestedClass']);
  });

  test('skips files above the max size guard', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    final huge = 'a' * (vocabularyImportMaxFileSizeBytes + 1);
    await fs
        .file('/project/huge.dart')
        .writeAsString('class HugeFileClass {}\n$huge');

    final summary = await serviceFor(fs).importFrom('/project', db);

    expect(summary.found, 0);
    expect(summary.added, 0);
  });

  test('a candidate matching an existing trigger is skipped, not '
      'duplicated', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    await fs
        .file('/project/service.dart')
        .writeAsString('class ExistingTrigger {}\n');

    await db.upsertReplacementWithTriggers(
      id: 'manual_1',
      triggers: ['ExistingTrigger'],
      replacement: 'ExistingTrigger',
      createdAt: DateTime.now(),
    );

    final summary = await serviceFor(fs).importFrom('/project', db);

    expect(summary.found, 1);
    expect(summary.added, 0);
    expect(summary.skipped, 1);
    expect(await db.readAllReplacements(), hasLength(1));
  });

  test('returns an empty summary for a folder that does not exist', () async {
    final fs = MemoryFileSystem();

    final summary = await serviceFor(fs).importFrom('/does/not/exist', db);

    expect(summary.found, 0);
    expect(summary.added, 0);
    expect(summary.skipped, 0);
  });

  test('pickFolder delegates to the injected picker function', () async {
    final fs = MemoryFileSystem();
    var calledWith = '';
    final service = VocabularyImportService(
      fileSystem: fs,
      pickFolder: ({initialDirectory}) async {
        calledWith = initialDirectory ?? '';
        return '/chosen/path';
      },
    );

    final result = await service.pickFolder(initialDirectory: '/start');

    expect(result, '/chosen/path');
    expect(calledWith, '/start');
  });
}
