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

  test('scan finds new identifiers but writes nothing until commit', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    await fs
        .file('/project/user_service.dart')
        .writeAsString('class RecordingOrchestrator {}\n');

    final service = serviceFor(fs);
    final scanResult = await service.scan('/project', db);

    expect(scanResult.candidates, ['RecordingOrchestrator']);
    expect(scanResult.skipped, 0);
    expect(await db.readAllReplacements(), isEmpty);

    final added = await service.commit(scanResult.candidates, db);

    expect(added, 1);
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

  test('commit writes only the terms the caller selected, not every '
      'scanned candidate', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    await fs
        .file('/project/service.dart')
        .writeAsString('class KeepThisClass {}\nclass SkipThisClass {}\n');

    final service = serviceFor(fs);
    final scanResult = await service.scan('/project', db);
    expect(scanResult.candidates, ['KeepThisClass', 'SkipThisClass']);

    await service.commit(['KeepThisClass'], db);

    final rows = await db.readAllReplacements();
    expect(rows, hasLength(1));
    expect(rows.single.triggers, ['KeepThisClass']);
  });

  test(
    'ignores files whose extension is not a recognized source type',
    () async {
      final fs = MemoryFileSystem();
      await fs.directory('/project').create(recursive: true);
      await fs
          .file('/project/notes.txt')
          .writeAsString('class NotActuallyScanned {}\n');

      final scanResult = await serviceFor(fs).scan('/project', db);

      expect(scanResult.candidates, isEmpty);
    },
  );

  test('recurses into subdirectories', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project/lib/nested').create(recursive: true);
    await fs
        .file('/project/lib/nested/deep.dart')
        .writeAsString('class DeeplyNestedClass {}\n');

    final scanResult = await serviceFor(fs).scan('/project', db);

    expect(scanResult.candidates, ['DeeplyNestedClass']);
  });

  test('skips files above the max size guard', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    final huge = 'a' * (vocabularyImportMaxFileSizeBytes + 1);
    await fs
        .file('/project/huge.dart')
        .writeAsString('class HugeFileClass {}\n$huge');

    final scanResult = await serviceFor(fs).scan('/project', db);

    expect(scanResult.candidates, isEmpty);
  });

  test('a candidate matching an existing trigger is excluded from the scan '
      'result, not offered for re-import', () async {
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

    final scanResult = await serviceFor(fs).scan('/project', db);

    expect(scanResult.candidates, isEmpty);
    expect(scanResult.skipped, 1);
    expect(await db.readAllReplacements(), hasLength(1));
  });

  test(
    'never descends into an ignored directory like .git or node_modules',
    (() async {
      final fs = MemoryFileSystem();
      await fs.directory('/project/.git/objects').create(recursive: true);
      await fs
          .file('/project/.git/objects/garbage.dart')
          .writeAsString('class ShouldNeverBeSeen {}\n');
      await fs.directory('/project/node_modules/pkg').create(recursive: true);
      await fs
          .file('/project/node_modules/pkg/index.js')
          .writeAsString('function ShouldAlsoNeverBeSeen() {}\n');
      await fs
          .file('/project/real.dart')
          .writeAsString('class RealSourceClass {}\n');

      final scanResult = await serviceFor(fs).scan('/project', db);

      expect(scanResult.candidates, ['RealSourceClass']);
    }),
  );

  test('an identifier shorter than the import minimum length is never '
      'offered, even if extraction found it', () async {
    final fs = MemoryFileSystem();
    await fs.directory('/project').create(recursive: true);
    // "abc" is a plausible-looking snake_case-free single token; too
    // short to safely become a fuzzy trigger (see
    // vocabularyImportMinIdentifierLength doc comment).
    await fs
        .file('/project/short.dart')
        .writeAsString('const abcde = 1;\nclass RealLongClassName {}\n');

    final scanResult = await serviceFor(fs).scan('/project', db);

    expect(scanResult.candidates, contains('RealLongClassName'));
    expect(scanResult.candidates, isNot(contains('abcde')));
  });

  test(
    'returns an empty scan result for a folder that does not exist',
    () async {
      final fs = MemoryFileSystem();

      final scanResult = await serviceFor(fs).scan('/does/not/exist', db);

      expect(scanResult.candidates, isEmpty);
      expect(scanResult.skipped, 0);
    },
  );

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
