/// The one write path for user text: recordings, notes, snippets (#676).
///
/// Every editor hands its text to [TextWriter.shared] instead of writing to
/// the database itself. The writer
///   - saves after a quiet pause ([quietPauseFor]: 2 s, longer for long
///     texts) and at once on [flush] / [flushAll] (close, entry switch,
///     focus loss, quit);
///   - journals small deltas every [journalInterval] in between, so a crash
///     loses at most that much typing ([TextJournal]);
///   - runs all saves one after the other under one lock, so two windows or
///     flows never write the same row concurrently;
///   - reads the stored text before saving and merges a change made
///     elsewhere since the last save paragraph by paragraph
///     ([mergeParagraphs]) — it never silently overwrites it;
///   - on a failed save keeps the text pending, writes a local backup file
///     and reports the failure on [failures]; [flush] never throws.
///
/// Typing never waits for any of this: [schedule] only stores the text and
/// (re)arms timers. The dictation hotkey path does not go through here.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:synchronized/synchronized.dart';

import '../../logging/app_logger.dart';
import 'paragraph_merge.dart';
import 'text_journal.dart';

export 'text_journal.dart' show TextDocKey;

final _log = AppLogger('TextWriter');

/// Stores [text] as the document's content.
typedef TextSave = Future<void> Function(String text);

/// Reads the document's stored content; null when it no longer exists.
typedef TextLoad = Future<String?> Function();

/// How a stored document is read and written, per kind — used to replay
/// journals left by a crash ([TextWriter.recover]).
class TextDocAccess {
  const TextDocAccess({required this.load, required this.save});

  final Future<String?> Function(String id) load;
  final Future<void> Function(String id, String text) save;
}

/// A save that combined the editor's text with a change made elsewhere.
class TextMerge {
  const TextMerge(
    this.key, {
    required this.ours,
    required this.merged,
    required this.conflict,
  });

  final TextDocKey key;

  /// The editor's text that went into the merge.
  final String ours;

  /// What is stored now.
  final String merged;

  /// Both sides changed the same paragraph; [merged] holds both versions.
  final bool conflict;
}

/// A save that failed; the text stays pending and is retried.
class TextWriteFailure {
  const TextWriteFailure(this.key, this.error, {this.backupPath});

  final TextDocKey key;
  final Object error;

  /// Local copy of the unsaved text, null when even that failed.
  final String? backupPath;
}

/// Quiet pause before an automatic save: 2 s up to 20 000 characters, one
/// more second per further 20 000, at most 6 s — a long text costs more to
/// write, so it is written less often (the journal covers the gap).
Duration quietPauseFor(int length) {
  final extra = length <= 20000 ? 0 : (length - 1) ~/ 20000;
  return Duration(seconds: (2 + extra).clamp(2, 6));
}

const journalInterval = Duration(milliseconds: 300);

/// First automatic retry after a failed save; doubles per further failure.
const retryDelay = Duration(seconds: 10);
const _maxRetryDelay = Duration(minutes: 5);

class _Doc {
  _Doc(this.key);

  final TextDocKey key;

  /// Last text of the editor's lineage known to be stored. Base of the
  /// paragraph merge and of the journal; null while unknown.
  String? base;
  bool baseKnown = false;

  /// Text waiting to be saved, null when everything is stored.
  String? pending;
  TextSave? save;
  TextLoad? load;

  /// What the last successful save stored (may include merged text).
  String? stored;
  Future<void>? baseLoading;
  int failedSaves = 0;

  Timer? quiet;
  Timer? journalTick;

  /// Text at the last journal record; null when the journal is not started.
  String? journaled;
  String? backupPath;
}

class TextWriter {
  TextWriter({this._journal, this._backupDirectory, this._backupWriter});

  /// The process-wide writer. [configure] it once at start.
  static TextWriter shared = TextWriter();

  TextJournal? _journal;
  String? _backupDirectory;

  /// Test hook replacing the backup file write.
  final Future<String?> Function(TextDocKey key, String text)? _backupWriter;

  final Lock _writeLock = Lock();
  final Lock _journalLock = Lock();
  final Map<TextDocKey, _Doc> _docs = {};
  final _merges = StreamController<TextMerge>.broadcast();
  final _failures = StreamController<TextWriteFailure>.broadcast();

  Stream<TextMerge> get merges => _merges.stream;
  Stream<TextWriteFailure> get failures => _failures.stream;

  /// Where the journal and the backups live (both non-losable data).
  void configure({
    required TextJournal journal,
    required String backupDirectory,
  }) {
    _journal = journal;
    _backupDirectory = backupDirectory;
  }

