import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard tests for the in-app feedback insert path.
///
/// The app inserts feedback as the anon role. The grants are not a property of
/// any single migration: a later REVOKE would silently break every insert. So
/// the grants are replayed in file order and the latest state is checked.
void main() {
  /// Migration SQL in file order, comments stripped, split into statements.
  List<String> statements() {
    final files =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final out = <String>[];
    for (final f in files) {
      final text = f
          .readAsStringSync()
          .split('\n')
          .map((line) {
            final i = line.indexOf('--');
            return i < 0 ? line : line.substring(0, i);
          })
          .join('\n');
      out.addAll(
        text
            .split(';')
            .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
            .where((s) => s.isNotEmpty),
      );
    }
    return out;
  }

  /// Replays the anon privileges on user_feedback for INSERT.
  ({bool tableInsert, Set<String> columns}) anonInsertState() {
    var tableInsert = false;
    final columns = <String>{};
    final revoke = RegExp(
      r'^REVOKE (ALL|INSERT)\b.* ON (public\.)?user_feedback FROM (.*)$',
      caseSensitive: false,
    );
    final grantTable = RegExp(
      r'^GRANT INSERT ON (public\.)?user_feedback TO (.*)$',
      caseSensitive: false,
    );
    final grantColumns = RegExp(
      r'^GRANT INSERT \(([^)]*)\) ON (public\.)?user_feedback TO (.*)$',
      caseSensitive: false,
    );
    final anon = RegExp(r'\banon\b', caseSensitive: false);

    for (final s in statements()) {
      final r = revoke.firstMatch(s);
      if (r != null && anon.hasMatch(r.group(3)!)) {
        tableInsert = false;
        if (r.group(1)!.toUpperCase() == 'ALL') {
          columns.clear();
        }
        continue;
      }
      final gt = grantTable.firstMatch(s);
      if (gt != null && anon.hasMatch(gt.group(2)!)) {
        tableInsert = true;
        continue;
      }
      final gc = grantColumns.firstMatch(s);
      if (gc != null && anon.hasMatch(gc.group(3)!)) {
        columns.addAll(
          gc.group(1)!.split(',').map((c) => c.trim().toLowerCase()),
        );
      }
    }
    return (tableInsert: tableInsert, columns: columns);
  }

  test('the latest migration state lets anon insert into user_feedback', () {
    final state = anonInsertState();
    expect(
      state.tableInsert || state.columns.contains('publish_consent'),
      isTrue,
      reason:
          'After replaying all migrations in order, anon has no INSERT on '
          'user_feedback (a later REVOKE without a re-grant?).',
    );
  });
}
