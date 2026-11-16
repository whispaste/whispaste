/// Ticket 27 regression guard — History's transcript formatting after the
/// bold/italic/bullet logic moved into [WpMarkdownFormatting].
///
/// History used to carry its own second copy of those three operations next
/// to the toolbar's. The copy is gone; both the keyboard shortcuts and the
/// toolbar buttons now go through the shared owner the Notes editor also
/// uses. This pins that History still formats the way it did — and, where it
/// changed, that it changed towards the toolbar it always displayed: the
/// shortcut can now take formatting back off, which is what the button beside
/// it has always done.
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/data/providers.dart';
import 'package:whispaste/features/history/data/sample_data.dart';
import 'package:whispaste/features/history/history_page.dart';
import 'package:whispaste/widgets/find_replace_bar.dart';
import 'package:whispaste/widgets/markdown_toolbar.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// The detail panel has long-standing tight-fit overflow at some widths; these
/// tests assert behaviour, not layout (same waiver as
/// `history_export_wiring_test.dart`).
void _ignoreOverflowErrors() {
  final originalHandler = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.toString().contains('overflowed')) return;
    originalHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = originalHandler);
}

List<Object> _sampleOverrides() {
  final all = generateSampleEntries();
  final active = all.where((e) => e.deletedAt == null && !e.archived).toList();
  final archived = all.where((e) => e.archived && e.deletedAt == null).toList();
  final trash = all.where((e) => e.deletedAt != null).toList();
  return [
    pagedHistoryProvider.overrideWith((ref) => Stream.value(active)),
    // The list carries no full text since #1333; the detail panel loads it.
    historyFullEntryProvider.overrideWith(
      (ref, id) => Stream.value(all.where((e) => e.id == id).firstOrNull),
    ),
    archivedEntriesProvider.overrideWith((ref) => Stream.value(archived)),
    trashEntriesProvider.overrideWith((ref) => Stream.value(trash)),
  ];
}

Future<void> _pressShortcut(WidgetTester tester, LogicalKeyboardKey key) async {
  final modifier = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.meta
      : LogicalKeyboardKey.control;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await tester.pump();
}

/// The transcript field's controller — the panel owns it, so the test reaches
/// it through the widget rather than through a seam that only exists for
/// tests.
TextEditingController _transcriptController(WidgetTester tester) => tester
    .widget<WpTextField>(
      find.byWidgetPredicate(
        (w) => w is WpTextField && w.variant == WpTextFieldVariant.passage,
      ),
    )
    .controller;

/// Opens the first sample entry and focuses its transcript editor.
Future<void> _openTranscriptEditor(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1800, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The detail panel loads its entry from the database by id.
  final first = generateSampleEntries().first;
  final db = HistoryDatabase.forTesting(NativeDatabase.memory());
  await db.insertHistoryEntry(
    HistoryEntriesCompanion.insert(
      id: first.id,
      timestamp: first.timestamp,
      content: Value(first.content),
      title: Value(first.title),
    ),
  );
  await tester.pumpWidget(
    makeTestable(
      const HistoryPage(),
      db: db,
      size: const Size(1800, 900),
      overrides: _sampleOverrides(),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Meeting notes — Product roadmap Q3').first);
  await tester.pumpAndSettle();

  // The transcript is written directly (#1498); a tap puts the focus in it.
  await tester.tap(
    find.byWidgetPredicate(
      (w) => w is WpTextField && w.variant == WpTextFieldVariant.passage,
    ),
  );
  await tester.pumpAndSettle();

  expect(
    find.byWidgetPredicate(
      (w) => w is WpTextField && w.variant == WpTextFieldVariant.passage,
    ),
    findsOneWidget,
    reason: 'transcript editor is not on screen',
  );
}

/// Taps a toolbar control after scrolling it to the middle of the pane. The
/// edit pill sits below the transcript, so opening the editor leaves the
/// toolbar (#638: it stays above the text) at the pane's top edge, under the
/// page header.
Future<void> _tapInView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// Drains the metadata preview debounce and Drift/Riverpod teardown timers before the framework's
/// `!timersPending` invariant runs.
Future<void> _teardownTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('Ctrl/Cmd+B still wraps the transcript selection in edit mode', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _openTranscriptEditor(tester);

    expect(find.byType(WpMarkdownToolbar), findsOneWidget);

    final controller = _transcriptController(tester);
    final original = controller.text;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);

    await _pressShortcut(tester, LogicalKeyboardKey.keyB);

    expect(
      controller.text,
      '**${original.substring(0, 2)}**${original.substring(2)}',
    );

    // And back off again — the shortcut now matches the button it sits under.
    await _pressShortcut(tester, LogicalKeyboardKey.keyB);
    expect(controller.text, original);

    await _teardownTree(tester);
  });

  testWidgets('Ctrl/Cmd+I still wraps the transcript selection in edit mode', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _openTranscriptEditor(tester);

    final controller = _transcriptController(tester);
    final original = controller.text;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);

    await _pressShortcut(tester, LogicalKeyboardKey.keyI);

    expect(
      controller.text,
      '_${original.substring(0, 2)}_${original.substring(2)}',
    );

    await _teardownTree(tester);
  });

  // The find bar's own Escape handling only matters here. Pumped standalone,
  // the bar closes on Escape because nothing else wants the key; inside the
  // detail panel, Escape is already bound to closing the panel, which takes the
  // toolbar — and the bar — down with it. Both paths
  // end with the bar gone, so "the bar disappeared" proves nothing. The
  // load-bearing assertion is that the transcript is *still* being edited.
  testWidgets(
    'Escape closes the find bar without leaving transcript edit mode',
    (tester) async {
      _ignoreOverflowErrors();
      await _openTranscriptEditor(tester);

      await _tapInView(tester, find.bySemanticsLabel(l10n.findReplaceToggle));
      await tester.pumpAndSettle();
      expect(find.byType(WpFindReplaceBar), findsOneWidget);

      // Focus has to sit in the find field: that is where the bar's
      // `FocusNode.onKeyEvent` gets first crack at the key, ahead of the
      // panel's ancestor `CallbackShortcuts`.
      await tester.tap(find.bySemanticsLabel(l10n.findReplaceFindLabel));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel(l10n.findReplaceFindLabel),
        'the',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(WpFindReplaceBar), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is WpTextField && w.variant == WpTextFieldVariant.passage,
        ),
        findsOneWidget,
        reason:
            'Escape reached the panel and closed it instead of being '
            'consumed by the find bar',
      );

      await _teardownTree(tester);
    },
  );

  // The other half of the same contract: with the bar shut, Escape must still
  // do what it always did. A find bar that swallowed the key permanently
  // would pass the test above and still be a regression.
  testWidgets('Escape still closes the panel when the bar is shut', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _openTranscriptEditor(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is WpTextField && w.variant == WpTextFieldVariant.passage,
      ),
      findsNothing,
    );

    await _teardownTree(tester);
  });

  testWidgets('the toolbar button formats the same text the shortcut does', (
    tester,
  ) async {
    _ignoreOverflowErrors();
    await _openTranscriptEditor(tester);

    final controller = _transcriptController(tester);
    final original = controller.text;
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);

    await _tapInView(
      tester,
      find.bySemanticsLabel(
        l10n.markdownToolbarBold(WpMarkdownFormatting.boldShortcutLabel(l10n)),
      ),
    );
    await tester.pump();

    expect(
      controller.text,
      '**${original.substring(0, 2)}**${original.substring(2)}',
    );

    await _teardownTree(tester);
  });
}
