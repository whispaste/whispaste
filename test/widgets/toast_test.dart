/// Widget tests for [WpToast.show] — verifies both action paths (the
/// bundled [WpToastAction] and the legacy `actionLabel`+`onAction`
/// pair) render the action button correctly and fire their callback.
///
/// Covers AC1, AC4 (recovery-toast navigation seam), AC5 (factory-reset
/// exit seam) and the spy requirement from AC7 in
/// `.scratch/reliability-sprint/issues/07-feat-actionable-toast-polish.md`.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/toast.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_touch_target.dart';

import '../fixtures/test_helpers.dart';
import 'package:golden_screenshot/golden_screenshot.dart' show loadAppFonts;

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

/// The localized dismiss label, read from the toast's own tree.
Future<String> _dismissLabel(WidgetTester tester) async {
  final context = tester.element(find.byType(ElevatedButton));
  return L10n.of(context).actionDismiss;
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
      await loadAppFonts();
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

    // UX-050: the hotkey-fallback toast carries the active combination in its
    // last sentence. At 2.0 the old layout (action and close beside the text)
    // left the message a narrow column and the line cap cut the tail away.
    testWidgets('hotkey fallback keeps the full message at text scale 2.0 '
        '(UX-050)', (tester) async {
      const fallback =
          'Win+Umschalt+D ist von einer anderen App belegt. Bis du eine andere '
          'Kombination wählst, startet Strg+Umschalt+Leertaste das Diktat.';
      await tester.binding.setSurfaceSize(const Size(800, 716));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: makeTestable(
            _ToastHarness(
              onShow: (ctx) => WpToast.show(
                ctx,
                message: fallback,
                type: WpToastType.warning,
                messageTestId: 'toast-hotkey-fallback',
                duration: const Duration(seconds: 10),
                action: WpToastAction(
                  label: 'Ändern',
                  testId: 'toast-hotkey-fallback-change',
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      await _showAndSettle(tester);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text(fallback),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason:
            'The fallback message was cut off at text scale 2.0, so the active '
            'combination at its end is lost.',
      );
      expect(
        find.byKey(const ValueKey('toast-hotkey-fallback-change')),
        findsOneWidget,
      );

      await tester.pumpAndSettle(const Duration(seconds: 11));
    });

    testWidgets('dismiss button has a 48 px tap area (WpLayout rule)', (
      tester,
    ) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'dismiss target',
            type: WpToastType.info,
          ),
        ),
      );
      await _showAndSettle(tester);

      final l10n = await _dismissLabel(tester);
      final close = find.byTooltip(l10n);
      expect(close, findsOneWidget);
      final centre = tester.getCenter(close);
      // 20 px right of the 14 px glyph's centre: outside the glyph, inside a
      // 48 px square. Only the enlarged tap area accepts it.
      await tester.tapAt(centre + const Offset(20, 0));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(
        find.text('dismiss target'),
        findsNothing,
        reason:
            'The close button is a 14 px glyph; its tap area must be at '
            'least 48 px square so it is reachable without a precise hit.',
      );
    });

    testWidgets('action button: tap area is at least 48 px high', (
      tester,
    ) async {
      var tapped = 0;

      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'target size',
            type: WpToastType.error,
            action: WpToastAction(
              label: 'action-target',
              onPressed: () => tapped++,
            ),
          ),
        ),
      );

      await _showAndSettle(tester);

      final button = find.byKey(const ValueKey('toast-action'));
      expect(button, findsOneWidget);
      final target = find.ancestor(
        of: button,
        matching: find.byType(WpTouchTarget),
      );
      expect(target, findsOneWidget);
      expect(
        tester.getSize(target).height,
        greaterThanOrEqualTo(WpLayout.minTouchTarget),
        reason:
            'The action is the primary control of the toast; its tap '
            'area must match the 48 px rule of the close button.',
      );

      // 20 px below the visual's centre: outside the 32 px label box, inside
      // the 48 px target. Only the enlarged tap area accepts it.
      final centre = tester.getCenter(button);
      await tester.tapAt(centre + const Offset(0, 20));
      await tester.pumpAndSettle();

      expect(tapped, 1);

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });

  group('WpToast — auto-dismiss timer', () {
    testWidgets('an actionable toast stays at least 10 s, even when asked for '
        'less', (tester) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'undo window',
            type: WpToastType.info,
            duration: const Duration(seconds: 2),
            actionLabel: 'Undo',
            onAction: () {},
          ),
        ),
      );
      await _showAndSettle(tester);

      await tester.pump(const Duration(seconds: 9));
      expect(find.text('undo window'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('undo window'), findsNothing);
    });

    testWidgets('a plain toast keeps its own duration', (tester) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'short notice',
            type: WpToastType.info,
            duration: const Duration(seconds: 3),
          ),
        ),
      );
      await _showAndSettle(tester);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('short notice'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('short notice'), findsNothing);
    });

    testWidgets('a pointer over the toast holds the timer, and it resumes '
        'with at least 5 s after the pointer leaves', (tester) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'held notice',
            type: WpToastType.info,
            duration: const Duration(seconds: 3),
          ),
        ),
      );
      await _showAndSettle(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('held notice')));
      await tester.pump();

      await tester.pump(const Duration(seconds: 30));
      expect(find.text('held notice'), findsOneWidget);

      await mouse.moveTo(const Offset(4, 4));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('held notice'), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(find.text('held notice'), findsNothing);
    });

    testWidgets('closing a hovered toast leaves no timer running afterwards', (
      tester,
    ) async {
      await _pumpHarness(
        tester,
        _ToastHarness(
          onShow: (ctx) => WpToast.show(
            ctx,
            message: 'closed while hovered',
            type: WpToastType.info,
            duration: const Duration(seconds: 3),
          ),
        ),
      );
      await _showAndSettle(tester);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.text('closed while hovered')));
      await tester.pump();

      final l10n = await _dismissLabel(tester);
      await tester.tap(find.byTooltip(l10n).last);
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('closed while hovered'), findsNothing);

      // The pointer leaves after the toast is gone. A timer armed now would
      // outlive the toast and fail the test at teardown.
      await mouse.moveTo(const Offset(4, 4));
      await tester.pump();
    });
  });
}
