/// Widget tests for [WpToast.show] — verifies both action paths (the
/// bundled [WpToastAction] and the legacy `actionLabel`+`onAction`
/// pair) render the action button correctly and fire their callback.
///
/// Covers AC1, AC4 (recovery-toast navigation seam), AC5 (factory-reset
/// exit seam) and the spy requirement from AC7 in
/// `.scratch/reliability-sprint/issues/07-feat-actionable-toast-polish.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/toast.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

class _ToastHarness extends StatelessWidget {
  const _ToastHarness({required this.onShow});

  final void Function(BuildContext) onShow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => onShow(context),
        child: const Text('show-toast'),
      ),
    );
  }
}

/// Re-uses the same harness across all WpToast action-button tests but
/// resizes the test surface so the bottom-right toast lands inside the
/// hit-test bounds.
Future<void> _pumpHarness(WidgetTester tester, Widget harness) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(makeTestable(harness));
}

/// Fires the harness's `show-toast` button and waits for the slide-in
/// animation to fully settle. Using `pump(300ms)` alone is not enough
/// — the curved SlideTransition leaves the action button just below
/// the visible viewport, so taps miss its hit-test bounds.
Future<void> _showAndSettle(WidgetTester tester) async {
  await tester.tap(find.text('show-toast'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  group('WpToast — action button', () {
    testWidgets('without action: renders no action button', (tester) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'plain message',
            type: WpToastType.info,
          ),
        ),
      );

      await _showAndSettle(tester);

      expect(find.text('plain message'), findsOneWidget);
      // No WpButton (the action surface) in the toast card itself.
      // The harness's ElevatedButton is the only other button in scope.
      expect(find.byType(WpButton), findsNothing);

      // Drain the toast's auto-dismiss timer so no Timer outlives the test.
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('with WpToastAction: renders label and fires callback', (
      tester,
    ) async {
      var tapped = 0;

      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'actionable message',
            type: WpToastType.error,
            action: WpToastAction(
              label: 'Einstellungen öffnen',
              onPressed: () => tapped++,
            ),
          ),
        ),
      );

      await _showAndSettle(tester);

      expect(find.text('actionable message'), findsOneWidget);
      expect(find.text('Einstellungen öffnen'), findsOneWidget);

      // Tap the action — spy callback must fire exactly once and the
      // toast must dismiss itself.
      await tester.tap(find.text('Einstellungen öffnen'));
      await tester.pumpAndSettle();

      expect(tapped, 1, reason: 'WpToastAction.onPressed must fire on tap');

      // Drain any pending auto-dismiss timer.
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('legacy actionLabel+onAction pair still works', (tester) async {
      var tapped = 0;

      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'legacy',
            type: WpToastType.warning,
            actionLabel: 'Undo',
            onAction: () => tapped++,
          ),
        ),
      );

      await _showAndSettle(tester);

      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(tapped, 1);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('bundled action wins over legacy pair when both provided', (
      tester,
    ) async {
      var bundled = 0;
      var legacy = 0;

      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'precedence',
            type: WpToastType.info,
            actionLabel: 'legacy-label',
            onAction: () => legacy++,
            action: WpToastAction(
              label: 'bundled-label',
              onPressed: () => bundled++,
            ),
          ),
        ),
      );

      await _showAndSettle(tester);

      expect(find.text('bundled-label'), findsOneWidget);
      expect(find.text('legacy-label'), findsNothing);

      await tester.tap(find.text('bundled-label'));
      await tester.pumpAndSettle();

      expect(bundled, 1);
      expect(legacy, 0);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

  group('WpToast — message line budget', () {
    // The longest string the app ever puts in a toast: the German
    // `pasteCapabilityRepairFailed`. It fills the card's four lines exactly at
    // 1.0×, which makes it the canary for the line cap. Hardcoded rather than
    // loaded from the ARB so a copy edit cannot silently defuse the test — if
    // the real string grows past this one, that is a deliberate decision worth
    // re-measuring here.
    const longMessage =
        'macOS-Berechtigungs-Reset konnte nicht ausgeführt werden. Bitte '
        'WhisPaste manuell aus Systemeinstellungen → Bedienungshilfen '
        'entfernen.';

    // Line-wrapping is a font-metrics question, and `flutter test` ships a
    // fallback font whose glyphs are all one width — under it this message
    // wraps to roughly twice as many lines as it does on a real build, and the
    // assertion below would measure the test harness rather than the toast.
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
    });

    // Before this family moved off `SnackBar`, the message was rendered
    // full-width and unbounded. The toast card is capped at 400 px and its
    // line budget used to be a fixed 4, so raising the system text size cut
    // the message off — and the tail is the actionable half ("Bitte … aus
    // Systemeinstellungen → Bedienungshilfen entfernen"). Users who need large
    // text were the only ones who lost the instruction.
    //
    // 1.0× is deliberately not asserted: this string fills the four-line
    // budget exactly at the default size, so a test there would flip on any
    // Inter metric change and report a font update as a toast regression. The
    // raised sizes carry a line of slack each, which is what makes them a
    // stable signal.
    for (final scale in [1.3, 1.6]) {
      testWidgets('long message is not ellipsized at textScaler $scale', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1280, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: makeTestable(
              _ToastHarness(
                onShow: (ctx) => WpToast.show(
                  ctx,
                  message: longMessage,
                  type: WpToastType.error,
                ),
              ),
            ),
          ),
        );

        await _showAndSettle(tester);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(longMessage),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason:
              'The toast truncated its message at textScaler $scale. The line '
              'budget in _ToastCard must grow with the text scaler, otherwise '
              'large-text users lose the end of the message — which is where '
              'the actionable instruction lives.',
        );

        await tester.pumpAndSettle(const Duration(seconds: 4));
      });
    }
  });
}
