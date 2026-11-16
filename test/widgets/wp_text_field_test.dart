/// Tests for [WpTextField] — behaviour only (a11y label, focus-node
/// ownership, one type family). Chrome, metrics and focus strokes are design
/// and not tested.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/widgets/wp_text_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
  // Removed 2026-08-11 (dark-only build): 'AC4 — light theme resolves light
  // tokens only' pumped the field with Brightness.light and asserted it
  // resolved the light-theme surface/text/border/focus tokens. The app now
  // ships a single dark theme only, so there is no light theme left to
  // resolve.

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

  // AC6 — one type family
  test('AC6 — no variant asks for a second type family', () {
    for (final variant in WpTextFieldVariant.values) {
      expect(
        WpTextField.styleFor(variant, color: WpColors.textPrimary).fontFamily,
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
}
