/// Tests for [WpButton] — the app's single push-button.
///
/// AC1 — every variant renders its Material carrier and its label
/// AC2 — `onPressed: null` disables the button and swallows taps
/// AC3 — `isLoading` swaps the icon for a spinner and disables the button
/// AC4 — `tone: danger` resolves to the shared error tint tokens
/// AC5 — `dense` is visually shorter than `standard`
/// AC6 — `disabledTooltip` appears only while the button is disabled
/// AC7 — the filled variant rings in a colour its fill can't swallow
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_button.dart';
import 'package:whispaste/widgets/wp_focus_ring.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The button's *visual* box — the `Material` inside Material's own button,
/// i.e. below the invisible tap-target padding a standard button carries.
double _visualHeight(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(WpButton),
            matching: find.byType(Material),
          )
          .first,
    )
    .height;

void main() {
  // -------------------------------------------------------------------------
  // AC1 — variants
  // -------------------------------------------------------------------------
  group('AC1 — variants', () {
    testWidgets('primary renders a FilledButton with its label', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Speichern',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
          ),
        ),
      );

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);
    });

    testWidgets('secondary renders an OutlinedButton', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Abbrechen',
            variant: WpButtonVariant.secondary,
            onPressed: _noop,
          ),
        ),
      );

      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text('Abbrechen'), findsOneWidget);
    });

    testWidgets('ghost renders a TextButton', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Später',
            variant: WpButtonVariant.ghost,
            onPressed: _noop,
          ),
        ),
      );

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.text('Später'), findsOneWidget);
    });

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

    testWidgets('disabled uses the muted token, not a dimmed live colour', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Gesperrt',
            variant: WpButtonVariant.primary,
            onPressed: null,
          ),
        ),
      );

      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;

      expect(style.foregroundColor!.resolve(const {}), WpColorsDark.textMuted);
      expect(
        style.backgroundColor!.resolve(const {}),
        WpColorsDark.surfaceVariant,
      );
    });

    testWidgets(
      'disabled primary borrows the secondary outline — its fill alone is '
      'near-invisible on surfaceVariant-tinted cards',
      (tester) async {
        await tester.pumpWidget(
          makeTestable(
            const WpButton(
              label: 'Gesperrt',
              variant: WpButtonVariant.primary,
              onPressed: null,
            ),
          ),
        );

        final style = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!;

        expect(style.side!.resolve(const {})!.color, WpColorsDark.borderSubtle);
      },
    );

    testWidgets('enabled primary has no outline at all', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Los',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
          ),
        ),
      );

      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;

      expect(style.side, isNull);
    });

    testWidgets('disabled ghost stays borderless — it has no silhouette to '
        'lose', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Gesperrt',
            variant: WpButtonVariant.ghost,
            onPressed: null,
          ),
        ),
      );

      final style = tester.widget<TextButton>(find.byType(TextButton)).style!;

      expect(style.side, isNull);
    });

    testWidgets('light theme resolves its own disabled-primary outline', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Gesperrt',
            variant: WpButtonVariant.primary,
            onPressed: null,
          ),
          brightness: Brightness.light,
        ),
      );

      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;

      expect(style.side!.resolve(const {})!.color, WpColorsLight.borderSubtle);
    });
  });

  // -------------------------------------------------------------------------
  // AC3 — loading
  // -------------------------------------------------------------------------
  group('AC3 — isLoading', () {
    testWidgets('replaces the icon with a spinner', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Sende',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
            icon: LucideIcons.send,
            isLoading: true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(LucideIcons.send), findsNothing);
    });

    testWidgets('shows the icon again once loading ends', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Sende',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
            icon: LucideIcons.send,
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.send), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

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
  // AC4 — danger tone
  // -------------------------------------------------------------------------
  group('AC4 — tone: danger', () {
    testWidgets('secondary outlines with the shared error border token', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Zurücksetzen',
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.danger,
            onPressed: _noop,
          ),
        ),
      );

      final style = tester
          .widget<OutlinedButton>(find.byType(OutlinedButton))
          .style!;

      expect(style.foregroundColor!.resolve(const {}), WpColorsDark.error);
      expect(style.side!.resolve(const {})!.color, WpColorsDark.errorBorder30);
    });

    testWidgets('primary fills with the error token', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Löschen',
            variant: WpButtonVariant.primary,
            tone: WpButtonTone.danger,
            onPressed: _noop,
          ),
        ),
      );

      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;

      expect(style.backgroundColor!.resolve(const {}), WpColorsDark.error);
    });

    testWidgets('light theme resolves its own error tokens', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Zurücksetzen',
            variant: WpButtonVariant.secondary,
            tone: WpButtonTone.danger,
            onPressed: _noop,
          ),
          brightness: Brightness.light,
        ),
      );

      final style = tester
          .widget<OutlinedButton>(find.byType(OutlinedButton))
          .style!;

      expect(style.side!.resolve(const {})!.color, WpColorsLight.errorBorder30);
    });
  });

  // -------------------------------------------------------------------------
  // AC5 — sizes
  // -------------------------------------------------------------------------
  group('AC5 — size', () {
    testWidgets('dense is visually shorter than standard', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Aktion',
            variant: WpButtonVariant.secondary,
            onPressed: _noop,
          ),
        ),
      );
      final standardHeight = _visualHeight(tester);

      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Aktion',
            variant: WpButtonVariant.secondary,
            size: WpButtonSize.dense,
            onPressed: _noop,
          ),
        ),
      );
      final denseHeight = _visualHeight(tester);

      expect(standardHeight, 40);
      expect(denseHeight, 32);
      expect(denseHeight, lessThan(standardHeight));
    });
  });

  // -------------------------------------------------------------------------
  // Label layout — the migration will put these into Rows everywhere
  // -------------------------------------------------------------------------
  group('label layout', () {
    testWidgets('lays out inside a Row that hands down unbounded width', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const Row(
            children: [
              WpButton(
                label: 'Ein außergewöhnlich langer Aktionstext',
                variant: WpButtonVariant.secondary,
                onPressed: _noop,
              ),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('ellipsizes instead of wrapping when width is constrained', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          const SizedBox(
            width: 160,
            child: WpButton(
              label: 'Ein außergewöhnlich langer Aktionstext',
              variant: WpButtonVariant.primary,
              onPressed: _noop,
              expanded: true,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final text = tester.widget<Text>(
        find.descendant(of: find.byType(WpButton), matching: find.byType(Text)),
      );
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
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

  // -------------------------------------------------------------------------
  // AC7 — focus ring on a filled button
  // -------------------------------------------------------------------------
  group('AC7 — focus ring', () {
    Color? ringColorOf(WidgetTester tester) =>
        tester.widget<WpFocusRing>(find.byType(WpFocusRing)).ringColor;

    testWidgets('primary overrides the ring away from every tone fill', (
      tester,
    ) async {
      for (final tone in WpButtonTone.values) {
        await tester.pumpWidget(
          makeTestable(
            WpButton(
              label: 'Aktion',
              variant: WpButtonVariant.primary,
              tone: tone,
              onPressed: _noop,
            ),
          ),
        );

        final fill = tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style!
            .backgroundColor!
            .resolve(const {});

        expect(
          ringColorOf(tester),
          WpColorsDark.textPrimary,
          reason: 'a filled button rings in textPrimary, not in its tone',
        );
        expect(
          ringColorOf(tester),
          isNot(fill),
          reason: 'ring and fill must never be the same colour ($tone)',
        );
      }
    });

    testWidgets('light theme resolves its own ring colour', (tester) async {
      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Aktion',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
          ),
          brightness: Brightness.light,
        ),
      );

      expect(ringColorOf(tester), WpColorsLight.textPrimary);
    });

    testWidgets('unfilled variants keep the shared accent ring', (
      tester,
    ) async {
      for (final variant in [
        WpButtonVariant.secondary,
        WpButtonVariant.ghost,
      ]) {
        await tester.pumpWidget(
          makeTestable(
            WpButton(label: 'Aktion', variant: variant, onPressed: _noop),
          ),
        );

        expect(
          ringColorOf(tester),
          isNull,
          reason: '$variant must not override WpFocusRing\'s accent default',
        );
      }
    });

    testWidgets('the painted ring uses the override, not the accent', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );

      await tester.pumpWidget(
        makeTestable(
          const WpButton(
            label: 'Aktion',
            variant: WpButtonVariant.primary,
            onPressed: _noop,
            autofocus: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final painter = tester
          .widget<CustomPaint>(
            find
                .descendant(
                  of: find.byType(WpFocusRing),
                  matching: find.byType(CustomPaint),
                )
                .first,
          )
          .foregroundPainter;

      expect(painter, isA<WpFocusRingPainter>());
      expect(
        (painter! as WpFocusRingPainter).color,
        WpColorsDark.textPrimary,
        reason: 'AC7: the focused filled button paints the override colour',
      );
    });
  });
}

/// Const-friendly stand-in for "enabled" where the test doesn't count taps.
void _noop() {}
