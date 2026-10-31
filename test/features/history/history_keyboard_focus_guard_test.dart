// Keyboard and focus guard for the recordings list (UIA-R-HIS-009, -021, -041,
// -087): command chips can be removed from the keyboard, row actions are
// reachable by Tab and show a focus ring, and the detail view closes with Esc
// and with its close button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/data/history_providers.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/features/history/widgets/history_detail_panel.dart';
import 'package:whispaste/features/history/widgets/history_list_tile.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';
import 'package:whispaste/widgets/wp_row_action.dart';

import '../../fixtures/test_helpers.dart';

HistoryEntry _entry() => HistoryEntry(
  id: 'row-1',
  content: 'Keyboard content',
  title: 'Keyboard title',
  timestamp: DateTime(2026, 4, 14),
  durationSec: 10.0,
  processingDurationSec: 0.5,
  language: 'en',
  languageHint: '',
  tags: '[]',
  pinned: false,
  source: 'microphone',
  model: 'whisper-small',
  isLocal: true,
  costUsd: 0.0,
  archived: false,
  deletedAt: null,
  titleEdited: false,
  colorSlot: 0,
);

Widget _row({required bool isFocused}) => makeTestable(
  Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 600,
      child: HistoryEntryRow(
        entry: _entry(),
        isSelected: false,
        isFocused: isFocused,
        onTap: () {},
        onCopy: () {},
        onPin: () {},
        onDelete: () {},
        onDuplicate: () {},
      ),
    ),
  ),
  locale: const Locale('en'),
);

/// Presses Tab until [matches] holds for the focused element, or fails.
Future<void> _tabUntil(
  WidgetTester tester,
  bool Function(BuildContext context) matches, {
  int max = 30,
}) async {
  for (var i = 0; i < max; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final context = FocusManager.instance.primaryFocus?.context;
    if (context != null && matches(context)) return;
  }
  fail('Tab never reached the expected control within $max presses');
}

bool _onRowAction(BuildContext context, String tooltip) =>
    context.findAncestorWidgetOfExactType<WpRowAction>()?.tooltip == tooltip;

final _ringPainter = find.byWidgetPredicate(
  (w) => w is CustomPaint && w.foregroundPainter is WpFocusRingPainter,
);

Future<void> _openDetail(
  WidgetTester tester,
  List<HistoryEntry> entries,
) async {
  await tester.pumpWidget(
    makeTestable(
      const HistoryPage(),
      overrides: [
        historyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
        archivedEntriesProvider.overrideWith((ref) => Stream.value(const [])),
        trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(entries.first.title).first);
  await tester.pumpAndSettle();
}

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional,
  );
  tearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );

  group('command chips (UIA-R-HIS-009)', () {
    testWidgets('a command chip is reached by Tab and removed with Enter', (
      tester,
    ) async {
      final entries = generateSampleEntries()
          .where((e) => e.deletedAt == null && !e.archived)
          .toList();
      await tester.pumpWidget(
        makeTestable(
          const HistoryPage(),
          overrides: [
            historyEntriesProvider.overrideWith((ref) => Stream.value(entries)),
            archivedEntriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            trashEntriesProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'lang:de');
      await tester.pumpAndSettle();
      // The search field's own text also matches find.text, so count the
      // chip's label only.
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'lang:de'),
        findsWidgets,
      );

      await _tabUntil(
        tester,
        (context) =>
            context
                .findAncestorWidgetOfExactType<Semantics>()
                ?.properties
                .label ==
            l10n.historyRemoveFilter,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('lang:de'), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        isNot(contains('lang:de')),
      );
    });
  });

  group('row actions by keyboard (UIA-R-HIS-021, UIA-R-HIS-087)', () {
    testWidgets('Tab from a row that is not the list cursor reaches its copy '
        'action (UIA-R-HIS-021)', (tester) async {
      await tester.pumpWidget(_row(isFocused: false));
      await tester.pumpAndSettle();

      await _tabUntil(
        tester,
        (context) => _onRowAction(context, l10n.historyCopyText),
        max: 10,
      );
    });

    testWidgets(
      'the focused detail action shows a focus ring (UIA-R-HIS-087)',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            Center(
              child: HistoryDetailAction(
                icon: LucideIcons.copy,
                tooltip: 'Copy',
                onTap: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        final action = find.byType(HistoryDetailAction);
        expect(
          find.descendant(of: action, matching: _ringPainter),
          findsOneWidget,
        );
      },
    );
  });

  group('detail view (UIA-R-HIS-041)', () {
    testWidgets('Esc closes the open detail view', (tester) async {
      final entries = generateSampleEntries()
          .where((e) => e.deletedAt == null && !e.archived)
          .toList();
      await _openDetail(tester, entries);
      expect(find.byType(HistoryDetailPanel), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(HistoryDetailPanel), findsNothing);
    });

    testWidgets('the close button closes the detail view and focus leaves it', (
      tester,
    ) async {
      final entries = generateSampleEntries()
          .where((e) => e.deletedAt == null && !e.archived)
          .toList();
      await _openDetail(tester, entries);

      await tester.tap(find.byTooltip('${l10n.historyClose} (Esc)'));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryDetailPanel), findsNothing);
      final focused = FocusManager.instance.primaryFocus?.context;
      expect(
        focused?.findAncestorWidgetOfExactType<HistoryDetailPanel>(),
        isNull,
      );
    });
  });
}
