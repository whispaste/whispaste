/// Derived, disposable metadata. Offsets are UTF-16 source offsets, matching
/// TextSelection; the Markdown source remains the only editable document.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../utils/word_count.dart';

enum ContentKind { recording, recordingEdited, note, snippet }

typedef ContentKey = ({ContentKind kind, String id});
typedef ContentHeading = ({String text, int level, int offset});
typedef ContentLink = ({String target, int offset});
typedef ContentChecklist = ({bool checked, int offset});

class ContentMetadata {
  const ContentMetadata({
    required this.hash,
    required this.headings,
    required this.links,
    required this.tags,
    required this.wordCount,
    required this.characterCount,
    required this.checklists,
  });

  // Bump whenever parsing semantics change. Old caches then rebuild on demand.
  static const version = 1;
  final String hash;
  final List<ContentHeading> headings;
  final List<ContentLink> links;
  final List<String> tags;
  final int wordCount;
  final int characterCount;
  final List<ContentChecklist> checklists;
  int get checkedCount => checklists.where((item) => item.checked).length;

  Map<String, Object> toJson() => {
    'version': version,
    'hash': hash,
    'headings': [
      for (final h in headings)
        {'text': h.text, 'level': h.level, 'offset': h.offset},
    ],
    'links': [
      for (final l in links) {'target': l.target, 'offset': l.offset},
    ],
    'tags': tags,
    'words': wordCount,
    'characters': characterCount,
    'checklists': [
      for (final c in checklists) {'checked': c.checked, 'offset': c.offset},
    ],
  };

  factory ContentMetadata.fromJson(Map<String, dynamic> json) {
    if (json['version'] != version) {
      throw const FormatException('Index version');
    }
    final result = ContentMetadata(
      hash: json['hash'] as String,
      headings: List.unmodifiable([
        for (final h in (json['headings'] as List).cast<Map<String, dynamic>>())
          (
            text: h['text'] as String,
            level: h['level'] as int,
            offset: h['offset'] as int,
          ),
      ]),
      links: List.unmodifiable([
        for (final l in (json['links'] as List).cast<Map<String, dynamic>>())
          (target: l['target'] as String, offset: l['offset'] as int),
      ]),
      tags: List<String>.unmodifiable(json['tags'] as List),
      wordCount: json['words'] as int,
      characterCount: json['characters'] as int,
      checklists: List.unmodifiable([
        for (final c
            in (json['checklists'] as List).cast<Map<String, dynamic>>())
          (checked: c['checked'] as bool, offset: c['offset'] as int),
      ]),
    );
    if (result.wordCount < 0 ||
        result.characterCount < 0 ||
        result.headings.any(
          (h) => h.level < 1 || h.level > 6 || !result._validOffset(h.offset),
        ) ||
        result.links.any((l) => !result._validOffset(l.offset)) ||
        result.checklists.any((c) => !result._validOffset(c.offset))) {
      throw const FormatException('Index bounds');
    }
    return result;
  }

  bool _validOffset(int offset) => offset >= 0 && offset < characterCount;
}

String contentHash(String text) => sha256.convert(utf8.encode(text)).toString();

/// Cache validation runs in the worker too, including JSON and integrity hash.
ContentMetadata? decodeContentMetadata(
  String payload,
  String digest,
  String hash,
) {
  try {
    if (contentHash(payload) != digest) return null;
    final metadata = ContentMetadata.fromJson(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    return metadata.hash == hash ? metadata : null;
  } on Object {
    return null;
  }
}

/// Pure parser shared by recordings, notes and snippets. Word counts preserve
/// the app's whitespace-delimited source semantics, including fenced code.
/// Links/tags/tasks inside code or escaped Markdown are not navigable metadata.
ContentMetadata parseContentMetadata(String source) =>
    _MetadataParser(source).parse();

class _MetadataParser {
  _MetadataParser(this.source);
  final String source;
  final headings = <ContentHeading>[];
  final links = <ContentLink>[];
  final tags = <String>{};
  final checklists = <ContentChecklist>[];
  String? previous;
  var previousOffset = 0;
  var offset = 0;

  ContentMetadata parse() {
    String? fence;
    for (final raw in source.split('\n')) {
      final line = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final marker = _fence.firstMatch(line)?.group(1);
      if (fence != null) {
        if (marker != null &&
            marker[0] == fence[0] &&
            marker.length >= fence.length &&
            line.trim().replaceAll(marker[0], '').isEmpty) {
          fence = null;
        }
        previous = null;
      } else if (marker != null) {
        fence = marker;
        previous = null;
      } else if (line.startsWith('    ') || line.startsWith('\t')) {
        previous = null;
      } else {
        _collectMarkdown(line);
      }
      offset += raw.length + 1;
    }
    return ContentMetadata(
      hash: contentHash(source),
      headings: List.unmodifiable(headings),
      links: List.unmodifiable(links),
      tags: List.unmodifiable(tags.toList()..sort()),
      wordCount: computeWordCountFast(source),
      characterCount: source.length,
      checklists: List.unmodifiable(checklists),
    );
  }

  void _collectMarkdown(String line) {
    final previousLine = previous;
    final heading = _heading.firstMatch(line);
    final setext = _setext.firstMatch(line);
    if (heading != null) {
      headings.add((
        text: heading.group(2)!.replaceFirst(_closingHeading, '').trim(),
        level: heading.group(1)!.length,
        offset: offset,
      ));
    } else if (setext != null &&
        previousLine != null &&
        previousLine.trim().isNotEmpty) {
      headings.add((
        text: previousLine.trim(),
        level: setext.group(1)![0] == '=' ? 1 : 2,
        offset: previousOffset,
      ));
    }
    final task = _task.firstMatch(line);
    if (task != null) {
      checklists.add((
        checked: task.group(1)!.toLowerCase() == 'x',
        offset: offset + line.indexOf('['),
      ));
    }
    var inline = line
        .replaceAllMapped(_inlineCode, (m) => ' ' * m[0]!.length)
        .replaceAllMapped(_escape, (m) => ' ' * m[0]!.length);
    inline = inline.replaceAllMapped(_link, (m) {
      final target = m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4)!;
      links.add((target: target.trim(), offset: offset + m.start));
      return ' ' * m[0]!.length;
    });
    for (final tag in _tag.allMatches(inline)) {
      tags.add(tag.group(1)!);
    }
    previous = heading == null && setext == null && task == null ? line : null;
    previousOffset = offset;
  }
}

final _fence = RegExp(r'^ {0,3}(`{3,}|~{3,})');
final _heading = RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+|$)(.*)$');
final _closingHeading = RegExp(r'[ \t]+#+[ \t]*$');
final _setext = RegExp(r'^ {0,3}(=+|-+)[ \t]*$');
final _task = RegExp(r'^ {0,3}(?:[-+*]|\d+[.)])[ \t]+\[([ xX])\](?:[ \t]|$)');
final _inlineCode = RegExp(r'(`+).*?\1');
final _escape = RegExp(r'\\[!-/:-@\[-`{-~]');
final _link = RegExp(
  r'\[\[([^\]|]+)(?:\|[^\]]*)?\]\]|(?<!!)\[[^\]]*\]\(<?([^\s)>]+)>?(?:\s+"[^"]*")?\)|<(https?://[^>]+)>|(https?://[^\s<>]+)',
  caseSensitive: false,
);
final _tag = RegExp(r'(?:^|\s)#([\p{L}\p{N}_][\p{L}\p{N}_/-]*)', unicode: true);
