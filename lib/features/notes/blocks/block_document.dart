/// Block model for very long notes (ADR 0035, #641): the note's source text is
/// the only stored form; blocks are a lossless view of it. Born in the #642
/// editor spike, now used by the long-note editor of the notes page.
library;

/// Kind of a block. Only what the spike renders differently.
enum BlockKind { paragraph, heading, listItem, codeFence }

/// One block of the document.
///
/// [content] is the raw Markdown of the block without its final line
/// terminator. [separator] holds that terminator plus any following blank
/// lines, so `content + separator` of all blocks (after [BlockDocument.leading])
/// reproduces the source byte for byte.
class MarkdownBlock {
  MarkdownBlock({
    required this.kind,
    required this.content,
    required this.separator,
    this.headingLevel = 0,
  });

  final BlockKind kind;
  String content;
  String separator;

  /// 1 to 6 for ATX headings, 0 otherwise.
  final int headingLevel;
}

/// Lossless split of a Markdown string into blocks.
///
/// Rules (spike scope, not full CommonMark): fenced code (``` or ~~~) is one
/// block up to its closing fence; ATX headings and list items are blocks of
/// their own (a list item keeps its indented continuation lines); other
/// consecutive non-blank lines form a paragraph. Blank lines belong to the
/// separator of the block before them.
class BlockDocument {
  BlockDocument._(this.leading, this.blocks);

  factory BlockDocument.parse(String source) {
    final parsed = _parse(source);
    return BlockDocument._(parsed.leading, parsed.blocks);
  }

  /// Blank lines before the first block.
  String leading;
  final List<MarkdownBlock> blocks;

  /// Soft split threshold for display segments (characters).
  static const softSplitChars = 2000;

  String toMarkdown() {
    final out = StringBuffer(leading);
    for (final b in blocks) {
      out
        ..write(b.content)
        ..write(b.separator);
    }
    return out.toString();
  }

  /// Replaces the content of block [index] with [text] and re-parses that
  /// block, so typing `# ` or a blank line changes its structure. Returns the
  /// number of blocks that replaced it (1 unless the edit split it).
  int updateBlock(int index, String text) {
    final old = blocks[index];
    final reparsed = _parse(text + old.separator);
    var replacement = reparsed.blocks;
    if (replacement.isEmpty) {
      // The block became blank: keep an empty paragraph so the caret has a
      // place; its separator absorbs the blank lines.
      replacement = [
        MarkdownBlock(
          kind: BlockKind.paragraph,
          content: '',
          separator: reparsed.leading,
        ),
      ];
    } else if (reparsed.leading.isNotEmpty) {
      // Leading blank lines of the edited text move to the previous block
      // (or the document start), so the round trip stays exact.
      if (index == 0) {
        leading += reparsed.leading;
      } else {
        blocks[index - 1].separator += reparsed.leading;
      }
    }
    blocks.replaceRange(index, index + 1, replacement);
    return replacement.length;
  }

  /// Joins block [index] onto the previous block (Backspace at block start):
  /// the separator between them is dropped. Returns the caret offset in the
  /// merged block, or -1 when there is no previous block.
  int mergeWithPrevious(int index) {
    if (index <= 0) return -1;
    final prev = blocks[index - 1];
    final cur = blocks[index];
    final caret = prev.content.length;
    final joined = prev.content + cur.content;
    prev.separator = cur.separator;
    blocks.removeAt(index);
    updateBlock(index - 1, joined);
    return caret;
  }

  /// Display segment bounds of [content] as offsets `[0, ..., length]`.
  ///
  /// Content up to [softSplitChars] is one segment. Longer content is cut
  /// after a sentence end (`.`, `!`, `?`, `…` followed by whitespace) near the
  /// threshold; without one, at the last whitespace; without that, hard at the
  /// threshold. Display only: the Markdown is never changed.
  static List<int> segmentBounds(String content) {
    final bounds = <int>[0];
    var start = 0;
    while (content.length - start > softSplitChars) {
      final limit = start + softSplitChars;
      var cut = -1;
      var space = -1;
      for (var i = limit; i > start + softSplitChars ~/ 2; i--) {
        final c = content.codeUnitAt(i);
        if (_isSpace(c)) {
          if (space < 0) space = i + 1;
          if (i > 0 && _isSentenceEnd(content.codeUnitAt(i - 1))) {
            cut = i + 1;
            break;
          }
        }
      }
      if (cut < 0) cut = space > 0 ? space : limit;
      // A hard cut must not split a surrogate pair: half an emoji would be
      // rendered as two replacement glyphs at the segment seam.
      if (cut == limit && _isHighSurrogate(content.codeUnitAt(cut - 1))) {
        cut--;
      }
      bounds.add(cut);
      start = cut;
    }
    bounds.add(content.length);
    return bounds;
  }

