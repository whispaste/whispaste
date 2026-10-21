/// UIA-HIS-18: the multi-select bar keeps Delete and Cancel on the bar at any
/// width and moves the secondary batch actions into an overflow menu, so
/// nothing sits behind a horizontal scroll.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';

import '../../fixtures/test_helpers.dart';

Widget _scaled(double scale, Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child,
  ),
);

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
  for (final locale in const [Locale('de'), Locale('he')]) {
    for (final width in const [800.0, 1100.0]) {
      for (final scale in const [1.0, 2.0]) {
        for (final trash in const [false, true]) {
          final name =
              '${locale.languageCode} ${width.toInt()}px '
              'text ${scale}x ${trash ? 'trash' : 'active'}';
          testWidgets('keeps Delete and Cancel hit-testable: $name', (
            tester,
          ) async {
            _useView(tester, width);
            final l10n = await L10n.delegate.load(locale);
            await tester.pumpWidget(
              makeTestable(
                _scaled(scale, _bar(trash: trash)),
                size: Size(width, 700),
                locale: locale,
              ),
            );
            await tester.pumpAndSettle();

            expect(
              find.byKey(const ValueKey('history-multiselect-delete')),
              findsOneWidget,
            );
            expect(
              find
                  .byKey(const ValueKey('history-multiselect-delete'))
                  .hitTestable(),
              findsOneWidget,
            );
            expect(
              find
                  .text(trash ? l10n.historyDeleteForever : l10n.actionDelete)
                  .hitTestable(),
              findsOneWidget,
            );
            expect(
              find
                  .byKey(const ValueKey('history-multiselect-cancel'))
                  .hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          });

          testWidgets('reaches every other action via the menu: $name', (
            tester,
          ) async {
            _useView(tester, width);
            await tester.pumpWidget(
              makeTestable(
                _scaled(scale, _bar(trash: trash)),
                size: Size(width, 700),
                locale: locale,
              ),
            );
            await tester.pumpAndSettle();

            await tester.tap(
              find.byKey(const ValueKey('history-multiselect-more')),
            );
            await tester.pumpAndSettle();

            final ids = [
              'merge',
              'copy',
              'markdown',
              'export',
              trash ? 'restore' : 'archive',
            ];
            for (final id in ids) {
              expect(
                find.byKey(ValueKey('history-multiselect-more-$id')),
                findsOneWidget,
                reason: 'menu item $id',
              );
            }
            // Delete and Cancel are never duplicated into the menu.
            expect(
              find.byKey(const ValueKey('history-multiselect-more-delete')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }

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