  /// The editor opened [key] showing [text] as stored: the base for the
  /// next merge. Ignored while edits of [key] are pending.
  void opened(TextDocKey key, String text) {
    final doc = _docs.putIfAbsent(key, () => _Doc(key));
    if (doc.pending != null) return;
    doc
      ..base = text
      ..baseKnown = true;
  }

  bool hasPending(TextDocKey key) => _docs[key]?.pending != null;

  /// Notes [text] as the editor's new content of [key]; saved after the
  /// quiet pause or on the next [flush]. [load] enables the merge with a
  /// change made elsewhere.
  void schedule(
    TextDocKey key,
    String text, {
    required TextSave save,
    TextLoad? load,
  }) {
    final doc = _docs.putIfAbsent(key, () => _Doc(key));
    doc
      ..pending = text
      ..save = save
      ..load = load ?? doc.load;
    if (!doc.baseKnown && doc.load != null && doc.baseLoading == null) {
      // The stored text when typing began is the base of a later merge.
      final load = doc.load!;
      doc.baseLoading = load().then((stored) {
        if (doc.baseKnown) return;
        doc
          ..base = stored
          ..baseKnown = true;
      }, onError: (Object _) {});
    }
    doc.quiet?.cancel();
    doc.quiet = Timer(quietPauseFor(text.length), () => unawaited(flush(key)));
    // Not re-armed per keystroke: while typing, a record lands every
    // [journalInterval] at the latest.
    if (_journal == null) return;
    doc.journalTick ??= Timer(journalInterval, () {
      doc.journalTick = null;
      unawaited(_journalPending(doc));
    });
  }

  /// Saves the pending text of [key] now. True when nothing is left pending.
  Future<bool> flush(TextDocKey key) async {
    final doc = _docs[key];
    if (doc == null) return true;
    doc.quiet?.cancel();
    doc.quiet = null;
    if (doc.pending == null) return true;
    return _writeLock.synchronized(() => _save(doc));
  }

  /// Saves every pending text (window blur, app pause, quit).
  Future<void> flushAll() async {
    for (final key in [..._docs.keys]) {
      await flush(key);
    }
  }

  /// Saves [text] as the content of [key] at once, through the same lock
  /// and merge as typed edits (explicit save buttons). Throws when the
  /// save fails, after the backup and the failure report.
  Future<String> writeNow(
    TextDocKey key,
    String text, {
    required TextSave save,
    TextLoad? load,
  }) async {
    final doc = _docs.putIfAbsent(key, () => _Doc(key));
    doc
      ..pending = text
      ..save = save
      ..load = load ?? doc.load;
    doc.quiet?.cancel();
    doc.quiet = null;
    return _writeLock.synchronized(() async {
      await _save(doc, rethrowError: true);
      return doc.stored ?? text;
    });
  }

  /// Drops pending edits of [key] without saving (the document was
  /// deleted, or the user discarded the edit).
  Future<void> discard(TextDocKey key) async {
    final doc = _docs.remove(key);
    if (doc == null) return;
    doc.quiet?.cancel();
    doc.journalTick?.cancel();
    await _journalLock.synchronized(() => _clearJournal(key));
  }

  Future<bool> _save(_Doc doc, {bool rethrowError = false}) async {
    final ours = doc.pending;
    final save = doc.save;
    if (ours == null || save == null) return true;
    try {
      await doc.baseLoading;
      if (!doc.baseKnown && doc.load != null) {
        // First save of a document the editor never announced: whatever
        // is stored now is what the editor started from.
        doc
          ..base = await doc.load!()
          ..baseKnown = true;
      }
      var toWrite = ours;
      ParagraphMergeResult? merge;
      final base = doc.base;
      if (doc.load != null && base != null) {
        final stored = await doc.load!();
        if (stored != null && stored != base && stored != ours) {
          merge = mergeParagraphs(base, ours, stored);
          toWrite = merge.text;
        }
      }
      await save(toWrite);
      // The editor's lineage is [ours]; [toWrite] may also carry the other
      // side. Keeping [ours] as base lets the next merge keep both again.
      doc
        ..base = ours
        ..baseKnown = true
        ..stored = toWrite
        ..failedSaves = 0;
      if (doc.pending == ours) {
        doc
          ..pending = null
          ..journalTick?.cancel()
          ..journalTick = null;
      }
      final backup = doc.backupPath;
      if (backup != null) {
        doc.backupPath = null;
        unawaited(_deleteQuietly(backup));
      }
      if (merge != null) {
        _merges.add(
          TextMerge(
            doc.key,
            ours: ours,
            merged: toWrite,
            conflict: merge.conflict,
          ),
        );
      }
      await _journalLock.synchronized(() async {
        if (doc.pending == null) {
          doc.journaled = null;
          await _clearJournal(doc.key);
        } else {
          await _restartJournal(doc);
        }
      });
      return doc.pending == null;
    } catch (e, st) {
      _log.warning('Save of ${doc.key.kind} failed: $e');
      final path = await _writeBackup(doc.key, ours);
      doc.backupPath = path ?? doc.backupPath;
      _failures.add(TextWriteFailure(doc.key, e, backupPath: doc.backupPath));
      // Retry on its own, backing off (10 s, 20 s, … at most 5 min); the
      // next keystroke or flush retries earlier.
      final wait = retryDelay * (1 << doc.failedSaves.clamp(0, 5));
      doc.failedSaves++;
      doc.quiet ??= Timer(
        wait > _maxRetryDelay ? _maxRetryDelay : wait,
        () => unawaited(flush(doc.key)),
      );
      if (rethrowError) Error.throwWithStackTrace(e, st);
      return false;
    }
  }