  static bool _isHighSurrogate(int c) => c >= 0xD800 && c <= 0xDBFF;

  /// Plain-text rendering: the visible text without Markdown syntax.
  ///
  /// Heading markers, fence lines, backslash escapes, hard-break backslashes
  /// and emphasis/code markers are removed; list markers stay (they are
  /// visible content). Blank lines and line endings are kept as they are.
  /// For a note migrated with [escapePlainText] this returns the original
  /// text exactly (ADR 0035).
  String toPlainText() {
    final out = StringBuffer(leading);
    for (final b in blocks) {
      out
        ..write(switch (b.kind) {
          BlockKind.heading => _inline(
            b.content.replaceFirst(_headingStrip, ''),
          ),
          BlockKind.codeFence => _fenceBody(b.content),
          _ => _inline(b.content),
        })
        ..write(b.separator);
    }
    return out.toString();
  }

  /// Escapes plain [text] so it parses as Markdown that renders (and
  /// [toPlainText]s) back to exactly [text]: the lossless migration step of a
  /// plain note into the Markdown model (ADR 0035).
  static String escapePlainText(String text) {
    final lines = text.split('\n');
    final out = StringBuffer();
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      final cr = line.endsWith('\r');
      if (cr) line = line.substring(0, line.length - 1);
      var escaped = line.replaceAllMapped(_inlineSpecial, (m) => '\\${m[0]}');
      escaped = escaped.replaceFirstMapped(
        _lineStartSpecial,
        (m) => '${m[1]}${m[2]}\\${m[3]}',
      );
      final hasNext = i + 1 < lines.length;
      // A single line break inside a paragraph is a soft break in Markdown
      // (rendered as a space); a trailing backslash keeps it a real break.
      if (hasNext && line.trim().isNotEmpty && lines[i + 1].trim().isNotEmpty) {
        escaped += '\\';
      }
      out
        ..write(escaped)
        ..write(cr ? '\r' : '');
      if (hasNext) out.write('\n');
    }
    return out.toString();
  }

  static String _fenceBody(String content) {
    final first = content.indexOf('\n');
    if (first < 0) return '';
    var body = content.substring(first + 1);
    final last = body.lastIndexOf('\n');
    final tail = last < 0 ? body : body.substring(last + 1);
    if (_fence.hasMatch(tail)) body = last < 0 ? '' : body.substring(0, last);
    return body.endsWith('\r') ? body.substring(0, body.length - 1) : body;
  }

  static String _inline(String s) {
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      final next = i + 1 < s.length ? s[i + 1] : '';
      if (c == r'\' && (next == '\n' || next == '\r')) continue;
      if (c == r'\' && next.isNotEmpty && _asciiPunct.hasMatch(next)) {
        out.write(next);
        i++;
        continue;
      }
      if (c == '*' || c == '`') continue;
      if (c == '_' && !(_wordChar(i - 1, s) && _wordChar(i + 1, s))) continue;
      out.write(c);
    }
    return out.toString();
  }

  static bool _wordChar(int i, String s) =>
      i >= 0 && i < s.length && _word.hasMatch(s[i]);

  static bool _isSpace(int c) => c == 0x20 || c == 0x0A || c == 0x0D;
  static bool _isSentenceEnd(int c) =>
      c == 0x2E || c == 0x21 || c == 0x3F || c == 0x2026;
}

