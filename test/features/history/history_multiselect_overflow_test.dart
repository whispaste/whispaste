/// UIA-HIS-18: the multi-select bar keeps Delete and Cancel on the bar at any
/// width and moves the secondary batch actions into an overflow menu, so
/// nothing sits behind a horizontal scroll. #1388: at large text, whatever
/// does not fit whole moves into that menu instead of wrapping mid-word.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/history/widgets/history_search_filter_bar.dart';

import '../../fixtures/test_helpers.dart';

WpMultiSelectBar _bar({
  required bool trash,
  VoidCallback? onExport,
  VoidCallback? onDelete,
  VoidCallback? onCancelSelection,
  VoidCallback? onSelectAll,
  String idPrefix = 'history-multiselect',
}) => WpMultiSelectBar(
  idPrefix: idPrefix,
  selectedCount: 3,
  totalCount: 10,
  isTrashView: trash,
  isArchiveView: false,
  onCancelSelection: onCancelSelection ?? () {},
  onSelectAll: onSelectAll ?? () {},
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

  test('fitMultiSelectBar moves Select All first, then Delete, then '
      'shortens the count', () {
    WpMultiSelectBarFit fit(double available, {double count = 100}) =>
        fitMultiSelectBar(
          available: available,
          count: count,
          countShort: 30,
          selectAll: 80,
          delete: 90,
          cancel: 70,
          more: 48,
          hasSecondary: false,
        );
    const all = WpMultiSelectBarFit(
      countFull: true,
      selectAllOnBar: true,
      deleteOnBar: true,
    );
    // Everything on the bar needs no menu button: 100 + 80 + 90 + 70.
    expect(fit(340), all);
    // One pixel short: Select All goes, and the menu button appears.
    expect(
      fit(339),
      const WpMultiSelectBarFit(
        countFull: true,
        selectAllOnBar: false,
        deleteOnBar: true,
      ),
    );
    // 100 + 48 + 70 = 218: only count, menu and Cancel.
    expect(
      fit(218),
      const WpMultiSelectBarFit(
        countFull: true,
        selectAllOnBar: false,
        deleteOnBar: false,
      ),
    );
    // A long count phrase (300 + 48 + 70) does not fit; the bare number
    // still leaves room for Delete: 30 + 90 + 48 + 70 = 238.
    expect(
      fit(250, count: 300),
      const WpMultiSelectBarFit(
        countFull: false,
        selectAllOnBar: false,
        deleteOnBar: true,
      ),
    );
    // A page without Select All and Delete never needs the menu button.
    expect(
      fitMultiSelectBar(
        available: 170,
        count: 100,
        countShort: 30,
        selectAll: null,
        delete: null,
        cancel: 70,
        more: 48,
        hasSecondary: false,
      ),
      const WpMultiSelectBarFit(
        countFull: true,
        selectAllOnBar: false,
        deleteOnBar: false,
      ),
    );
  });

  // 800 px window at 200 % text; the bar itself is narrower than the window
  // once the sidebar takes its share, so both widths are checked.
  for (final locale in const [Locale('de'), Locale('he')]) {
    for (final barWidth in const [800.0, 520.0]) {
      testWidgets('200 % text, ${locale.languageCode}, ${barWidth.toInt()} px: '
          'every bar label is whole and every action reachable by its ID', (
        tester,
      ) async {
        _useView(tester, 800);
        var deleted = 0;
        var selectedAll = 0;
        const prefix = 'notes-multiselect';
        await tester.pumpWidget(
          makeTestable(
            Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: barWidth,
                    child: _bar(
                      trash: false,
                      idPrefix: prefix,
                      onDelete: () => deleted++,
                      onSelectAll: () => selectedAll++,
                    ),
                  ),
                ),
              ),
            ),
            size: const Size(800, 700),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final bar = find.byType(WpMultiSelectBar);
        for (final paragraph in tester.renderObjectList<RenderParagraph>(
          find.descendant(of: bar, matching: find.byType(RichText)),
        )) {
          final text = paragraph.text.toPlainText();
          expect(paragraph.didExceedMaxLines, isFalse, reason: text);
          expect(
            paragraph.size.width,
            greaterThanOrEqualTo(
              paragraph.getMaxIntrinsicWidth(double.infinity) - 0.5,
            ),
            reason: '"$text" is cut or wrapped',
          );
        }

        Future<void> tapById(String id) async {
          final onBar = find.byKey(ValueKey(id));
          if (onBar.evaluate().isEmpty) {
            await tester.tap(find.byKey(const ValueKey('$prefix-more')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(ValueKey(id)));
          await tester.pumpAndSettle();
        }

        await tapById('$prefix-select-all');
        await tapById('$prefix-delete');
        expect(selectedAll, 1);
        expect(deleted, 1);
        expect(find.byKey(const ValueKey('$prefix-cancel')), findsOneWidget);
      });
    }
  }
}
