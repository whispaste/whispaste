import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_view.dart';

import '../../fixtures/test_helpers.dart';

void _noop(SidePanelSection section, String id) {}

String _dayKey(DateTime d) =>
    'side-panel-day-${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The real panel width (see the side panel window).
const _panelWidth = 290.0;

Widget _panel({
  SidePanelSnapshot snapshot = const SidePanelSnapshot(),
  double textScale = 1.0,
  Size size = const Size(1280, 800),
}) {
  return makeTestable(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: WpSidePanelView(
        snapshot: snapshot,
        onRowTap: _noop,
        onClose: () {},
      ),
    ),
    size: size,
  );
}

/// Moves keyboard focus onto the element with [identifier].
void _focus(WidgetTester tester, String identifier) {
  final inkWell = tester.widget<InkWell>(
    find
        .descendant(
          of: find.bySemanticsIdentifier(identifier),
          matching: find.byType(InkWell),
        )
        .first,
  );
  inkWell.focusNode!.requestFocus();
}

void main() {
  group('WpSidePanelView identifiers and semantics', () {
    testWidgets('tabs, list landmark and rows carry stable test ids', (
      tester,
    ) async {
      final today = DateTime.now();
      final createdAt = DateTime(today.year, today.month, today.day, 9);
      await tester.pumpWidget(
        _panel(
          snapshot: SidePanelSnapshot(
            transcriptions: [
              SidePanelRow(id: 't1', title: 'Hello', createdAt: createdAt),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.bySemanticsIdentifier('side-panel-tab-transcriptions'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('side-panel-tab-snippets'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier('side-panel-tab-clipboard-history'),
        findsOneWidget,
      );
      expect(find.bySemanticsIdentifier('side-panel-list'), findsOneWidget);
      expect(find.bySemanticsIdentifier('side-panel-row-t1'), findsOneWidget);
      expect(find.bySemanticsIdentifier(_dayKey(today)), findsOneWidget);
    });

    testWidgets('each tab is one named button node, not icon plus text', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Snippets'), findsOneWidget);
    });

    testWidgets('the close button and search field carry test ids', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();
      expect(find.bySemanticsIdentifier('side-panel-close'), findsOneWidget);
      expect(find.bySemanticsIdentifier('side-panel-search'), findsOneWidget);
    });

    testWidgets('a row names its section before its title', (tester) async {
      await tester.pumpWidget(
        _panel(
          snapshot: const SidePanelSnapshot(
            transcriptions: [SidePanelRow(id: 't1', title: 'Hello')],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'^\S.*, Hello$')), findsOneWidget);
    });
  });

  group('WpSidePanelView sizing', () {
    testWidgets('tabs are at least 48 px tall', (tester) async {
      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();
      final size = tester.getSize(
        find.bySemanticsIdentifier('side-panel-tab-snippets'),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        await tester.pumpWidget(
          _panel(
            textScale: scale,
            snapshot: const SidePanelSnapshot(
              transcriptions: [SidePanelRow(id: 't1', title: 'Hello')],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in [1.3, 2.0]) {
      testWidgets('no overflow at $scale in the real 290 px panel', (
        tester,
      ) async {
        await tester.pumpWidget(
          _panel(
            textScale: scale,
            size: const Size(_panelWidth, 800),
            snapshot: const SidePanelSnapshot(
              transcriptions: [
                SidePanelRow(
                  id: 't1',
                  title:
                      'A transcription title that is far too long for one line',
                  subtitle:
                      'and a subtitle that is long as well, to force truncation',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a truncated tab shows its full name on keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _panel(textScale: 2.0, size: const Size(_panelWidth, 800)),
      );
      await tester.pumpAndSettle();
      // Only the tab label shows the name until the tooltip appears.
      expect(find.text('Clipboard history'), findsOneWidget);

      _focus(tester, 'side-panel-tab-clipboard-history');
      await tester.pumpAndSettle();
      expect(find.text('Clipboard history'), findsNWidgets(2));
    });

    testWidgets('an untruncated tab shows no tooltip on keyboard focus', (
      tester,
    ) async {
      await tester.pumpWidget(_panel());
      await tester.pumpAndSettle();
      _focus(tester, 'side-panel-tab-snippets');
      await tester.pumpAndSettle();
      expect(find.text('Snippets'), findsOneWidget);
    });

    testWidgets('a truncated row shows its full title on keyboard focus', (
      tester,
    ) async {
      const title = 'A transcription title that is far too long for one line';
      await tester.pumpWidget(
        _panel(
          size: const Size(_panelWidth, 800),
          snapshot: const SidePanelSnapshot(
            transcriptions: [SidePanelRow(id: 't1', title: title)],
          ),
        ),
      );
      await tester.pumpAndSettle();
      _focus(tester, 'side-panel-row-t1');
      await tester.pumpAndSettle();
      expect(find.text(title), findsNWidgets(2));
    });

    testWidgets('day headers indent on the start side in RTL', (tester) async {
      final today = DateTime.now();
      final createdAt = DateTime(today.year, today.month, today.day, 9);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: _panel(
            snapshot: SidePanelSnapshot(
              transcriptions: [
                SidePanelRow(id: 't1', title: 'Hello', createdAt: createdAt),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final padding = tester.widget<Padding>(
        find.descendant(
          of: find.bySemanticsIdentifier(_dayKey(today)),
          matching: find.byType(Padding),
        ),
      );
      final resolved = padding.padding.resolve(TextDirection.rtl);
      expect(resolved.right, WpSpacing.xxs);
      expect(resolved.left, 0);
    });
  });
}
