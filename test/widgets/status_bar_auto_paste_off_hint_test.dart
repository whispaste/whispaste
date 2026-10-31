/// Widget tests for the `WpRecordingDock` Auto-Paste-Off hint chip.
///
/// Slice 11 of the onboarding-auto-paste-step feature surfaces a persistent
/// (but dismissible) hint in the status bar whenever the user has finished
/// onboarding with Auto-Paste skipped. These tests pin the three-condition
/// visibility rule and the dismiss / re-enable behaviour to the contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_dock.dart';
import 'package:whispaste/widgets/recording_dock_controls.dart';

import 'package:golden_screenshot/golden_screenshot.dart';

import '../fixtures/test_helpers.dart';

void main() {
  // Measure with the bundled fonts: the default Ahem test font is far wider
  // than the app's, which would make the chips fall back to icon form.
  setUpAll(loadAppFonts);

  group('shouldShowAutoPasteOffHint', () {
    test('hidden during onboarding (onboardingCompleted == false)', () {
      // Before onboarding completes the chip MUST stay hidden — the
      // onboarding overlay owns the screen and would clash with the hint.
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.clipboard,
          onboardingCompleted: false,
          autoPasteOffHintDismissed: false,
        ),
        isFalse,
      );
    });

    test('visible after skip path — all three conditions met', () {
      // Simulated outcome of slice 03: user finished onboarding but skipped
      // Auto-Paste, leaving afterTranscriptionAction at `clipboard`.
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.clipboard,
          onboardingCompleted: true,
          autoPasteOffHintDismissed: false,
        ),
        isTrue,
      );
    });

    test('hidden once dismissed by the user', () {
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.clipboard,
          onboardingCompleted: true,
          autoPasteOffHintDismissed: true,
        ),
        isFalse,
      );
    });

    test('hidden when Auto-Paste is on (paste)', () {
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.paste,
          onboardingCompleted: true,
          autoPasteOffHintDismissed: false,
        ),
        isFalse,
      );
    });

    test('hidden when Auto-Paste is on (clipboardAndPaste)', () {
      // Even with the dismiss flag still false, re-enabling Auto-Paste in
      // Settings hides the chip automatically — see AC #6.
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.clipboardAndPaste,
          onboardingCompleted: true,
          autoPasteOffHintDismissed: false,
        ),
        isFalse,
      );
    });

    test('visible when afterTranscription is `nothing`', () {
      expect(
        shouldShowAutoPasteOffHint(
          afterAction: AfterTranscriptionAction.nothing,
          onboardingCompleted: true,
          autoPasteOffHintDismissed: false,
        ),
        isTrue,
      );
    });
  });

  group('WpRecordingDock — Auto-Paste-Off hint chip', () {
    /// Builds a status bar with a configurable hint visibility flag. Mirrors
    /// the production wiring in `app.dart` so the test reflects how the host
    /// computes visibility from settings.
    Widget buildStatusBar({
      required bool showHint,
      VoidCallback? onTap,
      VoidCallback? onDismiss,
      Locale locale = const Locale('en'),
    }) {
      return makeTestable(
        locale: locale,
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            WpRecordingDock(
              sttModeLabel: 'On device',
              sttState: SttServerState.ready,
              afterAction: AfterTranscriptionAction.clipboard,
              afterActionLabel: 'After: Copy',
              onAfterActionChanged: (_) {},
              showAutoPasteOffHint: showHint,
              onAutoPasteOffHintTap: onTap,
              onAutoPasteOffHintDismiss: onDismiss,
            ),
          ],
        ),
      );
    }

    // The status bar lives in the content area to the right of a 240 px
    // sidebar spacer. The default headless test surface is 800x600, which
    // pushes the dismiss icon out of the hit-test bounds. Resize the view
    // to match the MediaQuery `makeTestable` declares.
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.devicePixelRatio = 1.0;
      view.physicalSize = const Size(1280, 800);
    });

    tearDown(() {
      final view =
          TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      view.resetDevicePixelRatio();
      view.resetPhysicalSize();
    });

    Future<String> hintLabel(WidgetTester tester) async {
      final BuildContext ctx = tester.element(find.byType(WpRecordingDock));
      return L10n.of(ctx).statusBarAutoPasteOffHint;
    }

    Future<void> openMehr(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('dock-overflow')));
      await tester.pumpAndSettle();
    }

    testWidgets('the hint is an entry in Mehr with its clipboard icon', (
      tester,
    ) async {
      await tester.pumpWidget(buildStatusBar(showHint: true, onDismiss: () {}));
      await tester.pump();
      await openMehr(tester);
      final entry = find.byKey(const ValueKey('dock-menu-auto-paste'));
      expect(
        find.descendant(
          of: entry,
          matching: find.text(await hintLabel(tester)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: entry,
          matching: find.byIcon(LucideIcons.clipboardX),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('dock-menu-auto-paste-dismiss')),
          matching: find.byIcon(LucideIcons.x),
        ),
        findsOneWidget,
      );
    });

    testWidgets('hides the hint entry when showAutoPasteOffHint is false', (
      tester,
    ) async {
      await tester.pumpWidget(buildStatusBar(showHint: false));
      await tester.pump();
      expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
      expect(find.text(await hintLabel(tester)), findsNothing);
    });

    testWidgets('selecting the hint entry fires onAutoPasteOffHintTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        buildStatusBar(showHint: true, onTap: () => tapped = true),
      );
      await tester.pump();
      await openMehr(tester);
      await tester.tap(find.byKey(const ValueKey('dock-menu-auto-paste')));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });

    testWidgets('selecting the dismiss entry fires onAutoPasteOffHintDismiss', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildStatusBar(showHint: true, onDismiss: () => dismissed = true),
      );
      await tester.pump();
      await openMehr(tester);
      await tester.tap(
        find.byKey(const ValueKey('dock-menu-auto-paste-dismiss')),
      );
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets(
      'visibility flips off without calling dismiss when host hides chip',
      (tester) async {
        // First frame: hint visible (user skipped Auto-Paste in onboarding).
        await tester.pumpWidget(buildStatusBar(showHint: true));
        await tester.pump();
        await openMehr(tester);
        expect(
          find.byKey(const ValueKey('dock-menu-auto-paste')),
          findsOneWidget,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        // Simulate the user re-enabling Auto-Paste in Settings: the parent
        // recomputes visibility from settings and rebuilds with the flag off.
        await tester.pumpWidget(buildStatusBar(showHint: false));
        await tester.pump();
        expect(find.byKey(const ValueKey('dock-overflow')), findsNothing);
      },
    );

    testWidgets(
      'the Mehr menu and its entries are operable from the keyboard',
      (tester) async {
        var tapped = false;
        var dismissed = false;
        await tester.pumpWidget(
          buildStatusBar(
            showHint: true,
            onTap: () => tapped = true,
            onDismiss: () => dismissed = true,
          ),
        );
        await tester.pump();
        bool overflowFocused() {
          final focused = FocusManager.instance.primaryFocus?.context;
          return focused != null &&
              focused.findAncestorWidgetOfExactType<WpDockOverflow>() != null;
        }

        for (var i = 0; i < 40 && !overflowFocused(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(overflowFocused(), isTrue, reason: 'Mehr is reachable by Tab');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('dock-menu-auto-paste')),
          findsOneWidget,
        );
        // No entry is highlighted when the menu opens: the first arrow key
        // highlights the first entry, the second moves to the dismiss entry.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          dismissed,
          isTrue,
          reason: 'two arrow-downs reach the dismiss entry',
        );
        expect(tapped, isFalse);
      },
    );
  });
}
