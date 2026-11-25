/// File exchange for single snippets or sets of them (#665).
///
/// Pure codec and import planner: no file access, no database. The page reads
/// the file the user chose (sandbox-safe) and hands the text here; the plan
/// it gets back is written in one transaction.
///
/// Two re-importable formats carry the same content per snippet: title, body,
/// kind and the interactive field names. Favourites, tags, usage counts and
/// dates are not part of the exchange: they describe how one person uses the
/// library, not the snippet itself.
///
/// JSON:
///   {"format":"whispaste-snippets","version":1,
///    "snippets":[{"title":…,"body":…,"kind":"static","fields":[]}]}
/// The import also reads any object with a `snippets` list, such as the
/// settings export, so a snippet can be taken from there without replacing
/// the whole library.
///
/// Markdown: a readable document. A file marker comment on the first line,
/// then per snippet a `## title` heading, a marker comment with the stored
/// title, kind and fields as JSON, and the body in a backtick fence longer
/// than any backtick run inside it. The heading is for people; the parser
/// reads the marker, so a title with Markdown characters survives.
///
/// Parsing is strict about content: every bad entry is reported with its
/// position and skipped, never guessed.
library;

import 'dart:convert';

/// Value of the `format` key in the JSON file.
const String snippetFileFormat = 'whispaste-snippets';

/// The only file version this build reads and writes.
const int snippetFileVersion = 1;

/// Files above this size are refused before parsing.
const int snippetFileMaxBytes = 2 * 1024 * 1024;

/// Entries above this count are not read; the result is marked truncated.
const int snippetFileMaxEntries = 2000;

/// File marker on the first line of the Markdown export.
const String snippetMarkdownFileMarker =
    '<!-- whispaste:snippets format=$snippetFileVersion -->';

const String _mdSnippetPrefix = '<!-- whispaste:snippet ';
const String _mdCommentEnd = ' -->';
final RegExp _mdFileMarker = RegExp(
  r'^<!-- whispaste:snippets format=(\d+) -->$',
);

/// Kinds a snippet can have (see `SnippetItem.kind`).
const String snippetKindStatic = 'static';
const String snippetKindInteractive = 'interactive';

/// One snippet as it appears in a file: already in stored form (title, body
/// and field names trimmed, no fields for a static snippet).
class SnippetFileEntry {
  const SnippetFileEntry({
    required this.title,
    required this.body,
    this.kind = snippetKindStatic,
    this.fields = const [],
  });

  final String title;
  final String body;
  final String kind;
  final List<String> fields;

  /// Same content: everything the exchange carries is equal.
  bool sameContent(SnippetFileEntry other) =>
      other.title == title &&
      other.body == body &&
      other.kind == kind &&
      _listEquals(other.fields, fields);

  SnippetFileEntry withTitle(String newTitle) =>
      SnippetFileEntry(title: newTitle, body: body, kind: kind, fields: fields);

  Map<String, Object?> toJson() => {
    'title': title,
    'body': body,
    'kind': kind,
    'fields': fields,
  };
}

enum SnippetFileType { json, markdown }

/// Why a whole file was refused, before any entry was read.
enum SnippetFileRefusal {
  /// Not a snippet file: no marker, unreadable JSON, or no snippet list.
  unsupportedFormat,

  /// A snippet file of a version this build does not read.
  unsupportedVersion,
}

/// Why one entry was skipped.
enum SnippetFileErrorReason {
  /// The entry is not an object or a field has the wrong type.
  malformed,
  missingTitle,
  emptyBody,
  unknownKind,

  /// An interactive snippet whose field names are missing, empty, repeated
  /// or not used as `{{name}}` in the body.
  invalidFields,
}

class SnippetFileError {
  const SnippetFileError({
    required this.position,
    required this.reason,
    this.title,
  });

  /// 1-based position of the entry in the file.
  final int position;
  final SnippetFileErrorReason reason;

