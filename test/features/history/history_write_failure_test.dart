// A failed write on the recordings page always reports (#449): at the entry,
// in the dialog, with "copy diagnostics".
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/widgets/wp_page_notice.dart';
import 'package:whispaste/features/history/widgets/history_write_failure.dart';
import 'package:whispaste/features/history/widgets/tag_management_dialog.dart';

import '../../fixtures/test_helpers.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

class _FailingDb extends HistoryDatabase {
  _FailingDb() : super.forTesting(NativeDatabase.memory());

  bool failing = true;

  @override
  Future<int> deleteUnusedTags() async {
    if (failing) throw StateError('disk full');
    return super.deleteUnusedTags();
  }

  @override
  Future<int> updateEntry(String entryId, HistoryEntriesCompanion companion) {
    if (failing) throw StateError('disk full');
    return super.updateEntry(entryId, companion);
  }
}

const _noticeKey = ValueKey('page-notice-write-failed');
const _slots = Key('slots');

Future<ProviderContainer> _pumpSlots(WidgetTester tester) async {
  await tester.pumpWidget(
    makeTestable(
      const Scaffold(
        body: Column(
          key: _slots,
          children: [
            WpPageNoticeSlot(page: 'history', openArea: 'entry-a'),
            WpPageNoticeSlot(page: 'history', area: 'entry-a'),
          ],
        ),
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byKey(_slots)));
}

void main() {
  testWidgets('the storage error keeps "copy diagnostics"', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _pumpSlots(tester);

    showHistoryWriteFailed(tester.element(find.byKey(_slots)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('page-notice-diagnostics')));
    await tester.pumpAndSettle();

    expect(copied, contains('fingerprint: $historyWriteFailed'));
  });

  testWidgets('a failed tag delete reports in the dialog and can be retried', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final db = _FailingDb();
    addTearDown(db.close);
    await db.createTag('unused');
    await tester.pumpWidget(
      makeTestable(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-dialog'),
              onPressed: () =>
                  showTagManagementDialog(context: context, db: db),
              child: const Text('open'),
            ),
          ),
        ),
        db: db,
        locale: const Locale('en'),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    Future<void> deleteUnused() async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('tag-delete-unused')),
      );
      await tester.tap(find.byKey(const ValueKey('tag-delete-unused')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-dialog-confirm')));
      await tester.pumpAndSettle();
    }

    await deleteUnused();
    expect(find.byKey(const ValueKey('tag-delete-failed')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('tag-delete-diagnostics')),
      findsOneWidget,
    );

    db.failing = false;
    await deleteUnused();
    expect(find.byKey(const ValueKey('tag-delete-failed')), findsNothing);
  });

  testWidgets('a title that fails to save reports at the entry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final db = _FailingDb();
    addTearDown(db.close);
    await db.insertHistoryEntry(
      HistoryEntriesCompanion.insert(
        id: 'title-1',
        timestamp: DateTime(2026, 1, 1, 12),
        content: const Value('text'),
        title: const Value('Old title'),
      ),
    );
    final entry = (await db.select(db.historyEntries).get()).single;
    await tester.pumpWidget(
      makeTestable(
        Scaffold(
          body: HistoryDetailPanel(
            entry: entry,
            isTrashView: false,
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
        overrides: [
          settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
        ],
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Old title'));
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'New title');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(_noticeKey), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
