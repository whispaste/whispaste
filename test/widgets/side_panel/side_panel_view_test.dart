import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/services/side_panel/side_panel_snapshot.dart';
import 'package:whispaste/widgets/side_panel/side_panel_row_tile.dart';
import 'package:whispaste/widgets/side_panel/side_panel_view.dart';

import '../../fixtures/test_helpers.dart';

const _fullSnapshot = SidePanelSnapshot(
  transcriptions: [SidePanelRow(id: 't1', title: 'Hello world')],
  snippets: [SidePanelRow(id: 's1', title: 'My signature')],
  clipboardHistory: [SidePanelRow(id: 'c1', title: 'Copied text')],
);

void main() {
  group('WpSidePanelView', () {
    testWidgets('shows the transcriptions tab by default', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: _fullSnapshot,
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      // Header spells out the active section; the other two sections'
      // rows are not rendered while their tab is inactive.
      expect(find.text('Transcriptions'), findsOneWidget);
      expect(find.text('Hello world'), findsOneWidget);
      expect(find.text('My signature'), findsNothing);
      expect(find.text('Copied text'), findsNothing);
    });

    testWidgets('switching tabs shows only that section', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: _fullSnapshot,
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.notebookText));
      await tester.pumpAndSettle();
      expect(find.text('Snippets'), findsOneWidget);
      expect(find.text('My signature'), findsOneWidget);
      expect(find.text('Hello world'), findsNothing);
      expect(find.text('Copied text'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.clipboardList).first);
      await tester.pumpAndSettle();
      expect(find.text('Clipboard History'), findsOneWidget);
      expect(find.text('Copied text'), findsOneWidget);
      expect(find.text('My signature'), findsNothing);
    });

    testWidgets('each tab renders its own empty state', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      expect(find.text('No recordings yet'), findsOneWidget);
      expect(find.text('No snippets yet'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.notebookText).first);
      await tester.pumpAndSettle();
      expect(find.text('No snippets yet'), findsOneWidget);
      expect(find.text('No recordings yet'), findsNothing);

      await tester.tap(find.byIcon(LucideIcons.clipboardList).first);
      await tester.pumpAndSettle();
      expect(find.text('Nothing copied yet'), findsOneWidget);
      expect(find.text('No snippets yet'), findsNothing);
    });

    testWidgets('close button reports onClose', (tester) async {
      var closed = false;

      await tester.pumpWidget(
        makeTestable(
          WpSidePanelView(
            snapshot: const SidePanelSnapshot(),
            onRowTap: _noopTap,
            onClose: () => closed = true,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();

      expect(closed, isTrue);
    });

    testWidgets('tapping a row reports its section and id', (tester) async {
      SidePanelSection? tappedSection;
      String? tappedId;

      await tester.pumpWidget(
        makeTestable(
          WpSidePanelView(
            snapshot: const SidePanelSnapshot(
              clipboardHistory: [
                SidePanelRow(id: 'clip-42', title: 'Copied text'),
              ],
            ),
            onRowTap: (section, id) {
              tappedSection = section;
              tappedId = id;
            },
            onClose: _noopClose,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.clipboardList));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copied text'));
      await tester.pump();

      expect(tappedSection, SidePanelSection.clipboardHistory);
      expect(tappedId, 'clip-42');
    });

    testWidgets('dragging a row horizontally past the touch slop reports '
        'drag start, not a tap (issue 11)', (tester) async {
      SidePanelSection? draggedSection;
      SidePanelRow? draggedRow;
      var tapped = false;

      await tester.pumpWidget(
        makeTestable(
          WpSidePanelView(
            snapshot: const SidePanelSnapshot(
              clipboardHistory: [
                SidePanelRow(
                  id: 'clip-42',
                  title: 'Copied text',
                  content: 'Copied text in full',
                ),
              ],
            ),
            onRowTap: (_, _) => tapped = true,
            onRowDragStart: (section, row) {
              draggedSection = section;
              draggedRow = row;
            },
            onClose: _noopClose,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.clipboardList));
      await tester.pumpAndSettle();

      // A real drag-out: press, move predominantly horizontally (as a real
      // drag out of the left-edge panel would), then release -- Flutter's
      // own gesture arena resolves this as a horizontal drag, never a tap,
      // and never competes with the row list's own vertical scroll gesture.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Copied text')),
      );
      await gesture.moveBy(const Offset(40, 4));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(draggedSection, SidePanelSection.clipboardHistory);
      expect(draggedRow?.id, 'clip-42');
      expect(draggedRow?.content, 'Copied text in full');
      expect(tapped, isFalse);
    });

    testWidgets('a plain tap on a row never reports a drag start', (
      tester,
    ) async {
      var dragged = false;
      var tapped = false;

      await tester.pumpWidget(
        makeTestable(
          WpSidePanelView(
            snapshot: const SidePanelSnapshot(
              clipboardHistory: [
                SidePanelRow(id: 'clip-42', title: 'Copied text'),
              ],
            ),
            onRowTap: (_, _) => tapped = true,
            onRowDragStart: (_, _) => dragged = true,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.clipboardList));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copied text'));
      await tester.pump();

      expect(tapped, isTrue);
      expect(dragged, isFalse);
    });

    testWidgets('renders an image row without a text subtitle crash', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              clipboardHistory: [
                SidePanelRow(
                  id: 'img-1',
                  title: 'Image',
                  kind: SidePanelRowKind.image,
                  imageBytes: [
                    // Minimal 1x1 transparent PNG.
                    137, 80, 78, 71, 13, 10, 26, 10, //
                    0, 0, 0, 13, 73, 72, 68, 82, //
                    0, 0, 0, 1, 0, 0, 0, 1, //
                    8, 6, 0, 0, 0, 31, 21, 196, 137, //
                    0, 0, 0, 10, 73, 68, 65, 84, //
                    120, 156, 99, 96, 0, 0, 0, 2, 0, 1, //
                    229, 39, 222, 252, //
                    0, 0, 0, 0, 73, 69, 78, 68, //
                    174, 66, 96, 130,
                  ],
                ),
              ],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );
      await tester.tap(find.byIcon(LucideIcons.clipboardList));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Image'), findsOneWidget);
    });

    testWidgets('row gap is compact (issue 08)', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              clipboardHistory: [
                SidePanelRow(id: 'c1', title: 'First'),
                SidePanelRow(id: 'c2', title: 'Second'),
              ],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );
      await tester.tap(find.byIcon(LucideIcons.clipboardList));
      await tester.pumpAndSettle();

      final tiles = find.byType(WpSidePanelRowTile);
      expect(tiles, findsNWidgets(2));
      final firstRect = tester.getRect(tiles.at(0));
      final secondRect = tester.getRect(tiles.at(1));
      final gap = secondRect.top - firstRect.bottom;

      // Noticeably tighter than the old WpSpacing.xxs (4px) wrapper gap.
      expect(gap, lessThan(WpSpacing.xxs));
    });

    testWidgets(
      'row tile height matches a standalone render (tap target unchanged)',
      (tester) async {
        const row = SidePanelRow(id: 'c1', title: 'First', subtitle: '09:00');

        await tester.pumpWidget(
          makeTestable(
            const WpSidePanelView(
              snapshot: SidePanelSnapshot(clipboardHistory: [row]),
              onRowTap: _noopTap,
              onClose: _noopClose,
            ),
          ),
        );
        await tester.tap(find.byIcon(LucideIcons.clipboardList));
        await tester.pumpAndSettle();
        final panelHeight = tester
            .getSize(find.byType(WpSidePanelRowTile))
            .height;

        await tester.pumpWidget(
          makeTestable(
            WpSidePanelRowTile(
              row: row,
              leadingIcon: LucideIcons.clipboardList,
              onTap: () {},
            ),
          ),
        );
        final standaloneHeight = tester
            .getSize(find.byType(WpSidePanelRowTile))
            .height;

        expect(panelHeight, standaloneHeight);
      },
    );

    testWidgets('search field is visible below the tab bar in every tab', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: _fullSnapshot,
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.notebookText));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.clipboardList).first);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('typing filters the list live, without pressing enter', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              transcriptions: [
                SidePanelRow(id: 't1', title: 'Meeting notes'),
                SidePanelRow(id: 't2', title: 'Grocery list'),
              ],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'grocery');
      await tester.pump();

      expect(find.text('Grocery list'), findsOneWidget);
      expect(find.text('Meeting notes'), findsNothing);
    });

    testWidgets('search match is case-insensitive', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              transcriptions: [SidePanelRow(id: 't1', title: 'Meeting notes')],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'MEETING');
      await tester.pump();

      expect(find.text('Meeting notes'), findsOneWidget);
    });

    testWidgets('each tab keeps its own independent search query', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: _fullSnapshot,
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.text('Hello world'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.notebookText));
      await tester.pumpAndSettle();
      // Snippets tab's own query is untouched by the transcriptions query.
      expect(find.text('My signature'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );

      await tester.tap(find.byIcon(LucideIcons.mic));
      await tester.pumpAndSettle();
      // Switching back to transcriptions restores its own saved query.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hello',
      );
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('a query with no matches shows a distinct hint', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              transcriptions: [SidePanelRow(id: 't1', title: 'Hello world')],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump();

      expect(find.text('No matches'), findsOneWidget);
      expect(find.text('Try a different search term.'), findsOneWidget);
      // Distinct from the genuinely-empty-section state.
      expect(find.text('No recordings yet'), findsNothing);
    });

    testWidgets('clearing the query restores the full list', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpSidePanelView(
            snapshot: SidePanelSnapshot(
              transcriptions: [
                SidePanelRow(id: 't1', title: 'Meeting notes'),
                SidePanelRow(id: 't2', title: 'Grocery list'),
              ],
            ),
            onRowTap: _noopTap,
            onClose: _noopClose,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'grocery');
      await tester.pump();
      expect(find.text('Meeting notes'), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Meeting notes'), findsOneWidget);
      expect(find.text('Grocery list'), findsOneWidget);
    });
  });
}

void _noopTap(SidePanelSection section, String id) {}

void _noopClose() {}
