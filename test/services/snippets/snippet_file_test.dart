// #665: single snippets, or sets of them, travel as a Markdown or JSON file.
// Covers the codec (round trip, validation, refusals), the import planner
// (strategies, repeats within a file) and the round trip through the library:
// export, import into another library, same snippets; the trash stays out.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/snippets/snippet_import_actions.dart';
import 'package:whispaste/features/snippets/snippets_page.dart';
import 'package:whispaste/services/snippets/snippet_file.dart';

// Fields as one string: a record compares a List member by identity, so two
// equal field lists would make equal entries look different.
typedef _Content = (String, String, String, String);

_Content _content(SnippetFileEntry e) =>
    (e.title, e.body, e.kind, e.fields.join('\u0000'));

const _tricky = [
  SnippetFileEntry(title: 'Plain', body: 'Hello'),
  SnippetFileEntry(
    title: 'Letter',
    body: 'Dear {{name}},\nsee {{date}}.',
    kind: snippetKindInteractive,
    fields: ['name', 'date'],
  ),
  SnippetFileEntry(title: '# Heading --> <b>', body: 'Code:\n````\nx\n````'),
  SnippetFileEntry(
    title: 'Umlaute äöü 字',
    body: '<!-- whispaste:snippet {} -->',
  ),
];

SnippetImportExisting _existing(String id, SnippetFileEntry entry) =>
    (id: id, entry: entry);