  /// Title of the entry when it had one, to name it in the preview.
  final String? title;
}

class SnippetFileParseResult {
  const SnippetFileParseResult({
    this.entries = const [],
    this.errors = const [],
    this.refusal,
    this.truncated = false,
  });

  final List<SnippetFileEntry> entries;
  final List<SnippetFileError> errors;
  final SnippetFileRefusal? refusal;

  /// More than [snippetFileMaxEntries] entries; the rest was not read.
  final bool truncated;
}

// ---------------------------------------------------------------------------
// Encoding
// ---------------------------------------------------------------------------

String encodeSnippetFile(
  List<SnippetFileEntry> entries,
  SnippetFileType type,
) => switch (type) {
  SnippetFileType.json => encodeSnippetsJson(entries),
  SnippetFileType.markdown => encodeSnippetsMarkdown(entries),
};

String encodeSnippetsJson(List<SnippetFileEntry> entries) =>
    '${const JsonEncoder.withIndent('  ').convert({
      'format': snippetFileFormat,
      'version': snippetFileVersion,
      'snippets': [for (final e in entries) e.toJson()],
    })}\n';

String encodeSnippetsMarkdown(List<SnippetFileEntry> entries) {
  final out = StringBuffer()..writeln(snippetMarkdownFileMarker);
  for (final e in entries) {
    final meta = jsonEncode({
      'title': e.title,
      'kind': e.kind,
      'fields': e.fields,
    }).replaceAll('>', r'\u003e');
    final run = _longestBacktickRun(e.body) + 1;
    final fence = '`' * (run < 3 ? 3 : run);
    out
      ..writeln()
      ..writeln('## ${_headingText(e.title)}')
      ..writeln('$_mdSnippetPrefix$meta$_mdCommentEnd')
      ..writeln('${fence}text')
      ..writeln(e.body)
      ..writeln(fence);
  }
  return out.toString();
}

/// A one-line heading: line breaks would end it.
String _headingText(String title) =>
    title.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ');

int _longestBacktickRun(String text) {
  var longest = 0;
  var run = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0x60) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }
  return longest;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/// Which parser fits [fileName] and [text]: the extension decides, and a
/// file without a known one is read as JSON when it starts with `{`.
SnippetFileType snippetFileTypeFor(String fileName, String text) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.json')) return SnippetFileType.json;
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return SnippetFileType.markdown;
  }
  return _stripBom(text).trimLeft().startsWith('{')
      ? SnippetFileType.json
      : SnippetFileType.markdown;
}

SnippetFileParseResult parseSnippetFile(String text, SnippetFileType type) =>
    switch (type) {
      SnippetFileType.json => parseSnippetsJson(text),
      SnippetFileType.markdown => parseSnippetsMarkdown(text),
    };

SnippetFileParseResult parseSnippetsJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(_stripBom(text));
  } on FormatException {
    return const SnippetFileParseResult(
      refusal: SnippetFileRefusal.unsupportedFormat,
    );
  }
  if (decoded is! Map || decoded['snippets'] is! List) {
    return const SnippetFileParseResult(
      refusal: SnippetFileRefusal.unsupportedFormat,
    );
  }
  // Another format name (the settings export) is accepted as long as it
  // carries a snippet list, see the library comment.
  if (decoded['format'] == snippetFileFormat &&
      decoded['version'] != snippetFileVersion) {
    return const SnippetFileParseResult(
      refusal: SnippetFileRefusal.unsupportedVersion,
    );
  }
  final raw = decoded['snippets'] as List;
  return _validateAll(
    [
      for (final item in raw)
        item is Map
            ? item.cast<Object?, Object?>()
            : const <Object?, Object?>{},
    ],
    malformed: {
      for (var i = 0; i < raw.length; i++)
        if (raw[i] is! Map) i,
    },
  );
}

