// #634/#1498: the transcript is written directly in the surface and saves
// itself after a short pause, on leaving the field, with Cmd/Ctrl+S and before
// another entry opens; the text survives a crash. One editing session is one
// version, the original stays. The pause runs on the test clock.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/text_writer/text_writer.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

const _content = 'original transcript text';

/// A database whose entry writes can be made to fail, or held back until the
/// test releases them, as a full disk or a slow disk would.
class _FlakyDatabase extends HistoryDatabase {
  _FlakyDatabase() : super.forTesting(NativeDatabase.memory());

  bool failWrites = false;
  int contentWrites = 0;
  Completer<void>? hold;

  @override
  Future<int> updateEntry(
    String entryId,
    HistoryEntriesCompanion companion,
  ) async {
    if (companion.content.present) contentWrites++;
    final gate = hold;
    if (gate != null) await gate.future;
    if (failWrites) throw StateError('disk full');
    return super.updateEntry(entryId, companion);
  }
}

Finder _editor() => find.byWidgetPredicate(
  (w) => w is TextField && (w.controller?.text ?? '').startsWith(_content),
);

Future<(_FlakyDatabase, HistoryEntry)> _seed() async {
  final db = _FlakyDatabase();
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: 'edit-1',
      timestamp: DateTime(2026, 1, 1, 12),
      content: const Value(_content),
      title: const Value('Edit me'),
    ),
  );
  final entry = (await db.select(db.historyEntries).get()).single;
  return (db, entry);
}