void main() {
  group('codec', () {
    for (final type in SnippetFileType.values) {
      test('round trip keeps every entry (${type.name})', () {
        final text = encodeSnippetFile(_tricky, type);
        final parsed = parseSnippetFile(text, type);
        expect(parsed.refusal, isNull);
        expect(parsed.errors, isEmpty);
        expect(parsed.entries.map(_content), _tricky.map(_content));
      });

      test('a BOM and CRLF line ends are read (${type.name})', () {
        final text = encodeSnippetFile(_tricky.take(2).toList(), type);
        final windows = '\uFEFF${text.replaceAll('\n', '\r\n')}';
        final parsed = parseSnippetFile(windows, type);
        expect(parsed.errors, isEmpty);
        expect(parsed.entries.map((e) => e.title), ['Plain', 'Letter']);
      });
    }

    test('the file type follows the extension, else the content', () {
      expect(snippetFileTypeFor('a.JSON', ''), SnippetFileType.json);
      expect(snippetFileTypeFor('a.markdown', '{'), SnippetFileType.markdown);
      expect(
        snippetFileTypeFor('drop', ' {"snippets":[]}'),
        SnippetFileType.json,
      );
      expect(snippetFileTypeFor('drop', '# x'), SnippetFileType.markdown);
    });

    test('bad entries are reported with position and skipped', () {
      final text = jsonEncode({
        'format': snippetFileFormat,
        'version': snippetFileVersion,
        'snippets': [
          {'title': 'Good', 'body': 'ok'},
          'not an object',
          {'title': '  ', 'body': 'x'},
          {'title': 'Empty', 'body': '  '},
          {'title': 'Odd', 'body': 'x', 'kind': 'macro'},
          {
            'title': 'Unused field',
            'body': 'Hi',
            'kind': snippetKindInteractive,
            'fields': ['name'],
          },
          {
            'title': 'Twice',
            'body': '{{a}}',
            'kind': snippetKindInteractive,
            'fields': ['a', 'a'],
          },
          {'title': 3, 'body': 'x'},
        ],
      });
      final parsed = parseSnippetsJson(text);
      expect(parsed.entries.map((e) => e.title), ['Good']);
      expect(
        [for (final e in parsed.errors) (e.position, e.reason)],
        [
          (2, SnippetFileErrorReason.malformed),
          (3, SnippetFileErrorReason.missingTitle),
          (4, SnippetFileErrorReason.emptyBody),
          (5, SnippetFileErrorReason.unknownKind),
          (6, SnippetFileErrorReason.invalidFields),
          (7, SnippetFileErrorReason.invalidFields),
          (8, SnippetFileErrorReason.malformed),
        ],
      );
      expect(parsed.errors[2].title, 'Empty');
    });

    test('a Markdown entry without closed fence is malformed', () {
      const text =
          '$snippetMarkdownFileMarker\n\n## A\n'
          '<!-- whispaste:snippet {"title":"A","kind":"static","fields":[]} -->\n'
          '```text\nopen';
      final parsed = parseSnippetsMarkdown(text);
      expect(parsed.entries, isEmpty);
      expect(parsed.errors.single.reason, SnippetFileErrorReason.malformed);
    });

    test('foreign files and other versions are refused whole', () {
      expect(
        parseSnippetsJson('not json').refusal,
        SnippetFileRefusal.unsupportedFormat,
      );
      expect(
        parseSnippetsJson('{"notes":[]}').refusal,
        SnippetFileRefusal.unsupportedFormat,
      );
      expect(
        parseSnippetsJson(
          jsonEncode({
            'format': snippetFileFormat,
            'version': 99,
            'snippets': [],
          }),
        ).refusal,
        SnippetFileRefusal.unsupportedVersion,
      );
      expect(
        parseSnippetsMarkdown('# Just notes\ntext').refusal,
        SnippetFileRefusal.unsupportedFormat,
      );
      expect(
        parseSnippetsMarkdown('<!-- whispaste:snippets format=2 -->').refusal,
        SnippetFileRefusal.unsupportedVersion,
      );
    });

    test(
      'any object with a snippet list is read, like the settings export',
      () {
        final parsed = parseSnippetsJson(
          jsonEncode({
            'settings': {'theme': 'dark'},
            'snippets': [
              {'title': 'From backup', 'body': 'text', 'isFavorite': true},
            ],
          }),
        );
        expect(parsed.refusal, isNull);
        expect(parsed.entries.single.title, 'From backup');
      },
    );

    test('entries beyond the limit are not read and marked truncated', () {
      final many = [
        for (var i = 0; i <= snippetFileMaxEntries; i++)
          SnippetFileEntry(title: 'T$i', body: 'b'),
      ];
      final parsed = parseSnippetsJson(encodeSnippetsJson(many));
      expect(parsed.truncated, isTrue);
      expect(parsed.entries, hasLength(snippetFileMaxEntries));
    });
  });

  group('planner', () {
    const mine = SnippetFileEntry(title: 'Greeting', body: 'Hi');
    final existing = [_existing('g1', mine)];

    test('new titles are added, equal content is a duplicate', () {
      final plan = planSnippetImport([
        const SnippetFileEntry(title: 'GREETING ', body: 'Hi'),
        const SnippetFileEntry(title: 'New', body: 'x'),
      ], existing);
      expect(plan.rows.map((r) => r.status), [
        SnippetImportStatus.duplicate,
        SnippetImportStatus.added,
      ]);
      expect(plan.writes.single.title, 'New');
      expect(plan.writes.single.id, isNull);
    });

    test('a title conflict follows the chosen strategy', () {
      const other = SnippetFileEntry(title: 'greeting', body: 'Hello there');
      final skip = planSnippetImport([other], existing);
      expect(skip.rows.single.status, SnippetImportStatus.conflictSkipped);
      expect(skip.writeCount, 0);

      final over = planSnippetImport(
        [other],
        existing,
        strategy: SnippetConflictStrategy.overwrite,
      );
      expect(over.rows.single.status, SnippetImportStatus.conflictReplaced);
      expect(over.writes.single.id, 'g1');
      expect(over.writes.single.title, 'Greeting');
      expect(over.writes.single.body, 'Hello there');

      final both = planSnippetImport(
        [other, other],
        [...existing, _existing('g2', mine.withTitle('greeting (2)'))],
        strategy: SnippetConflictStrategy.keepBoth,
      );
      expect(both.rows.map((r) => r.status), [
        SnippetImportStatus.conflictKept,
        SnippetImportStatus.duplicate,
      ]);
      expect(both.writes.map((w) => (w.id, w.title)), [(null, 'greeting (3)')]);
    });

    test('repeats within one file are unambiguous', () {
      const a = SnippetFileEntry(title: 'Twice', body: 'first');
      const b = SnippetFileEntry(title: 'twice', body: 'second');

      final skip = planSnippetImport([a, b], const []);
      expect(skip.rows.map((r) => r.status), [
        SnippetImportStatus.added,
        SnippetImportStatus.conflictSkipped,
      ]);

      final over = planSnippetImport(
        [a, b],
        const [],
        strategy: SnippetConflictStrategy.overwrite,
      );
      expect(over.rows.map((r) => r.status), [
        SnippetImportStatus.supersededInFile,
        SnippetImportStatus.added,
      ]);
      expect(over.writes.single.body, 'second');

      final both = planSnippetImport(
        [a, b],
        const [],
        strategy: SnippetConflictStrategy.keepBoth,
      );
      expect(both.writes.map((w) => w.title), ['Twice', 'twice (2)']);
    });
  });

  group('library round trip', () {
    late HistoryDatabase source;
    late HistoryDatabase target;

    setUp(() {
      source = HistoryDatabase.forTesting(NativeDatabase.memory());
      target = HistoryDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await source.close();
      await target.close();
    });

    ProviderContainer containerFor(HistoryDatabase db) {
      final c = ProviderContainer(
        overrides: [historyDatabaseProvider.overrideWith((ref) => db)],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<List<_Content>> library(ProviderContainer c) async {
      final items = await c.read(snippetsProvider.future);
      return [
        for (final s in items)
          (s.title, s.body, s.kind, s.fields.join('\u0000')),
      ]..sort((x, y) => x.$1.compareTo(y.$1));
    }

    for (final type in SnippetFileType.values) {
      test(
        'export then import gives the same snippets (${type.name})',
        () async {
          final from = containerFor(source);
          await from.read(snippetsProvider.future);
          final n = from.read(snippetsProvider.notifier);
          await n.add('Plain', 'Hello');
          await n.add(
            'Letter',
            'Dear {{name}}',
            kind: snippetKindInteractive,
            fields: const ['name'],
          );

          final exported = [
            for (final s in await from.read(snippetsProvider.future))
              SnippetFileEntry(
                title: s.title,
                body: s.body,
                kind: s.kind,
                fields: s.fields,
              ),
          ];
          final text = encodeSnippetFile(exported, type);

          final to = containerFor(target);
          final before = await to.read(snippetsProvider.future);
          final plan = planSnippetImport(
            parseSnippetFile(text, type).entries,
            snippetImportExisting(before),
          );
          await to.read(snippetsProvider.notifier).importSnippets(plan.writes);

          expect(await library(to), await library(from));

          // Importing the same file again changes nothing.
          final again = planSnippetImport(
            parseSnippetFile(text, type).entries,
            snippetImportExisting(await to.read(snippetsProvider.future)),
          );
          expect(again.writeCount, 0);
        },
      );
    }

    test('a snippet in the trash is no conflict and stays untouched', () async {
      final c = containerFor(source);
      await c.read(snippetsProvider.future);
      final n = c.read(snippetsProvider.notifier);
      final id = await n.add('Old', 'trashed body');
      await n.moveToTrash([id]);

      final plan = planSnippetImport(
        const [SnippetFileEntry(title: 'Old', body: 'new body')],
        snippetImportExisting(await c.read(snippetsProvider.future)),
        strategy: SnippetConflictStrategy.overwrite,
      );
      expect(plan.rows.single.status, SnippetImportStatus.added);
      await n.importSnippets(plan.writes);

      final trash = await c.read(snippetsTrashProvider.future);
      expect(trash.single.id, id);
      expect(trash.single.body, 'trashed body');
      expect((await library(c)).where((s) => s.$1 == 'Old').map((s) => s.$2), [
        'new body',
      ]);
    });
  });
}
