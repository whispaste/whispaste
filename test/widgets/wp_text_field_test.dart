/// Tests for [WpTextField] — the app's writing surfaces.
///
/// AC1 — every variant renders a field, its placeholder and its own metrics
/// AC2 — the boxed variants carry the DESIGN.md chrome, `bare` carries none
///        at rest
/// AC3 — focus moves the stroke to the accent and nothing else moves — on the
///        boxed variants and on `bare`, which grows the same stroke from none
/// AC4 — light theme resolves light tokens (no dark token leaks across)
/// AC5 — [WpTextField.styleFor] is what the field actually renders with, so a
///        read view can match its edit view exactly
/// AC6 — one type family: no variant asks for monospace
/// AC7 — an external focus node is neither adopted nor disposed
/// AC8 — an accessibility text size does not clip or overflow the `bare`
///        editor surface, nor `heading` in the narrow row it lives in
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

AnimatedContainer _box(WidgetTester tester) => tester.widget<AnimatedContainer>(
  find.descendant(
    of: find.byType(WpTextField),
    matching: find.byType(AnimatedContainer),
  ),
);

/// Fill and radius live here.
BoxDecoration _boxDecoration(WidgetTester tester) =>
    _box(tester).decoration! as BoxDecoration;

/// The stroke, painted *over* the child so it can thicken without shifting
/// layout. `null` on the variant that has no stroke at all.
BoxDecoration? _strokeDecoration(WidgetTester tester) =>
    _box(tester).foregroundDecoration as BoxDecoration?;

TextStyle _renderedStyle(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).style!;

Widget _field({
  required TextEditingController controller,
  required WpTextFieldVariant variant,
  FocusNode? focusNode,
  String? hintText = 'Schreib etwas…',
  String? semanticsLabel,
}) {
  final field = WpTextField(
    controller: controller,
    variant: variant,
    focusNode: focusNode,
    hintText: hintText,
    semanticsLabel: semanticsLabel,
  );
  // `bare` expands into the box it is given — a bounded one is part of its
  // contract, exactly as the Notes panel's `Expanded` provides.
  return variant == WpTextFieldVariant.bare
      ? SizedBox(height: 300, child: field)
      : field;
}

