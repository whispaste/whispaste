/// Manual identifier input for the auto-paste block list: a pasted list with
/// line breaks becomes one entry per line (trimmed, no blanks).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/auto_paste_blocklist.dart';

void main() {
  group('autoPasteIdentifiersFromInput', () {
    test('a single identifier stays one entry', () {
      expect(autoPasteIdentifiersFromInput('notepad.exe'), ['notepad.exe']);
    });

    test('line breaks separate entries, blanks and surrounding spaces go', () {
      expect(
        autoPasteIdentifiersFromInput('  note \r\n\n pad.exe\n\n  Safari  \n'),
        ['note', 'pad.exe', 'Safari'],
      );
    });

    test('commas separate entries as well', () {
      expect(autoPasteIdentifiersFromInput('a,b\nc,,'), ['a', 'b', 'c']);
    });

    test('blank input yields no entries', () {
      expect(autoPasteIdentifiersFromInput(' \n \t\n'), isEmpty);
    });
  });

  group('autoPasteBlocklistWithAll', () {
    test('adds every identifier in order', () {
      expect(
        autoPasteBlocklistWithAll('', ['note', 'pad.exe']),
        'note, pad.exe',
      );
    });

    test('skips identifiers that are already listed by key', () {
      expect(
        autoPasteBlocklistWithAll('Notepad.exe', ['notepad', 'pad.exe']),
        'Notepad.exe, pad.exe',
      );
    });
  });
}
