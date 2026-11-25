import 'entry_link.dart';

/// Turns the Markdown a note or snippet carries into plain text for apps that
/// do not render it (issue #644): a mail or chat field should receive
/// "Hello world", not "**Hello** _world_".
///
/// Only the markers are removed, the words stay; line structure is kept.
/// - Headings lose their `#`, quotes their `>`.
/// - Paired markers (`**`, `__`, `*`, `_`, `~~`, `==`, backticks) are removed
///   only when they really enclose text, so "5 * 3" and "snake_case" survive.
/// - Links become "text (url)", or just the url when both are the same;
///   images become their alt text; `<https://…>` becomes the url.
/// - Links to notes, recordings and snippets (`[[note:<id>|Label]]`, #660)
///   become their label; the id means nothing outside the app.
/// - Code fences disappear, their content stays verbatim.
/// - Backslash escapes resolve to the escaped character.
/// - List markers (`- `, `* `, `1. `) stay: they read as plain text and carry
///   the list structure. Checklist items lose bullet and brackets and become
///   a box character, `☐ open` and `☑ done` (#643).
///
/// Text without Markdown comes back unchanged. Pure and synchronous: callers
/// run it on the paste and copy paths without a measurable delay.
String markdownToPlainText(String source) {
  if (source.isEmpty) return source;
  final lines = source.split('\n');
  final out = <String>[];
  var inFence = false;
  String? fenceMarker;
  for (final rawLine in lines) {
    // Keep a Windows line ending exactly where it was.
    final hasCr = rawLine.endsWith('\r');
    final line = hasCr ? rawLine.substring(0, rawLine.length - 1) : rawLine;
    final fence = _fenceOpen.firstMatch(line);
    if (inFence) {
      if (fence != null &&
          fence.group(2)!.startsWith(fenceMarker!) &&
          line.trim().length == fence.group(2)!.length) {
        inFence = false;
        fenceMarker = null;
        continue;
      }
      out.add(rawLine);
      continue;
    }
    if (fence != null) {
      inFence = true;
      fenceMarker = fence.group(2);
      continue;
    }
    final converted = _convertLine(line);
    out.add(hasCr ? '$converted\r' : converted);
  }
  return out.join('\n');
}

final _fenceOpen = RegExp(r'^(\s{0,3})(`{3,}|~{3,})');
final _heading = RegExp(r'^(\s{0,3})#{1,6}(?:\s+|$)');
final _headingClose = RegExp(r'\s+#+\s*$');
final _quote = RegExp(r'^(\s{0,3})>\s?');
final _listMarker = RegExp(r'^(\s*(?:[-*+]|\d{1,9}[.)])\s+(?:\[[ xX]\]\s+)?)');
final _taskBox = RegExp(r'^(\s*)(?:[-*+]|\d{1,9}[.)])\s+\[([ xX])\]\s+$');
final _escape = RegExp(r'\\([\\`*_{}\[\]()#+\-.!>~=|<])');
final _codeSpan = RegExp(r'(`+)(.+?)\1');
final _image = RegExp(r'!\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)');
final _link = RegExp(r'\[([^\]]+)\]\(([^)\s]*)(?:\s+"[^"]*")?\)');
final _autolink = RegExp(r'<((?:https?|mailto):[^>\s]+)>');
final _hardBreak = RegExp(r'\\$');

// Paired markers, longest first. Each needs a non-space character right
// inside both markers (CommonMark flanking); the underscore forms also must
// not touch a word character outside, so "snake_case_name" stays.
final _pairs = <RegExp>[
  RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*'),
  RegExp(
    r'(?<![\p{L}\p{N}_])__(?=\S)(.+?)(?<=\S)__(?![\p{L}\p{N}_])',
    unicode: true,
  ),
  RegExp(r'~~(?=\S)(.+?)(?<=\S)~~'),
  RegExp(r'==(?=\S)(.+?)(?<=\S)=='),
  RegExp(r'(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)'),
  RegExp(
    r'(?<![\p{L}\p{N}_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\p{L}\p{N}_])',
    unicode: true,
  ),
];

// Protected spans (escapes, code) are swapped for private-use placeholders so
// the marker passes cannot touch them, then restored at the end.
const _placeholderBase = 0xE000;
final _placeholder = RegExp('[-]');

String _convertLine(String line) {
  final protected = <String>[];
  String protect(String text) {
    protected.add(text);
    return String.fromCharCode(_placeholderBase + protected.length - 1);
  }

  var text = line;
  var prefix = '';

  final heading = _heading.firstMatch(text);
  if (heading != null) {
    text = text.substring(heading.end).replaceFirst(_headingClose, '');
  } else {
    // Nested quotes ("> > text") lose every level.
    var quote = _quote.firstMatch(text);
    while (quote != null) {
      text = text.substring(quote.end);
      quote = _quote.firstMatch(text);
    }
    final list = _listMarker.firstMatch(text);
    if (list != null) {
      prefix = list.group(1)!;
      text = text.substring(list.end);
      // A checklist box reads as a box, not as "[ ]" (#643).
      final box = _taskBox.firstMatch(prefix);
      if (box != null) {
        prefix = '${box.group(1)}${box.group(2) == ' ' ? '☐' : '☑'} ';
      }
    }
  }

  text = text.replaceFirst(_hardBreak, '');
  text = text.replaceAllMapped(_escape, (m) => protect(m.group(1)!));
  text = text.replaceAllMapped(_codeSpan, (m) => protect(m.group(2)!));
  text = text.replaceAllMapped(entryLinkPattern, (m) {
    if (parseEntryLinkTarget(m.group(1)!) == null) return m.group(0)!;
    return m.group(2)?.trim() ?? '';
  });
  text = text.replaceAllMapped(_image, (m) => m.group(1)!);
  text = text.replaceAllMapped(_link, (m) {
    final label = m.group(1)!;
    final url = m.group(2)!;
    if (url.isEmpty) return label;
    if (label == url) return protect(url);
    return '$label (${protect(url)})';
  });
  text = text.replaceAllMapped(_autolink, (m) => protect(m.group(1)!));

  // Repeat so nested markers ("**_both_**") resolve completely.
  for (var round = 0; round < 4; round++) {
    final before = text;
    for (final pair in _pairs) {
      text = text.replaceAllMapped(pair, (m) => m.group(1)!);
    }
    if (text == before) break;
  }

  if (protected.isNotEmpty) {
    text = text.replaceAllMapped(_placeholder, (m) {
      final index = m.group(0)!.codeUnitAt(0) - _placeholderBase;
      return index < protected.length ? protected[index] : m.group(0)!;
    });
  }
  return '$prefix$text';
}
