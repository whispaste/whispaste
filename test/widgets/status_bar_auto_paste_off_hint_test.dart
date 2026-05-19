/// Widget tests for the `WpStatusBar` Auto-Paste-Off hint chip.
///
/// Slice 11 of the onboarding-auto-paste-step feature surfaces a persistent
/// (but dismissible) hint in the status bar whenever the user has finished
/// onboarding with Auto-Paste skipped. These tests pin the three-condition
/// visibility rule and the dismiss / re-enable behaviour to the contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

void main() {
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

  group('WpStatusBar — Auto-Paste-Off hint chip', () {
    /// Builds a status bar with a configurable hint visibility flag. Mirrors
    /// the production wiring in `app.dart` so the test reflects how the host
    /// computes visibility from settings.
    Widget buildStatusBar({
      required bool showHint,
      VoidCallback? onTap,
      VoidCallback? onDismiss,
    }) {
      return makeTestable(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            WpStatusBar(
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
      final BuildContext ctx = tester.element(find.byType(WpStatusBar));
      return L10n.of(ctx).statusBarAutoPasteOffHint;
    }

    testWidgets('renders the chip when showAutoPasteOffHint is true', (
      tester,
    ) async {
      await tester.pumpWidget(buildStatusBar(showHint: true));
      await tester.pump();

      expect(find.text(await hintLabel(tester)), findsOneWidget);
      expect(find.byIcon(LucideIcons.clipboardX), findsOneWidget);
      // The dismiss icon (X) — distinct from the chip body icon.
      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('hides the chip when showAutoPasteOffHint is false', (
      tester,
    ) async {
      await tester.pumpWidget(buildStatusBar(showHint: false));
      await tester.pump();

      expect(find.text(await hintLabel(tester)), findsNothing);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('tapping the chip body fires onAutoPasteOffHintTap', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        buildStatusBar(showHint: true, onTap: () => tapped = true),
      );
      await tester.pump();

      await tester.tap(find.text(await hintLabel(tester)));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('tapping the dismiss icon fires onAutoPasteOffHintDismiss', (
      tester,
    ) async {
      var dismissed = false;
      await tester.pumpWidget(
        buildStatusBar(showHint: true, onDismiss: () => dismissed = true),
      );
      await tester.pump();

      // The dismiss icon sits inside its own InkWell wrapped in a Tooltip —
      // tap the enclosing InkWell so hit-testing isn't intercepted by the
      // Tooltip's MouseRegion in headless test mode.
      final dismissInkWell = find.ancestor(
        of: find.byIcon(LucideIcons.x),
        matching: find.byType(InkWell),
      );
      await tester.tap(dismissInkWell);
      await tester.pump();

      expect(dismissed, isTrue);
    });

    testWidgets(
      'visibility flips off without calling dismiss when host hides chip',
      (tester) async {
        // First frame: chip visible (user skipped Auto-Paste in onboarding).
        await tester.pumpWidget(buildStatusBar(showHint: true));
        await tester.pump();
        expect(find.text(await hintLabel(tester)), findsOneWidget);

        // Simulate the user re-enabling Auto-Paste in Settings: the parent
        // recomputes visibility from settings and rebuilds with the flag off.
        await tester.pumpWidget(buildStatusBar(showHint: false));
        await tester.pump();

        expect(find.text(await hintLabel(tester)), findsNothing);
      },
    );
  });
}