void main() {
  // -------------------------------------------------------------------------
  // AC1 — variants render
  // -------------------------------------------------------------------------
  group('AC1 — variants render', () {
    for (final variant in WpTextFieldVariant.values) {
      testWidgets('$variant renders a TextField with its placeholder', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          makeTestable(_field(controller: controller, variant: variant)),
        );

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Schreib etwas…'), findsOneWidget);
      });
    }

    testWidgets('heading is single-line, the prose variants are not', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpTextFieldVariant.heading),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpTextFieldVariant.passage),
        ),
      );
      expect(tester.widget<TextField>(find.byType(TextField)).maxLines, isNull);
    });

    testWidgets('semanticsLabel names the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            variant: WpTextFieldVariant.passage,
            hintText: null,
            semanticsLabel: 'Transkript bearbeiten',
          ),
        ),
      );

      expect(find.bySemanticsLabel('Transkript bearbeiten'), findsOneWidget);
      handle.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // AC2 — chrome per variant
  // -------------------------------------------------------------------------
  group('AC2 — chrome', () {
    testWidgets('boxed variants: 8 dp radius, 1 dp subtle hairline, filled', (
      tester,
    ) async {
      for (final variant in [
        WpTextFieldVariant.heading,
        WpTextFieldVariant.passage,
      ]) {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          makeTestable(_field(controller: controller, variant: variant)),
        );

        expect(_boxDecoration(tester).color, WpColorsDark.surfaceVariant);
        expect(_boxDecoration(tester).borderRadius, WpRadius.borderSm);

        final stroke = _strokeDecoration(tester)!.border! as Border;
        expect(stroke.top.color, WpColorsDark.borderSubtle);
        expect(stroke.top.width, 1);
      }
    });

    testWidgets('bare at rest: no stroke, square, same writing-surface fill', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpTextFieldVariant.bare),
        ),
      );

      expect(_strokeDecoration(tester), isNull);
      expect(_boxDecoration(tester).borderRadius, BorderRadius.zero);
      // The fill is deliberately shared with the boxed variants: `bare` drops
      // the stroke, not the material.
      expect(_boxDecoration(tester).color, WpColorsDark.surfaceVariant);
    });

    testWidgets('no call site can be handed a contentPadding or a font size', (
      tester,
    ) async {
      // Pinned structurally: the constructor has no such parameters, so this
      // reads as a compile-time guarantee. The runtime half is that the
      // decoration the component builds carries the variant's own inset.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpTextFieldVariant.bare),
        ),
      );

      final decoration = tester
          .widget<TextField>(find.byType(TextField))
          .decoration!;
      expect(decoration.contentPadding, const EdgeInsets.all(WpSpacing.xl));
      expect(decoration.border, InputBorder.none);
      expect(decoration.filled, isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // AC3 — one highlight per state
  // -------------------------------------------------------------------------
  group('AC3 — focus', () {
    testWidgets('boxed: stroke goes accent at 1.5 dp, size unchanged', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            variant: WpTextFieldVariant.passage,
            focusNode: focusNode,
          ),
        ),
      );

      final sizeBefore = tester.getSize(find.byType(WpTextField));
      focusNode.requestFocus();
      await tester.pumpAndSettle();

      final stroke = _strokeDecoration(tester)!.border! as Border;
      expect(stroke.top.color, WpColorsDark.accent);
      expect(stroke.top.width, 1.5);
      // `foregroundDecoration` paints over the child: no reflow mid-edit.
      expect(tester.getSize(find.byType(WpTextField)), sizeBefore);
    });

    testWidgets(
      'bare: the same accent stroke at 1.5 dp, grown from none, size unchanged',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final focusNode = FocusNode();
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          makeTestable(
            _field(
              controller: controller,
              variant: WpTextFieldVariant.bare,
              focusNode: focusNode,
            ),
          ),
        );

        // The variant that owns its surface still shows nothing while idle —
        // the resting half of this is pinned in AC2.
        expect(_strokeDecoration(tester), isNull);
        final sizeBefore = tester.getSize(find.byType(WpTextField));

        focusNode.requestFocus();
        await tester.pumpAndSettle();

        // Same colour, same width, same square corners as at rest: one spec
        // predicate feeds one paint site, so `bare` cannot drift into a focus
        // treatment of its own.
        final stroke = _strokeDecoration(tester)!;
        expect((stroke.border! as Border).top.color, WpColorsDark.accent);
        expect((stroke.border! as Border).top.width, 1.5);
        expect(stroke.borderRadius, BorderRadius.zero);
        // Painted over the child, so a paragraph mid-edit does not reflow.
        expect(tester.getSize(find.byType(WpTextField)), sizeBefore);

        focusNode.unfocus();
        await tester.pumpAndSettle();
        expect(_strokeDecoration(tester), isNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC4 — light theme
  // -------------------------------------------------------------------------
  testWidgets('AC4 — light theme resolves light tokens only', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        _field(
          controller: controller,
          variant: WpTextFieldVariant.passage,
          focusNode: focusNode,
        ),
        brightness: Brightness.light,
      ),
    );

    expect(_boxDecoration(tester).color, WpColorsLight.surfaceVariant);
    expect(_renderedStyle(tester).color, WpColorsLight.textPrimary);
    expect(
      (_strokeDecoration(tester)!.border! as Border).top.color,
      WpColorsLight.borderSubtle,
    );

    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(
      (_strokeDecoration(tester)!.border! as Border).top.color,
      WpColorsLight.accent,
    );
  });

  // -------------------------------------------------------------------------
  // AC5 — read view matches edit view
  // -------------------------------------------------------------------------
  group('AC5 — styleFor', () {
    for (final variant in WpTextFieldVariant.values) {
      testWidgets('$variant renders exactly what styleFor advertises', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          makeTestable(_field(controller: controller, variant: variant)),
        );

        expect(
          _renderedStyle(tester),
          WpTextField.styleFor(variant, color: WpColorsDark.textPrimary),
        );
      });
    }

    test('both prose variants share one text size and line height', () {
      const color = WpColorsDark.textPrimary;
      final passage = WpTextField.styleFor(
        WpTextFieldVariant.passage,
        color: color,
      );
      final bare = WpTextField.styleFor(WpTextFieldVariant.bare, color: color);

      expect(passage.fontSize, bare.fontSize);
      expect(passage.height, bare.height);
      expect(passage.fontWeight, bare.fontWeight);
    });
  });

  // -------------------------------------------------------------------------
  // AC6 — one type family
  // -------------------------------------------------------------------------
  test('AC6 — no variant asks for a second type family', () {
    for (final variant in WpTextFieldVariant.values) {
      expect(
        WpTextField.styleFor(
          variant,
          color: WpColorsDark.textPrimary,
        ).fontFamily,
        isNull,
        reason:
            '$variant overrides the theme font — DESIGN.md knows one family '
            'everywhere, and the transcript\'s monospace was the exception '
            'this component removed.',
      );
    }
  });

  // -------------------------------------------------------------------------
  // AC7 — external focus node
  // -------------------------------------------------------------------------
  testWidgets('AC7 — an external focus node survives the field', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      makeTestable(
        _field(
          controller: controller,
          variant: WpTextFieldVariant.heading,
          focusNode: focusNode,
        ),
      ),
    );
    await tester.pumpWidget(makeTestable(const SizedBox.shrink()));

    // Still usable — the component disposed only what it owned.
    expect(() => focusNode.hasFocus, returnsNormally);
  });

  // -------------------------------------------------------------------------
  // AC8 — accessibility text size
  // -------------------------------------------------------------------------
  testWidgets('AC8 — bare editor survives a 1.5x text scaler without '
      'overflowing', (tester) async {
    final controller = TextEditingController(
      text: List.filled(
        40,
        'Ein diktierter Satz mit reichlich Text.',
      ).join(' '),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: _field(
              controller: controller,
              variant: WpTextFieldVariant.bare,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The field scrolls its own content instead of growing past its box.
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(WpTextField)).height, 300);
  });

  testWidgets('AC8 — heading survives a 1.5x text scaler in a narrow row '
      'without overflowing', (tester) async {
    // The History title sits in a row next to its action buttons, so its box
    // is narrow and it is the one variant that must not grow horizontally:
    // single-line, scrolling its own content.
    final controller = TextEditingController(
      text: 'Ein ziemlich langer Titel, der in kein schmales Feld passt',
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 240,
                child: _field(
                  controller: controller,
                  variant: WpTextFieldVariant.heading,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(WpTextField)).width, 240);
  });
}
