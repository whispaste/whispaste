import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_view.dart';

import '../../fixtures/test_helpers.dart';

void _noop(SidePanelSection section, String id) {}

String _dayKey(DateTime d) =>
    'side-panel-day-${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

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
}
