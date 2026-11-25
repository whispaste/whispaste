// Contract of the collection page family (#919, `internal-notes`):
// fixed slots, stable landmark ids, the one search shortcut, the compact
// head and the tools overflow. Layout looks are not tested here.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_collection_page.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(800, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context),
        child: Directionality(textDirection: TextDirection.ltr, child: app!),
      ),
      home: Scaffold(body: child),
    ),
  );
}

WpCollectionPage _page({
  required FocusNode focus,
  Widget? selectionBar,
  VoidCallback? onRemoveMark,
}) {
  return WpCollectionPage(
    screenId: 'demo',
    searchFocusNode: focus,
    selectionBar: selectionBar,
    notices: const [Text('notice', key: ValueKey('notice'))],
    toolbar: WpCollectionToolbar(
      screenId: 'demo',
      search: TextField(focusNode: focus),
      primaryAction: const SizedBox(
        key: ValueKey('new'),
        width: 40,
        height: 40,
      ),
      filterSections: [
        for (final id in ['view', 'period'])
          WpFilterSection(
            id: id,
            label: 'Group $id',
            children: [for (var i = 0; i < 4; i++) Text('Choice $id $i')],
          ),
      ],
      activeFilters: [
        WpActiveFilter(
          id: 'trash',
          label: 'Trash',
          onRemove: onRemoveMark ?? () {},
        ),
        WpActiveFilter(id: 'period', label: 'Last 7 days', onRemove: () {}),
      ],
      status: const [Text('12 results')],
      tools: const [
        SizedBox(key: ValueKey('tool-select'), width: 28, height: 28),
        SizedBox(key: ValueKey('tool-sort'), width: 28, height: 28),
        SizedBox(key: ValueKey('tool-view'), width: 28, height: 28),
      ],
      toolsOverflow: const SizedBox(
        key: ValueKey('tools-more'),
        width: 48,
        height: 48,
      ),
      searchExtras: const [Text('suggestions')],
    ),
    body: const ColoredBox(color: Color(0x00000000)),
  );
}

void main() {
  late FocusNode focus;
  setUp(() => focus = FocusNode());
  tearDown(() => focus.dispose());

  testWidgets('landmarks carry stable ids', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, child: _page(focus: focus));
    for (final id in ['demo-page', 'demo-toolbar', 'demo-list-area']) {
      expect(find.bySemanticsIdentifier(id), findsOneWidget, reason: id);
    }
    handle.dispose();
  });

  testWidgets('Cmd/Ctrl+F focuses the search', (tester) async {
    await _pump(tester, child: _page(focus: focus));
    expect(focus.hasFocus, isFalse);
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    final modifier = mac
        ? LogicalKeyboardKey.metaLeft
        : LogicalKeyboardKey.controlLeft;
    // Give the frame focus so the shortcut is reachable.
    Focus.of(
      tester.element(find.byKey(const ValueKey('notice'))),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('short window: the selection bar replaces the toolbar', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(800, 716),
      child: _page(focus: focus, selectionBar: const Text('selection')),
    );
    expect(find.text('selection'), findsOneWidget);
    expect(find.byType(WpCollectionToolbar), findsNothing);

    await _pump(
      tester,
      size: const Size(800, 716),
      child: _page(focus: focus),
    );
    expect(find.byType(WpCollectionToolbar), findsOneWidget);
  });

  testWidgets('the selection bar sits between search row and list', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await _pump(
      tester,
      size: const Size(1100, 900),
      child: _page(focus: focus, selectionBar: const Text('selection')),
    );
    final bar = tester.getRect(find.text('selection'));
    final toolbar = tester.getRect(find.byType(WpCollectionToolbar));
    final list = tester.getRect(find.byKey(const ValueKey('demo-list-area')));
    expect(bar.top, greaterThanOrEqualTo(toolbar.bottom));
    expect(bar.bottom, lessThanOrEqualTo(list.top));
  });

  testWidgets('tools collapse into one overflow button on a narrow row', (
    tester,
  ) async {
    // In the app the sidebar takes its share of an 800 px window, so the
    // page itself is narrower than the window.
    await _pump(
      tester,
      size: const Size(700, 900),
      child: _page(focus: focus),
    );
    expect(find.byKey(const ValueKey('tools-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('tool-sort')), findsNothing);

    await _pump(
      tester,
      size: const Size(1400, 900),
      child: _page(focus: focus),
    );
    expect(find.byKey(const ValueKey('tools-more')), findsNothing);
    expect(find.byKey(const ValueKey('tool-sort')), findsOneWidget);
  });

  testWidgets('filter button opens the sections; a mark removes its filter', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var removed = 0;
    await _pump(
      tester,
      child: _page(focus: focus, onRemoveMark: () => removed++),
    );
    expect(find.text('Choice view 0'), findsNothing);
    await tester.tap(find.bySemanticsIdentifier('demo-filter-menu'));
    await tester.pumpAndSettle();
    for (final id in ['view', 'period']) {
      expect(
        find.bySemanticsIdentifier('demo-filter-section-$id'),
        findsOneWidget,
      );
    }
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier('demo-filter-mark-trash-remove'),
    );
    expect(removed, 1);
    // A screen reader or voice control presses it through its semantics
    // action, not a pointer (#662).
    final node = tester.getSemantics(
      find.bySemanticsIdentifier('demo-filter-mark-trash-remove'),
    );
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(removed, 2);
    handle.dispose();
  });

  testWidgets('a filter popover opened by pointer takes focus, so Escape '
      'closes it (#1845)', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, child: _page(focus: focus));
    focus.requestFocus();
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('demo-filter-menu'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('demo-filter-section-view'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier('demo-filter-section-view'),
      findsNothing,
    );
    handle.dispose();
  });
}