SnippetFileParseResult parseSnippetsMarkdown(String text) {
  final lines = _stripBom(
    text,
  ).replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final first = lines.indexWhere((l) => l.trim().isNotEmpty);
  final marker = first < 0
      ? null
      : _mdFileMarker.firstMatch(lines[first].trim());
  if (marker == null) {
    return const SnippetFileParseResult(
      refusal: SnippetFileRefusal.unsupportedFormat,
    );
  }
  if (int.tryParse(marker.group(1)!) != snippetFileVersion) {
    return const SnippetFileParseResult(
      refusal: SnippetFileRefusal.unsupportedVersion,
    );
  }

  final raw = <Map<Object?, Object?>>[];
  final malformed = <int>{};
  var i = first + 1;
  while (i < lines.length) {
    final line = lines[i].trim();
    i++;
    if (!line.startsWith(_mdSnippetPrefix) || !line.endsWith(_mdCommentEnd)) {
      continue;
    }
    final position = raw.length;
    Map<Object?, Object?> meta = const {};
    try {
      final decoded = jsonDecode(
        line.substring(
          _mdSnippetPrefix.length,
          line.length - _mdCommentEnd.length,
        ),
      );
      if (decoded is Map) {
        meta = decoded.cast<Object?, Object?>();
      } else {
        malformed.add(position);
      }
    } on FormatException {
      malformed.add(position);
    }
    // The body fence follows the marker, after optional blank lines.
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
    final open = i < lines.length
        ? RegExp(r'^(`{3,})[^`]*$').firstMatch(lines[i].trimRight())
        : null;
    if (open == null) {
      malformed.add(position);
      raw.add(meta);
      continue;
    }
    final fence = open.group(1)!;
    final body = <String>[];
    var closed = false;
    i++;
    while (i < lines.length) {
      if (lines[i].trimRight() == fence) {
        closed = true;
        i++;
        break;
      }
      body.add(lines[i]);
      i++;
    }
    if (!closed) malformed.add(position);
    raw.add({...meta, 'body': body.join('\n')});
  }
  if (raw.isEmpty) return const SnippetFileParseResult();
  return _validateAll(raw, malformed: malformed);
}

SnippetFileParseResult _validateAll(
  List<Map<Object?, Object?>> raw, {
  required Set<int> malformed,
}) {
  final truncated = raw.length > snippetFileMaxEntries;
  final entries = <SnippetFileEntry>[];
  final errors = <SnippetFileError>[];
  for (var i = 0; i < raw.length && i < snippetFileMaxEntries; i++) {
    final title = raw[i]['title'];
    final shownTitle = title is String && title.trim().isNotEmpty
        ? title.trim()
        : null;
    final result = malformed.contains(i)
        ? SnippetFileErrorReason.malformed
        : _validate(raw[i]);
    switch (result) {
      case final SnippetFileEntry entry:
        entries.add(entry);
      case final SnippetFileErrorReason reason:
        errors.add(
          SnippetFileError(position: i + 1, reason: reason, title: shownTitle),
        );
    }
  }
  return SnippetFileParseResult(
    entries: entries,
    errors: errors,
    truncated: truncated,
  );
}

