/// Line diff for the note version panel (WP-31a).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/notes/data/note_line_diff.dart';

void main() {
  test('identical texts are all "same"', () {
    final diff = diffNoteLines('a\nb', 'a\nb');
    expect(diff, [
      const NoteDiffLine(NoteDiffKind.same, 'a'),
      const NoteDiffLine(NoteDiffKind.same, 'b'),
    ]);
  });

  test('marks an added line and a removed line', () {
    final diff = diffNoteLines('eins\nzwei\ndrei', 'eins\nzwei neu\ndrei');
    expect(diff, [
      const NoteDiffLine(NoteDiffKind.same, 'eins'),
      const NoteDiffLine(NoteDiffKind.removed, 'zwei'),
      const NoteDiffLine(NoteDiffKind.added, 'zwei neu'),
      const NoteDiffLine(NoteDiffKind.same, 'drei'),
    ]);
  });

  test('an empty old version shows every line as added', () {
    final diff = diffNoteLines('', 'a\nb');
    expect(diff, [
      const NoteDiffLine(NoteDiffKind.removed, ''),
      const NoteDiffLine(NoteDiffKind.added, 'a'),
      const NoteDiffLine(NoteDiffKind.added, 'b'),
    ]);
  });

  test('returns null beyond the line cap instead of running quadratically', () {
    final big = List.generate(2000, (i) => 'Zeile $i').join('\n');
    expect(diffNoteLines(big, '$big\nEnde'), isNull);
  });
}
