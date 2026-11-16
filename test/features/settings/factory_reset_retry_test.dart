/// A factory reset that leaves data behind opens a dialog with a retry action;
/// the click runs the reset again (#452, #557). The coordinator is built from
/// fakes through the section's test seam.
library;

import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/sections/cloud_advanced_section.dart';
import 'package:whispaste/services/factory_reset/factory_reset_coordinator.dart';

import '../../fixtures/test_helpers.dart';

class _Subprocess implements SubprocessController {
  @override
  Future<void> kill() async {}

  @override
  Future<bool> waitForExit({required Duration timeout}) async => true;

  @override
  Future<void> forceKill() async {}
}

void main() {
  testWidgets('an incomplete reset opens the dialog and its retry button '
      'runs the reset again', (tester) async {
    var runs = 0;
    final fs = MemoryFileSystem();
    FactoryResetCoordinator build() => FactoryResetCoordinator(
      subprocess: _Subprocess(),
      modelDirPath: '/models',
      logsDirPath: '/logs',
      fileSystem: fs,
      directoryDeleter: (_) async {},
      releaseLogFile: (body) => body(),
      captureSink:
          ({required message, required fingerprint, error, stackTrace}) {},
      eraseDatabase: () async {
        runs++;
        // The first attempt leaves the database behind.
        if (runs == 1) throw StateError('database is locked');
      },
      eraseSecureStore: () async {},
      resetSettings: () async {},
    );

    await tester.pumpWidget(
      makeTestable(
        SingleChildScrollView(
          child: AdvancedSection(coordinatorBuilder: (_) => build()),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final trigger = find.byKey(
      const ValueKey('settings-advanced-factory-reset'),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();

    expect(runs, 1);
    expect(
      find.byKey(const ValueKey('settings-factory-reset-failed')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-factory-reset-retry')),
    );
    await tester.pumpAndSettle();

    expect(runs, 2);
    expect(
      find.byKey(const ValueKey('settings-factory-reset-failed')),
      findsNothing,
    );
  });

  testWidgets('closing the dialog does not run the reset again', (
    tester,
  ) async {
    var runs = 0;
    FactoryResetCoordinator build() => FactoryResetCoordinator(
      subprocess: _Subprocess(),
      modelDirPath: '/models',
      logsDirPath: '/logs',
      fileSystem: MemoryFileSystem(),
      directoryDeleter: (_) async {},
      releaseLogFile: (body) => body(),
      captureSink:
          ({required message, required fingerprint, error, stackTrace}) {},
      eraseDatabase: () async {
        runs++;
        throw StateError('database is locked');
      },
      eraseSecureStore: () async {},
      resetSettings: () async {},
    );

    await tester.pumpWidget(
      makeTestable(
        SingleChildScrollView(
          child: AdvancedSection(coordinatorBuilder: (_) => build()),
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();
    final trigger = find.byKey(
      const ValueKey('settings-advanced-factory-reset'),
    );
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-factory-reset-close')),
    );
    await tester.pumpAndSettle();

    expect(runs, 1);
    expect(
      find.byKey(const ValueKey('settings-factory-reset-failed')),
      findsNothing,
    );
  });
}
