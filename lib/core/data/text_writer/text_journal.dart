/// Write-ahead journal of the text writer (#676).
///
/// Between two saves the editor's text only lives in memory. The journal
/// keeps that window small: every few hundred milliseconds the writer
/// appends the small change since the last record (one splice), and after a
/// successful save the journal of that document starts over. On the next
/// start [TextJournal.readAll] hands back what a crash left behind, and the
/// writer replays it onto the stored text.
///
/// The journal is non-losable data (CONTEXT §Schreibweg): it lives next to
/// the database, never in a cache folder.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Identity of one text document: its kind ('note', 'recording', …) and id.
class TextDocKey {
  const TextDocKey(this.kind, this.id);

  final String kind;
  final String id;

  @override
  bool operator ==(Object other) =>
      other is TextDocKey && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => '$kind:$id';
}

/// One splice: replace [deleteCount] UTF-16 units at [start] by [inserted].
class TextDelta {
  const TextDelta(this.start, this.deleteCount, this.inserted);

  final int start;
  final int deleteCount;
  final String inserted;

  /// The single splice that turns [from] into [to] (common prefix and
  /// suffix kept), or null when both are equal.
  static TextDelta? between(String from, String to) {
    if (from == to) return null;
    final max = from.length < to.length ? from.length : to.length;
    var pre = 0;
    while (pre < max && from.codeUnitAt(pre) == to.codeUnitAt(pre)) {
      pre++;
    }
    var suf = 0;
    while (suf < max - pre &&
        from.codeUnitAt(from.length - 1 - suf) ==
            to.codeUnitAt(to.length - 1 - suf)) {
      suf++;
    }
    return TextDelta(
      pre,
      from.length - pre - suf,
      to.substring(pre, to.length - suf),
    );
  }

  /// Applies the splice; throws [RangeError] when it does not fit [text].
  String apply(String text) {
    RangeError.checkValueInInterval(start, 0, text.length, 'start');
    RangeError.checkValueInInterval(
      start + deleteCount,
      start,
      text.length,
      'deleteCount',
    );
    return text.replaceRange(start, start + deleteCount, inserted);
  }

  Map<String, Object?> toJson() => {
    's': start,
    'd': deleteCount,
    'i': inserted,
  };

  static TextDelta fromJson(Map<String, Object?> json) =>
      TextDelta(json['s']! as int, json['d']! as int, json['i']! as String);
}

/// What a journal holds for one document: the base the deltas start from
/// (the last text known to be stored, null when unknown) and the deltas.
class TextJournalEntry {
  const TextJournalEntry(this.key, this.base, this.deltas);

  final TextDocKey key;
  final String? base;
  final List<TextDelta> deltas;

  /// The editor's text at the last journal record. A delta that does not
  /// fit (torn write) ends the replay — everything before it is kept.
  String replay() {
    var text = base ?? '';
    for (final d in deltas) {
      try {
        text = d.apply(text);
      } on RangeError {
        break;
      }
    }
    return text;
  }
}

abstract interface class TextJournal {
  /// Starts the journal of [key] over: [base] plus the first [delta].
  /// Atomic — a crash leaves either the old or the new journal.
  Future<void> start(TextDocKey key, String? base, TextDelta? delta);

  /// Appends one delta to the journal of [key].
  Future<void> append(TextDocKey key, TextDelta delta);

  /// Removes the journal of [key] (its text is stored).
  Future<void> clear(TextDocKey key);

  /// Every journal left behind.
  Future<List<TextJournalEntry>> readAll();
}

/// In-memory journal for tests: survives a "crash" of the writer as long as
/// the same instance is handed to the next one.
class MemoryTextJournal implements TextJournal {
  final Map<TextDocKey, TextJournalEntry> _entries = {};

  @override
  Future<void> start(TextDocKey key, String? base, TextDelta? delta) async {
    _entries[key] = TextJournalEntry(key, base, [?delta]);
  }

  @override
  Future<void> append(TextDocKey key, TextDelta delta) async {
    final e = _entries[key];
    if (e == null) return;
    e.deltas.add(delta);
  }

  @override
  Future<void> clear(TextDocKey key) async => _entries.remove(key);

  @override
  Future<List<TextJournalEntry>> readAll() async => _entries.values.toList();
}

/// One JSON-lines file per document under [directory]: a header line
/// `{v, k, id, b}` and one line per delta. Appends are flushed to disk.
class FileTextJournal implements TextJournal {
  FileTextJournal(this.directory);

  final String directory;
  static const _version = 1;
  static const _ext = '.jsonl';

  File _file(TextDocKey key) => File(
    p.join(
      directory,
      '${base64Url.encode(utf8.encode('${key.kind}\u0000${key.id}'))}$_ext',
    ),
  );

  @override
  Future<void> start(TextDocKey key, String? base, TextDelta? delta) async {
    await Directory(directory).create(recursive: true);
    final buf = StringBuffer()
      ..writeln(
        jsonEncode({'v': _version, 'k': key.kind, 'id': key.id, 'b': base}),
      );
    if (delta != null) buf.writeln(jsonEncode(delta.toJson()));
    final target = _file(key);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(buf.toString(), flush: true);
    await tmp.rename(target.path);
  }

  @override
  Future<void> append(TextDocKey key, TextDelta delta) async {
    final f = _file(key);
    if (!await f.exists()) return;
    await f.writeAsString(
      '${jsonEncode(delta.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<void> clear(TextDocKey key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<List<TextJournalEntry>> readAll() async {
    final dir = Directory(directory);
    if (!await dir.exists()) return const [];
    final out = <TextJournalEntry>[];
    await for (final f in dir.list()) {
      if (f is! File) continue;
      if (f.path.endsWith('$_ext.tmp')) {
        // A start() that never reached its rename: the old file is intact.
        await f.delete().catchError((_) => f);
        continue;
      }
      if (!f.path.endsWith(_ext)) continue;
      final entry = _parse(await f.readAsString());
      if (entry != null) out.add(entry);
    }
    return out;
  }

  static TextJournalEntry? _parse(String raw) {
    final lines = const LineSplitter().convert(raw);
    if (lines.isEmpty) return null;
    try {
      final head = jsonDecode(lines.first) as Map<String, Object?>;
      if (head['v'] != _version) return null;
      final key = TextDocKey(head['k']! as String, head['id']! as String);
      final deltas = <TextDelta>[];
      for (final line in lines.skip(1)) {
        try {
          deltas.add(
            TextDelta.fromJson(jsonDecode(line) as Map<String, Object?>),
          );
        } on Object {
          break; // torn last line after a crash
        }
      }
      return TextJournalEntry(key, head['b'] as String?, deltas);
    } on Object {
      return null;
    }
  }
}
