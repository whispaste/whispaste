/// Widget tests for [SnippetPickerBody] — the Snippet-Picker render engine's
/// panel content (search field, keyboard-navigable result list, key-hint
/// footer).
///
/// Regression coverage for two live-test bugs:
///  - The search field must hold real Flutter keyboard focus as soon as the
///    panel's first frame settles, so the user can type immediately.
///  - Escape must close the panel (fire `onCancel`) while the search field
///    has focus — Flutter's macOS `DefaultTextEditingShortcuts` (installed by
///    `WidgetsApp`, an ANCESTOR of this widget's own `Shortcuts`) maps Escape
///    to an intent that stops propagation, so the platform under test
///    matters: `flutter_test` defaults `defaultTargetPlatform` to `android`,
///    whose text-editing shortcut map does not touch Escape, which would
///    make this test pass for the wrong reason. Forcing
///    `TargetPlatform.macOS` (try/finally around each body — the repo's
///    established pattern, see `mic_permission_chip_test.dart`; a `setUp`/
///    `tearDown` pair trips `flutter_test`'s "foundation debug variable
///    changed" invariant check mid-test) exercises the actual map the real
///    app runs under.
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/services/snippet_picker/snippet_picker_render_channel.dart';
import 'package:whispaste/snippet_picker_render_entrypoint.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

const _items = [
  SnippetPickerRenderItem(id: '1', title: 'Greeting', body: 'Hello there'),
  SnippetPickerRenderItem(id: '2', title: 'Signoff', body: 'Best regards'),
];

