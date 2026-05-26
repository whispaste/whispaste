/// Widget tests for [WpToast.show] — verifies both action paths (the
/// bundled [WpToastAction] and the legacy `actionLabel`+`onAction`
/// pair) render the action button correctly and fire their callback.
///
/// Covers AC1, AC4 (recovery-toast navigation seam), AC5 (factory-reset
/// exit seam) and the spy requirement from AC7 in
/// `.scratch/reliability-sprint/issues/07-feat-actionable-toast-polish.md`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/toast.dart';

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
      // No TextButton (the action surface) in the toast card itself.
      // The harness's ElevatedButton is the only other button in scope.
      expect(find.byType(TextButton), findsNothing);

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
}