Future<void> _pump(
  WidgetTester tester,
  HistoryDatabase db,
  HistoryEntry entry, {
  bool trash = false,
}) async {
  tester.view.physicalSize = const Size(1600, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    makeTestable(
      Scaffold(
        body: HistoryDetailPanel(
          entry: entry,
          isTrashView: trash,
          onClose: () {},
          onCopy: () {},
          onPin: () {},
          onDelete: () {},
          onArchive: () {},
          onRestore: () {},
        ),
      ),
      db: db,
      locale: const Locale('en'),
      overrides: [settingsProvider.overrideWith(() => _FakeSettingsNotifier())],
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _primaryS(WidgetTester tester) async {
  await tester.sendKeyDownEvent(primaryShortcutModifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
  await tester.sendKeyUpEvent(primaryShortcutModifier);
  await tester.pumpAndSettle();
}

/// Lets toasts and timers finish, then tears the tree down. The shared
/// writer drops what a failing disk left pending (its retry timer).
Future<void> _end(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  TextWriter.shared.resetForTest();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<HistoryEntry> _stored(HistoryDatabase db) async =>
    (await db.select(db.historyEntries).get()).single;

/// Opens the panel; the transcript is written directly, so there is no mode
/// to switch on.
Future<void> _open(
  WidgetTester tester,
  HistoryDatabase db,
  HistoryEntry e,
) async {
  await _pump(tester, db, e);
  expect(_editor(), findsOneWidget);
}

void main() {
  Finder status() => find.bySemanticsIdentifier('history-editor-save-status');
  // The state sits in the key of the status node, never in its wording.
  Finder statusIs(String state) =>
      find.byKey(ValueKey('history-editor-save-status-$state'));

  testWidgets('the text is saved after a short pause, not before', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, more');
    await tester.pump(const Duration(milliseconds: 1500));
    expect((await _stored(db)).content, _content);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect((await _stored(db)).content, '$_content, more');
    expect(statusIs('saved'), findsOneWidget);
    expect(status(), findsOneWidget);
    expect(_editor(), findsOneWidget);
    await _end(tester);
  });

  testWidgets('after a crash the last text is there at the next start', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, typed before the crash');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final restarted = await _stored(db);
    expect(restarted.content, '$_content, typed before the crash');
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester, db, restarted);
    expect(find.textContaining('typed before the crash'), findsWidgets);
    await _end(tester);
  });

  testWidgets('leaving the field saves at once', (tester) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, left the field');
    await tester.pump(const Duration(milliseconds: 50));
    expect((await _stored(db)).content, _content);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    expect((await _stored(db)).content, '$_content, left the field');
    await _end(tester);
  });

  testWidgets('closing the panel saves the pending text', (tester) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, closed early');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();

    expect((await _stored(db)).content, '$_content, closed early');
    await tester.pump(const Duration(seconds: 10));
    TextWriter.shared.resetForTest();
  });

  testWidgets('Cmd/Ctrl+S saves at once and the editor stays', (tester) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, one two');
    await _primaryS(tester);

    expect((await _stored(db)).content, '$_content, one two');
    expect(_editor(), findsOneWidget);
    expect(statusIs('saved'), findsOneWidget);
    await _end(tester);
  });

  testWidgets('a failed save shows the status and keeps the text', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    db.failWrites = true;
    await tester.enterText(_editor(), '$_content, cannot be written');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(statusIs('failed'), findsOneWidget);
    expect(
      tester.widget<TextField>(_editor()).controller!.text,
      '$_content, cannot be written',
    );
    await _end(tester);
  });

  testWidgets('a failed save recovers to saved with the next good write', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    db.failWrites = true;
    await tester.enterText(_editor(), '$_content, first try');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(statusIs('failed'), findsOneWidget);

    db.failWrites = false;
    await tester.enterText(_editor(), '$_content, second try');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(statusIs('saved'), findsOneWidget);
    expect((await _stored(db)).content, '$_content, second try');
    await _end(tester);
  });

  testWidgets('Cmd/Ctrl+S that fails keeps the failed status, the next works', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    db.failWrites = true;
    await tester.enterText(_editor(), '$_content, save refused');
    await _primaryS(tester);
    expect(statusIs('failed'), findsOneWidget);
    expect((await _stored(db)).content, _content);

    db.failWrites = false;
    await _primaryS(tester);
    expect((await _stored(db)).content, '$_content, save refused');
    await _end(tester);
  });

  testWidgets('Cmd/Ctrl+S twice writes once', (tester) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, once');
    db.contentWrites = 0;
    await _primaryS(tester);
    await _primaryS(tester);

    expect(db.contentWrites, 1);
    expect((await _stored(db)).content, '$_content, once');
    await _end(tester);
  });

  testWidgets('a failed final write on entry switch is reported, not lost '
      'silently', (tester) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'edit-2',
        timestamp: DateTime(2026, 1, 2, 12),
        content: const Value('second entry text'),
        title: const Value('Other'),
      ),
    );
    final other = (await db.select(db.historyEntries).get()).firstWhere(
      (e) => e.id == 'edit-2',
    );
    await _open(tester, db, entry);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HistoryDetailPanel)),
    );

    db.failWrites = true;
    await tester.enterText(_editor(), '$_content, lost?');
    await tester.pump(const Duration(milliseconds: 50));
    await _pump(tester, db, other);
    await tester.pump();
    await tester.pump();

    final notice = container.read(wpPageNoticeProvider(WpNoticePage.history));
    expect(notice?.id, 'write-failed');
    await _end(tester);
  });

  testWidgets('unsaved text never lands in the entry opened next', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'edit-2',
        timestamp: DateTime(2026, 1, 2, 12),
        content: const Value('second entry text'),
        title: const Value('Other'),
      ),
    );
    final other = (await db.select(db.historyEntries).get()).firstWhere(
      (e) => e.id == 'edit-2',
    );
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, typed in the first');
    await tester.pump(const Duration(milliseconds: 50));
    await _pump(tester, db, other);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    final rows = await db.select(db.historyEntries).get();
    expect(
      rows.firstWhere((e) => e.id == 'edit-1').content,
      '$_content, typed in the first',
    );
    expect(
      rows.firstWhere((e) => e.id == 'edit-2').content,
      'second entry text',
    );
    await _end(tester);
  });

  // #1498: one editing session = one version; the original stays.
  testWidgets('one session writes one version and the original stays', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, a');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.enterText(_editor(), '$_content, a b');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.enterText(_editor(), '$_content, a b c');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final versions = await db.entryVersionsFor('edit-1');
    expect(versions.map((v) => v.content), [
      '$_content, a b c',
      _content,
    ], reason: 'the session version, then the original');
    await _end(tester);
  });

  testWidgets('a new session after leaving the field is a new version', (
    tester,
  ) async {
    final (db, entry) = await _seed();
    addTearDown(db.close);
    await _open(tester, db, entry);

    await tester.enterText(_editor(), '$_content, first session');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    // The live entry stream hands the panel the stored row.
    await _pump(tester, db, await _stored(db));

    await tester.enterText(_editor(), '$_content, second session');
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    final versions = await db.entryVersionsFor('edit-1');
    expect(versions.map((v) => v.content), [
      '$_content, second session',
      '$_content, first session',
      _content,
    ]);
    await _end(tester);
  });
}
