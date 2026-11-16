import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:whispaste/core/config/data_key_access.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/database_startup_gate.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

/// The schema version this build supports, read from the database class so
/// the fixture follows every schema bump.
Future<int> _supportedSchemaVersion() async {
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  final version = db.schemaVersion;
  await db.close();
  return version;
}

/// Writes a history file whose user_version is one step newer than this build.
Future<File> _seedTooNewDatabase(Directory dir) async {
  final file = File(p.join(dir.path, 'history.db'));
  final raw = sqlite.sqlite3.open(file.path);
  raw.execute('CREATE TABLE marker (value TEXT)');
  raw.execute("INSERT INTO marker VALUES ('keep me')");
  // One step above this build's schema stands for a file from a newer release.
  raw.execute('PRAGMA user_version = ${(await _supportedSchemaVersion()) + 1}');
  raw.close();
  return file;
}

/// Stands in for the key store: [build] says what the marker records,
/// [request] what the system answers after the tap.
class _FakeDataKeyAccess extends DataKeyAccessNotifier {
  _FakeDataKeyAccess(this.recorded, this.answer);

  final DataKeyAccessStatus recorded;
  final DataKeyAccessStatus Function() answer;
  int requests = 0;

  @override
  DataKeyAccessStatus build() => recorded;

  @override
  Future<DataKeyAccessStatus> request() async {
    requests++;
    return state = answer();
  }
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
      final file = await _seedTooNewDatabase(dir);
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
              storedVersion: 34,
              supportedVersion: 33,
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
      expect(find.textContaining('34'), findsWidgets);
      expect(find.textContaining('33'), findsWidgets);
    },
  );

  testWidgets('an interrupted upgrade offers a retry that opens a fresh '
      'database', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            opened++;
            final db = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          databaseStartupProbeProvider.overrideWith((ref) async {
            ref.watch(historyDatabaseProvider);
            if (opened == 1) {
              throw DatabaseUpgradeInterruptedException(
                sqlite.SqliteException(
                  extendedResultCode: 5,
                  message: 'database is locked',
                ),
              );
            }
          }),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DatabaseStartupGate(child: Text('app-shell')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsNothing);
    expect(
      find.byKey(const ValueKey('database-upgrade-interrupted-screen')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('database-upgrade-retry')));
    await tester.pumpAndSettle();

    expect(opened, 2);
    expect(find.text('app-shell'), findsOneWidget);
  });

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

  testWidgets('a data key that needs consent shows its explanation, never '
      'the shell, and reopens the database once access is allowed', (
    tester,
  ) async {
    var opened = 0;
    var granted = false;
    var answers = 0;
    final access = _FakeDataKeyAccess(DataKeyAccessStatus.ready, () {
      if (++answers == 1) return DataKeyAccessStatus.declined;
      granted = true;
      return DataKeyAccessStatus.ready;
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dataKeyAccessProvider.overrideWith(() => access),
          historyDatabaseProvider.overrideWith((ref) {
            opened++;
            final db = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          databaseStartupProbeProvider.overrideWith((ref) async {
            ref.watch(historyDatabaseProvider);
            if (!granted) throw const HistoryKeyUnavailableException();
          }),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: DatabaseStartupGate(child: Text('app-shell')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('app-shell'), findsNothing);
    expect(
      find.byKey(const ValueKey('data-key-locked-screen')),
      findsOneWidget,
    );

    // Declined: the screen stays, nothing reopens, a retry is offered.
    await tester.tap(find.byKey(const ValueKey('data-key-locked-allow')));
    await tester.pumpAndSettle();
    expect(find.text('app-shell'), findsNothing);
    expect(opened, 1);

    await tester.tap(find.byKey(const ValueKey('data-key-locked-allow')));
    await tester.pumpAndSettle();
    expect(access.requests, 2);
    expect(opened, 2);
    expect(find.text('app-shell'), findsOneWidget);
  });

  testWidgets('without a recorded key the screen never asks the store, so no '
      'new key can be created', (tester) async {
    final access = _FakeDataKeyAccess(
      DataKeyAccessStatus.notRequested,
      () => DataKeyAccessStatus.ready,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dataKeyAccessProvider.overrideWith(() => access)],
        child: _gateApp(
          () => Future<void>.error(const HistoryKeyUnavailableException()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('data-key-locked-screen')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('data-key-locked-allow')), findsNothing);
    expect(find.byKey(const ValueKey('data-key-locked-quit')), findsOneWidget);
    expect(access.requests, 0);
  });
}
