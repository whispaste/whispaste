/// The list preview of a note: computed once on every save and stored in its
/// own column, so lists never have to read the full text (#639).
library;

/// How many characters of the beginning a stored preview keeps. The notes
/// list shows a title of up to 240 characters and two preview lines, so this
/// covers everything a list row can display.
const int kNotePreviewLength = 500;

/// The beginning of [content] without leading blank space, at most
/// [kNotePreviewLength] characters, cut at a word end when the text is longer.
String notePreview(String content) {
  final start = content.indexOf(RegExp(r'\S'));
  if (start < 0) return '';
  final text = start == 0 ? content : content.substring(start);
  if (text.length <= kNotePreviewLength) return text;
  var cut = kNotePreviewLength;
  // Prefer the last whitespace in the final fifth of the window.
  final lastSpace = text.lastIndexOf(RegExp(r'\s'), cut);
  if (lastSpace > kNotePreviewLength * 4 ~/ 5) {
    cut = lastSpace;
  } else if (_isHighSurrogate(text.codeUnitAt(cut - 1))) {
    cut -= 1;
  }
  return text.substring(0, cut).trimRight();
}

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;
