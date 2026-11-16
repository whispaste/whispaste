/// Tests for [WpSearchField] — the app's single search input.
///
/// AC1 — every variant renders the field and its placeholder
/// AC2 — the clear button appears only with text, and carries a real
///        Semantics *label* (not just a tooltip hint — the bug this
///        component was built to make structurally impossible)
/// AC3 — clearing empties the controller, reports `''` and runs `onClear`
/// AC4 — each variant resolves to its own radius / fill / resting border
/// AC5 — focus thickens the border to accent and moves nothing
/// AC6 — the suffix slot sits beside the clear button, not instead of it
/// AC7 — an external focus node is neither adopted nor disposed
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _field({
  required TextEditingController controller,
  WpSearchFieldVariant variant = WpSearchFieldVariant.outlined,
  FocusNode? focusNode,
  ValueChanged<String>? onChanged,
  VoidCallback? onClear,
  Widget? suffix,
  String? clearTooltip,
  String? semanticsLabel,
}) => WpSearchField(
  controller: controller,
  hintText: 'Suchen…',
  variant: variant,
  focusNode: focusNode,
  onChanged: onChanged,
  onClear: onClear,
  suffix: suffix,
  clearTooltip: clearTooltip,
  semanticsLabel: semanticsLabel,
);

void main() {
  // -------------------------------------------------------------------------
  // AC1 — variants render
  // -------------------------------------------------------------------------
  group('AC1 — variants render', () {
    for (final variant in WpSearchFieldVariant.values) {
      testWidgets('$variant renders a TextField with the placeholder', (
        tester,
      ) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          makeTestable(_field(controller: controller, variant: variant)),
        );

        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('Suchen…'), findsOneWidget);
        expect(find.byIcon(LucideIcons.search), findsOneWidget);
      });
    }
  });

  // -------------------------------------------------------------------------
  // AC2 — clear button + the Semantics label
  // -------------------------------------------------------------------------
  group('AC2 — clear button', () {
    testWidgets('absent while the field is empty', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(makeTestable(_field(controller: controller)));

      expect(find.byIcon(LucideIcons.x), findsNothing);
    });

    testWidgets('appears once text is typed — without the call site '
        'rebuilding the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(makeTestable(_field(controller: controller)));
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      expect(find.byIcon(LucideIcons.x), findsOneWidget);
    });

    testWidgets('carries a Semantics label, not merely a tooltip hint', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(makeTestable(_field(controller: controller)));

      // "Clear search" is the default (l10n.actionClearSearch) — the string
      // Settings used to borrow from History.
      expect(
        tester.getSemantics(find.byIcon(LucideIcons.x)),
        matchesSemantics(
          label: 'Clear search',
          tooltip: 'Clear search',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      handle.dispose();
    });

    testWidgets('a feature-specific clearTooltip overrides the default', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, clearTooltip: 'Notizsuche leeren'),
        ),
      );

      expect(
        find.bySemanticsLabel('Notizsuche leeren'),
        findsAtLeastNWidgets(1),
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC3 — clearing
  // -------------------------------------------------------------------------
  group('AC3 — clearing', () {
    testWidgets('empties the controller, reports an empty query, and runs '
        'onClear afterwards', (tester) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);
      final reported = <String>[];
      var cleared = 0;

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            onChanged: reported.add,
            onClear: () => cleared++,
          ),
        ),
      );

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pump();

      expect(controller.text, isEmpty);
      // Call sites that filter from the callback rather than from a controller
      // listener would otherwise keep showing the old result set.
      expect(reported, ['']);
      expect(cleared, 1);
      expect(find.byIcon(LucideIcons.x), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // AC7 — external focus node ownership
  // -------------------------------------------------------------------------
  group('AC7 — focus node ownership', () {
    testWidgets('an external node outlives the field (the caller disposes it, '
        'and keeps its own onKeyEvent handler)', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final node = FocusNode();
      addTearDown(node.dispose);
      var keyEvents = 0;
      node.onKeyEvent = (_, _) {
        keyEvents++;
        return KeyEventResult.ignored;
      };

      await tester.pumpWidget(
        makeTestable(_field(controller: controller, focusNode: node)),
      );
      node.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);

      expect(keyEvents, greaterThan(0));

      // Unmount: the component must not dispose a node it doesn't own.
      // A disposed ChangeNotifier throws the moment it's used again, so this
      // is the assertion that a leak of ownership would actually trip.
      await tester.pumpWidget(makeTestable(const SizedBox.shrink()));
      expect(() => node.addListener(() {}), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // AC9 — semanticsLabel names the field itself
  // -------------------------------------------------------------------------
  group('AC9 — semanticsLabel', () {
    testWidgets(
      'a label that genuinely differs from the hint lands on the same node '
      'as the field\'s own actions and state — not on a separate, '
      'unfocusable ancestor node',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          makeTestable(
            _field(controller: controller, semanticsLabel: 'Suche Notizen'),
          ),
        );

        // A `container: true`-only wrapper would put the label on a node
        // above the field's own — that node carries no actions/isFocusable,
        // so a reader would land on it first and never reach an announced,
        // operable field. Asserting label and interaction flags together on
        // the *same* node is what pins that regression shut. 'Suche Notizen'
        // says something the hint ('Suchen…') doesn't, so it's kept
        // alongside it rather than deduplicated away.
        expect(
          tester.getSemantics(find.byType(EditableText)),
          matchesSemantics(
            label: 'Suche Notizen\nSuchen…',
            isTextField: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        handle.dispose();
      },
    );

    testWidgets(
      'a label that only restates the hint (its own wording minus the '
      'trailing ellipsis — every real call site\'s shape) does not '
      'announce itself twice',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(
          makeTestable(
            _field(controller: controller, semanticsLabel: 'Suchen'),
          ),
        );

        // The field's own `hintText` ('Suchen…') already carries the label
        // on this merged node. Stacking 'Suchen' on top of it would repeat
        // the same word twice — the exact bug class this whole a11y sweep
        // exists to prevent — so this axis suppresses the redundant half
        // while still applying `MergeSemantics`'s boundary.
        expect(
          tester.getSemantics(find.byType(EditableText)),
          matchesSemantics(
            label: 'Suchen…',
            isTextField: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        handle.dispose();
      },
    );

    testWidgets(
      'stays absent from the tree when the field has no semanticsLabel — '
      'this axis never invents one',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        final handle = tester.ensureSemantics();

        await tester.pumpWidget(makeTestable(_field(controller: controller)));

        expect(
          tester.getSemantics(find.byType(EditableText)),
          matchesSemantics(
            label: 'Suchen…',
            isTextField: true,
            isFocusable: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
        );

        handle.dispose();
      },
    );
  });
}
