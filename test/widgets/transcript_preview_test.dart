// UIA-SHL-13: the done-toast preview must not split a surrogate pair when it
// truncates a transcript that contains emoji or other non-BMP characters.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  test('short transcripts are returned unchanged', () {
    expect(transcriptPreview('hello'), 'hello');
  });

  test('a transcript of exactly 80 characters is not truncated', () {
    final text = 'a' * 80;
    expect(transcriptPreview(text), text);
  });

  test('truncation keeps 80 code points and adds an ellipsis', () {
    final text = '${'a' * 79}🎤tail';
    expect(transcriptPreview(text), '${'a' * 79}🎤…');
  });

  test('truncation never leaves a lone surrogate behind', () {
    final text = '${'a' * 79}🎤🎤';
    final preview = transcriptPreview(text);
    expect(preview.runes.length, 81);
    expect(() => String.fromCharCodes(preview.runes), returnsNormally);
    expect(
      preview.codeUnits.where((c) => c >= 0xD800 && c <= 0xDFFF).length,
      2,
    );
  });
}
