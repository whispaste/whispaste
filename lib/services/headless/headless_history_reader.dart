/// Read-only access to the history database for `whispaste --transcribe-file
/// --replacements` (#1647).
///
/// The headless mode runs before the single-instance guard, often next to an
/// open WhisPaste. Opening the history the normal way would run the start
/// steps of the app (moving, encrypting, backups, schema upgrade, index
/// repair), which write to the file another process is using. This reader
/// opens a read-only SQLite connection instead, reads the text replacements
/// and closes it again: SQLite lets it read beside the running app, and it
/// cannot change a byte.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/data/database.dart'
    show
        HistoryKeyUnavailableException,
        historySchemaVersion,
        nestedHistoryPath,
        nestedPathMovePending;
import '../../core/data/history_encryption.dart' show isPlainSqliteFile;
import '../../core/data/sqlite_copy_check.dart' show openSqlite;
import '../replacements/text_replacement_matcher.dart';

/// The history needs a schema step that only the app performs; the headless
/// mode never upgrades it.
class HeadlessHistoryVersionException implements Exception {
  const HeadlessHistoryVersionException(this.storedVersion);

  final int storedVersion;

  @override
  String toString() =>
      'the history database has schema version $storedVersion, this build '
      'reads version $historySchemaVersion; open WhisPaste once so it updates '
      'its data, or run without --replacements';
}

/// The history file the app would open in [appDataDir]: the old nested
/// Windows file while its move is still pending, else `history.db`.
String headlessHistoryPath(String appDataDir, {bool? isWindows}) =>
    nestedPathMovePending(appDataDir, isWindows: isWindows)
    ? nestedHistoryPath(appDataDir)
    : p.join(appDataDir, 'history.db');

/// Reads the text replacement rules from the history in [appDataDir] over a
/// read-only connection, in the order the app applies them. No history file
/// yet means no rules. [keySource] is asked only for an encrypted file; it
/// must never create a key.
///
/// Throws [HistoryKeyUnavailableException] for an encrypted file without a
/// key, [HeadlessHistoryVersionException] for a file at another schema
/// version, and a [SqliteException] when the file cannot be read.
Future<List<TextReplacementRule>> readReplacementRulesReadOnly({
  required String appDataDir,
  required Future<String?> Function() keySource,
  bool? isWindows,
}) async {
  final path = headlessHistoryPath(appDataDir, isWindows: isWindows);
  if (!File(path).existsSync()) return const [];
  String? hexKey;
  if (!isPlainSqliteFile(path)) {
    hexKey = await keySource();
    if (hexKey == null) throw const HistoryKeyUnavailableException();
  }
  final db = openSqlite(path, mode: OpenMode.readOnly, hexKey: hexKey);
  try {
    // A second guard on top of the read-only open, and a short wait instead
    // of an instant "database is locked" while the app writes.
    db.execute('PRAGMA query_only = ON');
    db.execute('PRAGMA busy_timeout = 5000');
    final version = db.select('PRAGMA user_version').single.columnAt(0) as int;
    if (version != historySchemaVersion) {
      throw HeadlessHistoryVersionException(version);
    }
    // Same order as HistoryDatabase.readAllReplacements: placed rows by
    // position, the rest in creation order, triggers by id.
    final rows = db.select('''
      SELECT r.id, r.replacement, r.match_mode, r.fuzzy_threshold, t.trigger
      FROM text_replacements r
      LEFT JOIN text_replacement_triggers t ON t.replacement_id = r.id
      ORDER BY r.sort_position IS NULL, r.sort_position, r.rowid, t.id
    ''');
    final order = <String>[];
    final byId = <String, Row>{};
    final triggers = <String, List<String>>{};
    for (final row in rows) {
      final id = row['id'] as String;
      if (byId[id] == null) {
        order.add(id);
        byId[id] = row;
        triggers[id] = [];
      }
      if (row['trigger'] case final String trigger) triggers[id]!.add(trigger);
    }
    return [
      for (final id in order)
        TextReplacementRule(
          triggers: triggers[id]!,
          replacement: byId[id]!['replacement'] as String,
          matchMode: byId[id]!['match_mode'] == 'fuzzy'
              ? TextReplacementMatchMode.fuzzy
              : TextReplacementMatchMode.exact,
          fuzzyThreshold: (byId[id]!['fuzzy_threshold'] as num?)?.toDouble(),
        ),
    ];
  } finally {
    db.close();
  }
}