final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]|$)');
final _listItem = RegExp(r'^[ \t]*(?:[-*+]|\d{1,9}[.)])[ \t]');
final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final _headingStrip = RegExp(r'^ {0,3}#{1,6}[ \t]*');
final _inlineSpecial = RegExp(r'[\\`*_\[\]<>~|]');
final _lineStartSpecial = RegExp(r'^( {0,3})(\d{0,9})([#+=.)-])');
final _asciiPunct = RegExp(r'''[!-/:-@\[-`{-~]''');
final _word = RegExp(r'[\p{L}\p{N}]', unicode: true);

class _Parsed {
  _Parsed(this.leading, this.blocks);
  final String leading;
  final List<MarkdownBlock> blocks;
}

/// Splits [s] into lines that keep their terminator (`\n` or `\r\n`).
List<String> _lines(String s) {
  final out = <String>[];
  var start = 0;
  while (start < s.length) {
    final nl = s.indexOf('\n', start);
    if (nl < 0) {
      out.add(s.substring(start));
      break;
    }
    out.add(s.substring(start, nl + 1));
    start = nl + 1;
  }
  return out;
}

String _body(String line) {
  if (line.endsWith('\r\n')) return line.substring(0, line.length - 2);
  if (line.endsWith('\n')) return line.substring(0, line.length - 1);
  return line;
}

String _eol(String line) => line.substring(_body(line).length);

bool _isBlank(String line) => _body(line).trim().isEmpty;

_Parsed _parse(String source) {
  final lines = _lines(source);
  final blocks = <MarkdownBlock>[];
  final leading = StringBuffer();
  var i = 0;

  void emit(BlockKind kind, int from, int to, {int level = 0}) {
    // Lines [from, to) form the block; the last terminator goes to separator.
    final buf = StringBuffer();
    for (var k = from; k < to - 1; k++) {
      buf.write(lines[k]);
    }
    final last = lines[to - 1];
    buf.write(_body(last));
    blocks.add(
      MarkdownBlock(
        kind: kind,
        content: buf.toString(),
        separator: _eol(last),
        headingLevel: level,
      ),
    );
  }

  while (i < lines.length) {
    final line = lines[i];
    final body = _body(line);
    if (_isBlank(line)) {
      if (blocks.isEmpty) {
        leading.write(line);
      } else {
        blocks.last.separator += line;
      }
      i++;
      continue;
    }
    final fence = _fence.firstMatch(body);
    if (fence != null) {
      final j = _fenceEnd(lines, i, fence.group(1)!);
      emit(BlockKind.codeFence, i, j);
      i = j;
      continue;
    }
    final heading = _heading.firstMatch(body);
    if (heading != null) {
      emit(BlockKind.heading, i, i + 1, level: heading.group(1)!.length);
      i++;
      continue;
    }
    if (_listItem.hasMatch(body)) {
      final j = _listItemEnd(lines, i);
      emit(BlockKind.listItem, i, j);
      i = j;
      continue;
    }
    final j = _paragraphEnd(lines, i);
    emit(BlockKind.paragraph, i, j);
    i = j;
  }
  return _Parsed(leading.toString(), blocks);
}

/// Line index after the fence opened at [i] (closing fence included).
int _fenceEnd(List<String> lines, int i, String marker) {
  final closing = marker[0] * marker.length;
  var j = i + 1;
  while (j < lines.length) {
    final t = _body(lines[j]).trimLeft();
    j++;
    if (t.startsWith(closing) && t.replaceAll(marker[0], '').trim().isEmpty) {
      break;
    }
  }
  return j;
}

/// Line index after the list item at [i] with its indented continuation.
int _listItemEnd(List<String> lines, int i) {
  var j = i + 1;
  while (j < lines.length &&
      !_isBlank(lines[j]) &&
      !_listItem.hasMatch(_body(lines[j])) &&
      (lines[j].startsWith(' ') || lines[j].startsWith('\t'))) {
    j++;
  }
  return j;
}

/// Line index after the paragraph starting at [i].
int _paragraphEnd(List<String> lines, int i) {
  var j = i + 1;
  while (j < lines.length) {
    final b = _body(lines[j]);
    if (_isBlank(lines[j]) ||
        _heading.hasMatch(b) ||
        _fence.hasMatch(b) ||
        _listItem.hasMatch(b)) {
      break;
    }
    j++;
  }
  return j;
}