/// The stored form of [raw], or why it cannot be stored. Mirrors the rules
/// of the snippet editor, so an imported snippet is one the editor accepts.
Object _validate(Map<Object?, Object?> raw) {
  final title = raw['title'];
  final body = raw['body'] ?? '';
  final kind = raw['kind'] ?? snippetKindStatic;
  final fields = raw['fields'] ?? const <Object?>[];
  if (title != null && title is! String) {
    return SnippetFileErrorReason.malformed;
  }
  if (body is! String || kind is! String || fields is! List) {
    return SnippetFileErrorReason.malformed;
  }
  final storedTitle = (title as String? ?? '').trim();
  if (storedTitle.isEmpty) return SnippetFileErrorReason.missingTitle;
  final storedBody = body.trim();
  if (kind == snippetKindStatic) {
    if (storedBody.isEmpty) return SnippetFileErrorReason.emptyBody;
    return SnippetFileEntry(title: storedTitle, body: storedBody);
  }
  if (kind != snippetKindInteractive) return SnippetFileErrorReason.unknownKind;
  if (fields.any((f) => f is! String)) return SnippetFileErrorReason.malformed;
  final names = [for (final f in fields.cast<String>()) f.trim()];
  if (names.isEmpty ||
      names.any((n) => n.isEmpty) ||
      names.toSet().length != names.length ||
      names.any((n) => !storedBody.contains('{{$n}}'))) {
    return SnippetFileErrorReason.invalidFields;
  }
  return SnippetFileEntry(
    title: storedTitle,
    body: storedBody,
    kind: snippetKindInteractive,
    fields: names,
  );
}

String _stripBom(String text) =>
    text.startsWith('\uFEFF') ? text.substring(1) : text;

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Import plan
// ---------------------------------------------------------------------------

/// What happens when an imported snippet has the title of one that exists.
enum SnippetConflictStrategy {
  /// Keep the existing snippet, leave the imported one out (default).
  skip,

  /// The imported content replaces the existing snippet's.
  overwrite,

  /// Import it beside the existing one under a numbered title, "Title (2)".
  keepBoth,
}

enum SnippetImportStatus {
  /// No snippet with this title: added.
  added,

  /// A snippet with this title and the same content exists: nothing to do.
  duplicate,

  /// Same title, other content, strategy [SnippetConflictStrategy.skip].
  conflictSkipped,

  /// Same title, other content, strategy [SnippetConflictStrategy.overwrite].
  conflictReplaced,

  /// Same title, other content, strategy [SnippetConflictStrategy.keepBoth]:
  /// added under [SnippetImportPlanRow.finalTitle].
  conflictKept,

  /// A later entry of the same file with this title replaced this one
  /// (strategy [SnippetConflictStrategy.overwrite]).
  supersededInFile,
}

class SnippetImportPlanRow {
  const SnippetImportPlanRow({
    required this.entry,
    required this.status,
    required this.finalTitle,
    this.existingId,
  });

  final SnippetFileEntry entry;
  final SnippetImportStatus status;

  /// The title it is stored under (differs for [SnippetImportStatus.conflictKept]).
  final String finalTitle;

  /// Id of the existing snippet it replaces ([SnippetImportStatus.conflictReplaced]).
  final String? existingId;

  bool get writes =>
      status == SnippetImportStatus.added ||
      status == SnippetImportStatus.conflictReplaced ||
      status == SnippetImportStatus.conflictKept;

  bool get isConflict =>
      status == SnippetImportStatus.conflictSkipped ||
      status == SnippetImportStatus.conflictReplaced ||
      status == SnippetImportStatus.conflictKept;
}

/// One write of an applied plan: [id] is the existing snippet to replace,
/// `null` for a new one.
typedef SnippetImportWrite = ({
  String? id,
  String title,
  String body,
  String kind,
  List<String> fields,
});

class SnippetImportPlan {
  const SnippetImportPlan(this.rows);

  final List<SnippetImportPlanRow> rows;

  int count(SnippetImportStatus status) =>
      rows.where((r) => r.status == status).length;

  int get conflictCount => rows.where((r) => r.isConflict).length;

  int get writeCount => rows.where((r) => r.writes).length;

  List<SnippetImportWrite> get writes => [
    for (final r in rows)
      if (r.writes)
        (
          id: r.existingId,
          title: r.finalTitle,
          body: r.entry.body,
          kind: r.entry.kind,
          fields: r.entry.fields,
        ),
  ];
}

/// An existing snippet the plan compares against. Only active snippets are
/// passed: the trash is never touched by an import and never a conflict.
typedef SnippetImportExisting = ({String id, SnippetFileEntry entry});

String _titleKey(String title) => title.trim().toLowerCase();

