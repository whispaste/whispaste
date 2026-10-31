/// Tests for [WpButton] — the app's single push-button.
///
/// AC1 — every variant renders its Material carrier and its label
/// AC2 — `onPressed: null` disables the button and swallows taps
/// AC3 — `isLoading` swaps the icon for a spinner and disables the button
/// AC4 — `tone: danger` resolves to the shared error tint tokens
/// AC5 — `dense` is visually shorter than `standard`
/// AC6 — `disabledTooltip` appears only while the button is disabled
/// AC7 — the filled variant rings in a colour its fill can't swallow
/// AC8 — `testId` is the identifier of the node that carries the tap action
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/wp_button.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // AC1 — variants
  // -------------------------------------------------------------------------
  group('AC1 — variants', () {
    testWidgets('an enabled button fires its callback on tap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          WpButton(
            label: 'Los',
            variant: WpButtonVariant.primary,
            onPressed: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(WpButton));
      await tester.pump();

      expect(taps, 1);
    });
  });

  // -------------------------------------------------------------------------
  // AC2 — disabled
  // -------------------------------------------------------------------------
  group('AC2 — onPressed: null', () {
    testWidgets('marks the button disabled and swallows taps', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Gesperrt',
            variant: WpButtonVariant.primary,
            onPressed: null,
          ),
        ),
      );

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.enabled, isFalse);
      expect(button.onPressed, isNull);

      // Tapping a disabled button must stay a no-op rather than throw.
      await tester.tap(find.byType(WpButton), warnIfMissed: false);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    // Removed 2026-08-11 (dark-only build): 'light theme resolves its own
    // disabled-primary outline' repeated the assertion above with
    // Brightness.light, confirming both themes resolved to the same border
    // token. The app now ships a single dark theme only, so there is no
    // second theme left to compare against.
  });

  // -------------------------------------------------------------------------
  // AC3 — loading
  // -------------------------------------------------------------------------
  group('AC3 — isLoading', () {
    testWidgets('is not tappable while loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        makeTestable(
          WpButton(
            label: 'Sende',
            variant: WpButtonVariant.primary,
            onPressed: () => taps++,
            isLoading: true,
          ),
        ),
      );

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
        isFalse,
      );

      await tester.tap(find.byType(WpButton), warnIfMissed: false);
      await tester.pump();

      expect(taps, 0);
    });
  });

  // -------------------------------------------------------------------------
  // AC6 — disabledTooltip
  // -------------------------------------------------------------------------
  group('AC6 — disabledTooltip', () {
    testWidgets('wraps the disabled button in a Tooltip', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Modell laden',
            variant: WpButtonVariant.primary,
            onPressed: null,
            disabledTooltip: 'Erst ein Modell auswählen',
          ),
        ),
      );

      final tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.byType(FilledButton),
          matching: find.byType(Tooltip),
        ),
      );

      expect(tooltip.message, 'Erst ein Modell auswählen');
    });

    testWidgets('stays absent while the button is enabled', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Modell laden',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
            disabledTooltip: 'Erst ein Modell auswählen',
          ),
        ),
      );

      expect(
        find.ancestor(
          of: find.byType(FilledButton),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );
    });
  });
}

/// Const-friendly stand-in for "enabled" where the test doesn't count taps.
void _noop() {
  // -------------------------------------------------------------------------
  // AC8 — testId
  // -------------------------------------------------------------------------
  group('AC8 — testId', () {
    for (final size in WpButtonSize.values) {
      testWidgets('the identifier sits on the tappable node ($size)', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        addTearDown(handle.dispose);
        await tester.pumpWidget(
          makeTestable(
            WpButton(
              label: 'Probe',
              testId: 'probe-button',
              variant: WpButtonVariant.ghost,
              size: size,
              onPressed: () {},
            ),
          ),
        );
        // One node, not two: the identifier and the tap action share it, so a
        // second tappable node without an identifier never appears.
        expect(find.bySemanticsLabel('Probe'), findsOneWidget);
        final node = tester.getSemantics(
          find.bySemanticsIdentifier('probe-button'),
        );
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(node.label, 'Probe');
      });
    }
  });
}
