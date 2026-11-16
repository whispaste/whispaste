// A launch whose single-instance check could not run keeps the history
// closed behind a start screen until the user answers (#1647).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/database_startup_gate.dart';
import 'package:whispaste/core/data/instance_write_gate.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/startup/instance_check_unavailable_screen.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  tearDown(InstanceWriteGate.open);

  test('the history database does not open, nor create a file, while the '
      'gate is closed', () async {
    final dir = Directory.systemTemp.createTempSync('wp_instance_gate_');
    addTearDown(() => dir.deleteSync(recursive: true));
    paths.appDataDirOverride = dir.path;
    addTearDown(() => paths.appDataDirOverride = null);
    InstanceWriteGate.close();

    // Never opened, so there is nothing to close afterwards.
    final db = HistoryDatabase();

    await expectLater(
      db.customSelect('SELECT 1').get(),
      throwsA(isA<InstanceCheckUnavailableException>()),
    );
    expect(dir.listSync(), isEmpty);
  });

  testWidgets('the start screen replaces the shell; "Open anyway" confirms '
      'and opens the database', (tester) async {
    InstanceWriteGate.close();
    var opened = 0;
    var confirmations = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historyDatabaseProvider.overrideWith((ref) {
            opened++;
            final db = HistoryDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          // Mirrors the real opener: refuses while the gate is closed.
          databaseStartupProbeProvider.overrideWith((ref) async {
            ref.watch(historyDatabaseProvider);
            InstanceWriteGate.ensureOpen();
          }),
          confirmUnverifiedStartProvider.overrideWithValue(() async {
            confirmations++;
            InstanceWriteGate.open();
            return true;
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
      find.byKey(const ValueKey('instance-check-unavailable-screen')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('instance-check-quit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('instance-check-open')));
    await tester.pumpAndSettle();

    expect(confirmations, 1);
    expect(opened, 2);
    expect(find.text('app-shell'), findsOneWidget);
  });
}