/// Mirrors the real entrypoint's `MaterialApp` (`_SnippetPickerRenderApp`) —
/// same theme/localization wiring, so `WidgetsApp.defaultShortcuts` and
/// `DefaultTextEditingShortcuts` are present exactly as they are in the app,
/// which is the layer this file's Escape regression is actually about.
Future<void> _pumpPicker(
  WidgetTester tester, {
  required TextEditingController controller,
  List<SnippetPickerRenderItem> items = _items,
  int showGeneration = 0,
  bool visible = true,
  ValueChanged<String>? onSelect,
  VoidCallback? onCancel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: wpDarkTheme(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: SnippetPickerBody(
          items: items,
          showGeneration: showGeneration,
          visible: visible,
          searchController: controller,
          l10n: lookupL10n(const Locale('en')),
          onSelect: onSelect ?? (_) {},
          onCancel: onCancel ?? () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SnippetPickerBody — focus (live-test bug 1)', () {
    testWidgets('search field holds real focus after the first frame', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await _pumpPicker(tester, controller: controller);

        final field = tester.widget<WpSearchField>(find.byType(WpSearchField));
        expect(
          field.focusNode!.hasFocus,
          isTrue,
          reason:
              'the search field must be the primary focus as soon as the '
              'panel appears, so the user can type without clicking first',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('re-show (showGeneration bump) re-claims focus', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await _pumpPicker(tester, controller: controller);
        final field = tester.widget<WpSearchField>(find.byType(WpSearchField));

        // Simulate the field losing focus (e.g. a stray native focus hop)
        // between two invocations of a reused picker engine.
        field.focusNode!.unfocus();
        await tester.pump();
        expect(field.focusNode!.hasFocus, isFalse);

        await _pumpPicker(tester, controller: controller, showGeneration: 1);
        expect(field.focusNode!.hasFocus, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('SnippetPickerBody — Escape (live-test bug 2)', () {
    testWidgets('Escape fires onCancel while the search field has focus', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        var cancelled = false;

        await _pumpPicker(
          tester,
          controller: controller,
          onCancel: () => cancelled = true,
        );

        final field = tester.widget<WpSearchField>(find.byType(WpSearchField));
        expect(field.focusNode!.hasFocus, isTrue);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();

        expect(
          cancelled,
          isTrue,
          reason: 'Escape must close the picker, same as clicking outside it',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('SnippetPickerBody — arrow navigation (live-test bug 4)', () {
    testWidgets('ArrowDown moves the highlight the submit then acts on', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? selectedId;

        // Three items so two presses land unambiguously on the last one —
        // a wrong-but-plausible outcome (highlight never moved) selects '1',
        // and an off-by-one selects '2'.
        await _pumpPicker(
          tester,
          controller: controller,
          items: const [
            SnippetPickerRenderItem(id: '1', title: 'A', body: 'first'),
            SnippetPickerRenderItem(id: '2', title: 'B', body: 'second'),
            SnippetPickerRenderItem(id: '3', title: 'C', body: 'third'),
          ],
          onSelect: (id) => selectedId = id,
        );

        final field = tester.widget<WpSearchField>(find.byType(WpSearchField));
        expect(field.focusNode!.hasFocus, isTrue);

        // The live-test question this file did NOT answer before: do
        // ArrowDown/ArrowUp reach this widget's own `Shortcuts` at all while
        // the search field holds focus, or does the `EditableText` subtree /
        // macOS `DefaultTextEditingShortcuts` consume them as caret motion
        // first? Everything native (panel key status, app activation, frame
        // presentation) was being investigated on the assumption that this
        // half already worked.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(
          selectedId,
          '3',
          reason:
              'two ArrowDown presses must move the highlight from the first '
              'to the third item',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('ArrowUp moves the highlight back and clamps at the top', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? selectedId;

        await _pumpPicker(
          tester,
          controller: controller,
          onSelect: (id) => selectedId = id,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        // Three ups from index 1 must clamp at 0, not wrap or go negative.
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await tester.pump();
        }

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(selectedId, '1');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('SnippetPickerBody — animation gating (frame-starvation fix)', () {
    // Companion to test/services/snippet_picker/
    // snippet_picker_engine_lifecycle_test.dart: with the render engine
    // detached from the embedder's app lifecycle, frames are never
    // lifecycle-disabled — so the panel's own `visible` flag (relayed via
    // native show()/dismiss()) must be what starts and stops the continuous
    // glass drift animation, or an invisible panel would repaint all
    // session. Tickers are the observable: `transientCallbackCount` counts
    // active animation tickers, and the drift `repeat()` holds one open.
    testWidgets('glass animations run only while the panel is visible', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        // The autofocused search field runs finite focus animations
        // (~hundreds of ms) that also hold tickers open; every assertion
        // below first pumps past them, so the only ticker that can remain
        // is the panel's own unbounded drift `repeat()`.
        const settleFiniteAnimations = Duration(milliseconds: 500);

        // Boot state: engine alive (prewarm), panel never shown.
        await _pumpPicker(tester, controller: controller, visible: false);
        await tester.pump(settleFiniteAnimations);
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason: 'no ticker may run while the panel has never been shown',
        );

        // Native show(): setItems bumps the generation and flips visible on.
        await _pumpPicker(
          tester,
          controller: controller,
          visible: true,
          showGeneration: 1,
        );
        await tester.pump(settleFiniteAnimations);
        expect(
          tester.binding.transientCallbackCount,
          greaterThan(0),
          reason: 'the glass drift cycle must animate while on screen',
        );

        // Native dismiss(): panelHidden flips visible off (generation stays).
        await _pumpPicker(
          tester,
          controller: controller,
          visible: false,
          showGeneration: 1,
        );
        await tester.pump(settleFiniteAnimations);
        expect(
          tester.binding.transientCallbackCount,
          0,
          reason:
              'an ordered-out panel must not keep repainting for the rest '
              'of the app session',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('SnippetPickerBody — Enter (control, already working)', () {
    testWidgets('Enter selects the highlighted item', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        String? selectedId;

        await _pumpPicker(
          tester,
          controller: controller,
          onSelect: (id) => selectedId = id,
        );

        // Enter reaches `WpSearchField.onSubmitted` via the text-input
        // "done" action, not a raw hardware key event — mirrors how the app
        // itself triggers it (the search field's `TextInputAction` is the
        // default single-line `done`) and how the repo's other tests submit
        // text fields (see `notes_page_test.dart`).
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(selectedId, '1');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
