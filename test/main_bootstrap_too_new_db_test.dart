import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/database_startup_gate.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/main.dart' hide main;

import 'test_helpers/temp_dir_cleanup.dart';

/// Start flow against a database written by a newer build: the container must
/// come up (no endless wait for settings) and the gate must show the notice.
void main() {
  testWidgets('start against a too-new database ends in the notice screen', (
    tester,
  ) async {
    // Real file I/O never completes inside the fake-async test zone.
    final (file, before) = await tester
        .runAsync(() async {
          final dir = await Directory.systemTemp.createTemp('whispaste-boot-');
          final file = File(p.join(dir.path, 'history.db'));
          final probe = HistoryDatabase.forTesting(NativeDatabase.memory());
          final supported = probe.schemaVersion;
          await probe.close();
          final raw = sqlite.sqlite3.open(file.path);
          raw.execute('CREATE TABLE marker (value TEXT)');
          raw.execute('PRAGMA user_version = ${supported + 1}');
          raw.close();
          return (file, await file.readAsBytes());
        })
        .then((v) => v!);
    // The container closes the database without waiting; on Windows the file
    // is still open when this runs (lab run 2845), so a locked leftover stays.
    addTearDown(() => deleteTempDir(file.parent));

    final container = await tester.runAsync(
      () => bootstrapAppContainer(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            final db = HistoryDatabase.forTesting(NativeDatabase(file));
            ref.onDispose(db.close);
            return db;
          }),
        ],
      ),
    );
    addTearDown(container!.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DatabaseStartupGate(child: Text('app-shell')),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsNothing);
    expect(
      find.byKey(const ValueKey('database-too-new-screen')),
      findsOneWidget,
    );
    expect(await tester.runAsync(file.readAsBytes), before);
  });
}
