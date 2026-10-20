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

/// Writes a history file whose user_version is one step newer than this build.
File _seedTooNewDatabase(Directory dir) {
  final file = File(p.join(dir.path, 'history.db'));
  final raw = sqlite.sqlite3.open(file.path);
  raw.execute('CREATE TABLE marker (value TEXT)');
  raw.execute("INSERT INTO marker VALUES ('keep me')");
  // This build supports schema 31; 32 stands for a file from a newer release.
  raw.execute('PRAGMA user_version = 32');
  raw.close();
  return file;
}

Widget _gateApp(Future<void> Function() probe, {Widget? child}) {
  return ProviderScope(
    overrides: [databaseStartupProbeProvider.overrideWith((ref) => probe())],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: DatabaseStartupGate(child: child ?? const Text('app-shell')),
    ),
  );
}

void main() {
  test(
    'a file from a newer build is refused and its bytes stay unchanged',
    () async {
      final dir = await Directory.systemTemp.createTemp('whispaste-too-new-');
      addTearDown(() => dir.delete(recursive: true));
      final file = _seedTooNewDatabase(dir);
      final before = await file.readAsBytes();

      final db = HistoryDatabase.forTesting(NativeDatabase(file));
      addTearDown(db.close);

      await expectLater(
        db.customSelect('SELECT 1').get(),
        throwsA(isA<DatabaseTooNewException>()),
      );
      expect(await file.readAsBytes(), before);
    },
  );

  testWidgets(
    'a too-new database shows the start screen instead of the shell',
    (tester) async {
      await tester.pumpWidget(
        _gateApp(
          () => Future<void>.error(
            const DatabaseTooNewException(
              storedVersion: 32,
              supportedVersion: 31,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('app-shell'), findsNothing);
      expect(
        find.byKey(const ValueKey('database-too-new-screen')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('database-too-new-quit')),
        findsOneWidget,
      );
      expect(find.textContaining('32'), findsWidgets);
      expect(find.textContaining('31'), findsWidgets);
    },
  );

  testWidgets('a healthy database shows the shell', (tester) async {
    await tester.pumpWidget(_gateApp(() async {}));
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsOneWidget);
    expect(find.byKey(const ValueKey('database-too-new-screen')), findsNothing);
  });

  testWidgets('other probe errors keep today\'s behaviour and show the shell', (
    tester,
  ) async {
    await tester.pumpWidget(
      _gateApp(() => Future<void>.error(StateError('x'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsOneWidget);
  });
}