/// Plans the import of [entries] into a library holding [existing].
///
/// Titles are compared trimmed and case-insensitively, against the library
/// and against earlier entries of the same file. Nothing existing changes
/// unless [strategy] is [SnippetConflictStrategy.overwrite].
SnippetImportPlan planSnippetImport(
  List<SnippetFileEntry> entries,
  List<SnippetImportExisting> existing, {
  SnippetConflictStrategy strategy = SnippetConflictStrategy.skip,
}) {
  final rows = <SnippetImportPlanRow>[];
  final library = {for (final e in existing) _titleKey(e.entry.title): e};
  // Title key → index in [rows] of the file entry that holds that title.
  final fromFile = <String, int>{};
  final taken = {for (final e in existing) _titleKey(e.entry.title)};

  for (final entry in entries) {
    final key = _titleKey(entry.title);
    final earlier = fromFile[key];
    final match = library[key];

    // Compared against an earlier entry of the file first: that one already
    // decided what happens to this title.
    if (earlier != null) {
      final prior = rows[earlier];
      final priorContent = prior.writes ? prior.entry : match?.entry;
      if (priorContent != null &&
          priorContent.withTitle(entry.title).sameContent(entry)) {
        rows.add(
          SnippetImportPlanRow(
            entry: entry,
            status: SnippetImportStatus.duplicate,
            finalTitle: entry.title,
          ),
        );
        continue;
      }
    } else if (match == null) {
      rows.add(
        SnippetImportPlanRow(
          entry: entry,
          status: SnippetImportStatus.added,
          finalTitle: entry.title,
        ),
      );
      fromFile[key] = rows.length - 1;
      taken.add(key);
      continue;
    } else if (match.entry.withTitle(entry.title).sameContent(entry)) {
      rows.add(
        SnippetImportPlanRow(
          entry: entry,
          status: SnippetImportStatus.duplicate,
          finalTitle: match.entry.title,
        ),
      );
      fromFile[key] = rows.length - 1;
      continue;
    }

    switch (strategy) {
      case SnippetConflictStrategy.skip:
        rows.add(
          SnippetImportPlanRow(
            entry: entry,
            status: SnippetImportStatus.conflictSkipped,
            finalTitle: entry.title,
          ),
        );
        fromFile.putIfAbsent(key, () => rows.length - 1);
      case SnippetConflictStrategy.keepBoth:
        final title = _numberedTitle(entry.title, taken);
        taken.add(_titleKey(title));
        // A repeat of this entry later in the file is then a duplicate.
        fromFile.putIfAbsent(key, () => rows.length);
        rows.add(
          SnippetImportPlanRow(
            entry: entry,
            status: SnippetImportStatus.conflictKept,
            finalTitle: title,
          ),
        );
      case SnippetConflictStrategy.overwrite:
        // The last entry of the file wins over earlier ones with its title.
        final prior = earlier == null ? null : rows[earlier];
        if (prior != null && prior.writes) {
          rows[earlier!] = SnippetImportPlanRow(
            entry: prior.entry,
            status: SnippetImportStatus.supersededInFile,
            finalTitle: prior.finalTitle,
          );
        }
        final replacesExisting = match != null;
        rows.add(
          SnippetImportPlanRow(
            entry: entry,
            status: replacesExisting
                ? SnippetImportStatus.conflictReplaced
                : SnippetImportStatus.added,
            finalTitle: replacesExisting ? match.entry.title : entry.title,
            existingId: match?.id,
          ),
        );
        fromFile[key] = rows.length - 1;
    }
  }
  return SnippetImportPlan(rows);
}

/// "[title] (n)" with the smallest n from 2 whose title is not [taken].
String _numberedTitle(String title, Set<String> taken) {
  for (var n = 2; ; n++) {
    final candidate = '$title ($n)';
    if (!taken.contains(_titleKey(candidate))) return candidate;
  }
}
