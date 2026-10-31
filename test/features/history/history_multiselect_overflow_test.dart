/// UIA-HIS-18: the multi-select bar keeps Delete and Cancel on the bar at any
/// width and moves the secondary batch actions into an overflow menu, so
/// nothing sits behind a horizontal scroll.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';

import '../../fixtures/test_helpers.dart';

HistoryMultiSelectBar _bar({
  required bool trash,
  VoidCallback? onExport,
  VoidCallback? onDelete,
  VoidCallback? onCancelSelection,
}) => HistoryMultiSelectBar(
  selectedCount: 3,
  totalCount: 10,
  isTrashView: trash,
  isArchiveView: false,
  onCancelSelection: onCancelSelection ?? () {},
  onSelectAll: () {},
  onMerge: () {},
  onBatchCopy: () {},
  onBatchCopyMarkdown: () {},
  onExport: onExport ?? () {},
  onArchive: trash ? null : () {},
  onRestore: trash ? () {} : null,
  onDelete: onDelete ?? () {},
);

void _useView(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 700);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  testWidgets('a menu item runs its action and closes the menu', (
    tester,
  ) async {
    _useView(tester, 800);
    var exported = 0;
    await tester.pumpWidget(
      makeTestable(
        _bar(trash: false, onExport: () => exported++),
        size: const Size(800, 700),
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-multiselect-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('history-multiselect-more-export')),
    );
    await tester.pumpAndSettle();

    expect(exported, 1);
    expect(
      find.byKey(const ValueKey('history-multiselect-more-export')),
      findsNothing,
    );
  });

  testWidgets('Delete and Cancel fire their callbacks from the bar', (
    tester,
  ) async {
    _useView(tester, 800);
    var deleted = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      makeTestable(
        _bar(
          trash: false,
          onDelete: () => deleted++,
          onCancelSelection: () => cancelled++,
        ),
        size: const Size(800, 700),
        locale: const Locale('de'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('history-multiselect-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-multiselect-cancel')));
    await tester.pumpAndSettle();

    expect(deleted, 1);
    expect(cancelled, 1);
  });
}
