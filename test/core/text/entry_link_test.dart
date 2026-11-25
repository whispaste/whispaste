import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/content_metadata.dart';
import 'package:whispaste/core/text/entry_link.dart';
import 'package:whispaste/core/text/markdown_plain_text.dart';

void main() {
  const note = (kind: EntryLinkKind.note, id: 'n-1');
  const recording = (kind: EntryLinkKind.recording, id: 'r-1');

  group('format and parse (#660)', () {
    test('stores the id before the label', () {
      expect(formatEntryLink(note, 'Meeting'), '[[note:n-1|Meeting]]');
      expect(parseEntryLinkTarget('note:n-1'), note);
      expect(parseEntryLinkTarget('recording:r-1'), recording);
    });

    test('labels lose what would end the link early', () {
      expect(formatEntryLink(note, 'A]] | b\n[c'), '[[note:n-1|A b c]]');
      expect(formatEntryLink(note, '  '), '[[note:n-1]]');
    });

    test('plain wiki words and unknown kinds are no entry links', () {
      expect(parseEntryLinkTarget('Meeting'), isNull);
      expect(parseEntryLinkTarget('folder:x'), isNull);
      expect(parseEntryLinkTarget('note:'), isNull);
      expect(findEntryLinks('[[Meeting]] [[folder:x|y]]'), isEmpty);
    });

    test('finds every link with its range and label', () {
      const text = 'See [[note:n-1|Old name]] and [[recording:r-1]].';
      final links = findEntryLinks(text);
      expect(links.map((l) => l.ref), [note, recording]);
      expect(links.first.label, 'Old name');
      expect(links.last.label, isNull);
      expect(
        text.substring(links.first.start, links.first.end),
        '[[note:n-1|Old name]]',
      );
      expect(entryLinkAt(text, links.first.start + 3)?.ref, note);
      expect(entryLinkAt(text, 2), isNull);
    });

    test('the content index records the link target, so backlinks follow '
        'the id and a rename changes nothing', () {
      final metadata = parseContentMetadata(
        'x ${formatEntryLink(note, 'First name')}',
      );
      expect(metadata.links.single.target, 'note:n-1');
      final renamed = parseContentMetadata(
        'x ${formatEntryLink(note, 'Second name')}',
      );
      expect(renamed.links.single.target, entryLinkTarget(note));
    });

    test('a recording edited by Smart Mode is the recording', () {
      expect(
        entryRefOf((kind: ContentKind.recordingEdited, id: 'r-1')),
        recording,
      );
    });
  });

  group('typed trigger', () {
    test('the second typed bracket opens the chooser', () {
      expect(typedLinkTrigger('ab [', 'ab [[', 5), 3);
      expect(typedLinkTrigger('[', '[[', 2), 0);
      expect(typedLinkTrigger('a [ b', 'a [[ b', 4), 2);
    });

    test('paste, a third bracket or a single one do not', () {
      expect(typedLinkTrigger('ab', 'ab [[', 5), isNull);
      expect(typedLinkTrigger('[[', '[[[', 3), isNull);
      expect(typedLinkTrigger('a[', 'a[[[', 2), isNull);
      expect(typedLinkTrigger('a', 'a[', 2), isNull);
      expect(typedLinkTrigger('x [', 'y [[', 4), isNull);
    });
  });

  group('outside the app', () {
    test('plain text keeps only the label', () {
      expect(
        markdownToPlainText('See [[note:n-1|Meeting]] now'),
        'See Meeting now',
      );
      expect(markdownToPlainText('[[Meeting]]'), '[[Meeting]]');
      expect(markdownToPlainText('`[[note:n-1|x]]`'), '[[note:n-1|x]]');
    });
  });
}
