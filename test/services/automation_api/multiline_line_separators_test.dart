/// WP-43a A-N5: every Unicode line separator counts as a line break for the
/// multiline preview gate, not only LF and CR.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/multiline_paste_confirmation.dart';

void main() {
  const separators = {
    'VT': '\v',
    'FF': '\f',
    'NEL': '\u0085',
    'LINE SEPARATOR': ' ',
    'PARAGRAPH SEPARATOR': ' ',
  };

  for (final entry in separators.entries) {
    test('${entry.key} needs the preview', () {
      expect(needsMultilinePreview('first${entry.value}second'), isTrue);
    });
  }

  test('a single line without separators does not', () {
    expect(needsMultilinePreview('just one line'), isFalse);
  });
}