  Future<void> _journalPending(_Doc doc) => _journalLock.synchronized(() async {
    final text = doc.pending;
    final journal = _journal;
    if (text == null || journal == null) return;
    try {
      final last = doc.journaled;
      if (last == null) {
        await _restartJournal(doc);
      } else {
        final delta = TextDelta.between(last, text);
        if (delta == null) return;
        await journal.append(doc.key, delta);
        doc.journaled = text;
      }
    } catch (e) {
      // Best effort: the save itself still runs; only the crash window grows.
      _log.debug('Journal write failed: $e');
    }
  });

  /// Must run under [_journalLock].
  Future<void> _restartJournal(_Doc doc) async {
    final journal = _journal;
    final text = doc.pending;
    if (journal == null || text == null) return;
    try {
      await journal.start(
        doc.key,
        doc.base,
        TextDelta.between(doc.base ?? '', text),
      );
      doc.journaled = text;
    } catch (e) {
      doc.journaled = null;
      _log.debug('Journal restart failed: $e');
    }
  }

  Future<void> _clearJournal(TextDocKey key) async {
    try {
      await _journal?.clear(key);
    } catch (e) {
      _log.debug('Journal clear failed: $e');
    }
  }

  /// Writes [text] to `<backupDirectory>/<kind>-<id>.md` (tmp + rename).
  Future<String?> _writeBackup(TextDocKey key, String text) async {
    final custom = _backupWriter;
    if (custom != null) return custom(key, text);
    final dir = _backupDirectory;
    if (dir == null) return null;
    try {
      await Directory(dir).create(recursive: true);
      final safeId = key.id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final target = p.join(dir, '${key.kind}-$safeId.md');
      final tmp = File('$target.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(target);
      return target;
    } catch (e) {
      _log.warning('Backup write failed: $e');
      return null;
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  /// Replays the journals a crash left behind onto the stored texts.
  /// A document that no longer exists keeps its text as a backup file.
  /// Returns how many documents got text back.
  Future<int> recover(Map<String, TextDocAccess> access) async {
    final journal = _journal;
    if (journal == null) return 0;
    var restored = 0;
    final List<TextJournalEntry> entries;
    try {
      entries = await journal.readAll();
    } catch (e) {
      _log.warning('Journal read failed: $e');
      return 0;
    }
    for (final entry in entries) {
      final a = access[entry.key.kind];
      if (a == null) continue;
      try {
        final ours = entry.replay();
        final stored = await a.load(entry.key.id);
        if (stored == null) {
          if (ours.trim().isNotEmpty) await _writeBackup(entry.key, ours);
        } else {
          final text = entry.base == null
              ? ours
              : mergeParagraphs(entry.base!, ours, stored).text;
          if (text != stored) {
            await _writeLock.synchronized(() => a.save(entry.key.id, text));
            restored++;
          }
        }
        await journal.clear(entry.key);
      } catch (e) {
        // Keep the journal: the next start tries again.
        _log.warning('Journal replay of ${entry.key.kind} failed: $e');
      }
    }
    return restored;
  }

  /// Test hook: forget all state without saving (simulates a crash).
  void resetForTest() {
    for (final d in _docs.values) {
      d.quiet?.cancel();
      d.journalTick?.cancel();
    }
    _docs.clear();
  }
}
