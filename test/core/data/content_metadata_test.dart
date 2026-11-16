import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/content_metadata.dart';

void main() {
  test(
    'identical source gives identical metadata; changed source changes hash',
    () {
      const source = '# Heading\r\nHello world #tag\n- [x] Done\n[[note-id]]';
      final first = parseContentMetadata(source);
      expect(parseContentMetadata(source).toJson(), first.toJson());
      expect(parseContentMetadata('$source!').hash, isNot(first.hash));
      expect(first.headings.single, (text: 'Heading', level: 1, offset: 0));
      expect(first.links.single, (
        target: 'note-id',
        offset: source.indexOf('[['),
      ));
      expect(first.tags, ['tag']);
      expect(first.checklists.single.offset, source.indexOf('[x]'));
      expect(first.checkedCount, 1);
      expect(first.characterCount, source.length);
      expect(first.wordCount, 9);
    },
  );

  test('headings, links, tags and tasks ignore code and escaped syntax', () {
    const source = '''# First ###
Title
-----
- [ ] Open
1. [X] Done
[site](https://example.org) [[note|Label]] #ä/子 #ä/子
`[[hidden]] #hidden` \\#escaped
~~~markdown
# Not a heading
- [x] Not a task
[[not-a-link]] #not-a-tag
~~~
## 😀 Last
''';
    final metadata = parseContentMetadata(source);
    expect(metadata.headings.map((h) => h.text), ['First', 'Title', '😀 Last']);
    expect(metadata.headings.map((h) => h.level), [1, 2, 2]);
    expect(metadata.headings.last.offset, source.indexOf('## 😀'));
    expect(metadata.links.map((l) => l.target), [
      'https://example.org',
      'note',
    ]);
    expect(metadata.tags, ['ä/子']);
    expect(metadata.checklists, hasLength(2));
    expect(metadata.checkedCount, 1);
  });

  test('empty content and Unicode whitespace retain counter semantics', () {
    expect(parseContentMetadata('').wordCount, 0);
    expect(parseContentMetadata('one\u00a0two\u3000three').wordCount, 3);
  });

  test('cache verifies integrity, parser version, source hash and bounds', () {
    final metadata = parseContentMetadata('# Hello');
    final payload = jsonEncode(metadata.toJson());
    expect(
      decodeContentMetadata(
        payload,
        contentHash(payload),
        metadata.hash,
      )?.toJson(),
      metadata.toJson(),
    );
    expect(
      decodeContentMetadata('$payload ', contentHash(payload), metadata.hash),
      isNull,
    );
    expect(
      decodeContentMetadata(payload, contentHash(payload), 'wrong'),
      isNull,
    );
    for (final broken in [
      {...metadata.toJson(), 'version': -1},
      {...metadata.toJson(), 'words': -1},
      {
        ...metadata.toJson(),
        'headings': [
          {'text': 'bad', 'level': 7, 'offset': 0},
        ],
      },
    ]) {
      final encoded = jsonEncode(broken);
      expect(
        decodeContentMetadata(encoded, contentHash(encoded), metadata.hash),
        isNull,
      );
    }
  });
}
