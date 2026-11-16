/// Guard test for the read-only role the WhisPaste API used to import the
/// remaining Supabase feedback (#695). The role is dropped again by
/// 20261105120000_drop_feedback_import_role.sql (#699); this test still
/// checks its grant history up to that point.
///
/// The role must never see device or IP evidence and must never write. The
/// grants are replayed over all migrations in file order, so a later grant
/// that widens the role fails here. This is the fast text check; the
/// authoritative check is supabase/tests/privileges_assert.sql (now: role
/// and policy are gone), run on a native Postgres 16 by
/// supabase/tests/run_withdraw_cleanup.sh: manual, not part of CI, so run it
/// before applying the migration.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `--` and `/* */` comments in one pass, keeping string literals
/// intact, drops identifier quotes and splits at `;` outside strings.
List<String> splitSql(String sql) {
  final out = <String>[];
  final cur = StringBuffer();
  var i = 0;
  void flush() {
    final s = cur.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isNotEmpty) out.add(s);
    cur.clear();
  }

  while (i < sql.length) {
    final c = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';
    if (c == '-' && next == '-') {
      final end = sql.indexOf('\n', i);
      i = end < 0 ? sql.length : end;
    } else if (c == '/' && next == '*') {
      final end = sql.indexOf('*/', i + 2);
      i = end < 0 ? sql.length : end + 2;
      cur.write(' ');
    } else if (c == "'") {
      // E'...' strings allow backslash escapes; '' is an escaped quote in
      // both forms. An unclosed literal fails loudly instead of hiding the
      // rest of the file.
      final escapes = i > 0 && (sql[i - 1] == 'E' || sql[i - 1] == 'e');
      var j = i + 1;
      while (true) {
        if (j >= sql.length) {
          throw FormatException('unclosed string literal', sql, i);
        }
        if (escapes && sql[j] == r'\') {
          j += 2;
        } else if (sql[j] == "'") {
          if (j + 1 < sql.length && sql[j + 1] == "'") {
            j += 2;
          } else {
            break;
          }
        } else {
          j++;
        }
      }
      cur.write(sql.substring(i, j + 1));
      i = j + 1;
    } else if (c == '"') {
      i++;
    } else if (c == ';') {
      flush();
      i++;
    } else {
      cur.write(c);
      i++;
    }
  }
  flush();
  return out;
}

void main() {
  test('the SQL splitter does not lose a grant after comment markers', () {
    const sql = """
-- glob supabase/* stays a line comment
GRANT SELECT ("id") ON user_feedback TO feedback_import_reader;
/* note; with a semicolon */ SELECT '--;' AS x;
""";
    expect(splitSql(sql), [
      'GRANT SELECT (id) ON user_feedback TO feedback_import_reader',
      "SELECT '--;' AS x",
    ]);
    expect(splitSql(r"SELECT E'\'', 'it''s'; GRANT x TO y;"), [
      r"SELECT E'\'', 'it''s'",
      'GRANT x TO y',
    ]);
    expect(() => splitSql("SELECT 'open"), throwsFormatException);
    // Line breaks collapse, so a GRANT split over lines is matched as one.
    expect(splitSql('GRANT SELECT\n  (id)\n  ON t TO r;'), [
      'GRANT SELECT (id) ON t TO r',
    ]);
  });

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
      out.addAll(splitSql(f.readAsStringSync()));
    }
    return out;
  }

  final role = RegExp(r'\bfeedback_import_reader\b', caseSensitive: false);
  // Grants are searched anywhere in a statement, so one inside a DO body
  // (which the splitter cuts at its inner semicolons) is found as well.
  final grantClause = RegExp(
    r'\bGRANT\s+(.+?)\s+TO\s+([^;]*)',
    caseSensitive: false,
  );
  final grants = [
    for (final s in statements())
      for (final m in grantClause.allMatches(s))
        if (role.hasMatch(m.group(2)!) &&
            !RegExp(r'^ALTER DEFAULT', caseSensitive: false).hasMatch(s))
          'GRANT ${m.group(1)} TO ${m.group(2)}',
  ];

  test('no default privileges are granted to the import role', () {
    expect(
      statements().where(
        (s) =>
            RegExp(
              r'ALTER DEFAULT PRIVILEGES',
              caseSensitive: false,
            ).hasMatch(s) &&
            role.hasMatch(s),
      ),
      isEmpty,
    );
  });
  final toPublic = statements().where(
    (s) => RegExp(
      r'^GRANT .* ON (TABLE )?(public\.)?user_feedback TO .*\bPUBLIC\b',
      caseSensitive: false,
    ).hasMatch(s),
  );

  test('nobody grants user_feedback to PUBLIC', () {
    expect(toPublic, isEmpty);
  });

  test('the import role is granted something at all', () {
    expect(grants, isNotEmpty);
  });

  test('the import role can only read, never write', () {
    for (final g in grants) {
      expect(
        g,
        isNot(
          matches(
            RegExp(
              r'^GRANT\s+(ALL|INSERT|UPDATE|DELETE|TRUNCATE|EXECUTE)\b',
              caseSensitive: false,
            ),
          ),
        ),
        reason: g,
      );
    }
  });

  test('the import role reads user_feedback only column by column, '
      'without device or IP evidence', () {
    final readable = <String>{};
    for (final g in grants) {
      final cols = RegExp(
        r'^GRANT SELECT \(([^)]*)\) ON (public\.)?user_feedback TO',
        caseSensitive: false,
      ).firstMatch(g);
      if (cols != null) {
        readable.addAll(
          cols.group(1)!.split(',').map((c) => c.trim().toLowerCase()),
        );
        continue;
      }
      // Anything else may only be schema usage; a table-wide SELECT would
      // expose every column.
      expect(
        g,
        matches(RegExp(r'^GRANT USAGE ON SCHEMA', caseSensitive: false)),
        reason: g,
      );
    }
    expect(readable, isNotEmpty);
    for (final hidden in ['device_id_hash', 'ip_hash', 'discord_message_id']) {
      expect(readable, isNot(contains(hidden)), reason: hidden);
    }
  });
}
