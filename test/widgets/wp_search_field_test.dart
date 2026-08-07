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
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/widgets/wp_search_field.dart';

import '../fixtures/test_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// The box the component paints itself — fill/shadow/radius live here.
BoxDecoration _boxDecoration(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byType(WpSearchField),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration
        as BoxDecoration;

/// The border, which is painted *over* the child so it can thicken without
/// shifting layout.
BoxDecoration _borderDecoration(WidgetTester tester) =>
    tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byType(WpSearchField),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .foregroundDecoration
        as BoxDecoration;

Widget _field({
  required TextEditingController controller,
  WpSearchFieldVariant variant = WpSearchFieldVariant.outlined,
  FocusNode? focusNode,
  ValueChanged<String>? onChanged,
  VoidCallback? onClear,
  Widget? suffix,
  String? clearTooltip,
}) => WpSearchField(
  controller: controller,
  hintText: 'Suchen…',
  variant: variant,
  focusNode: focusNode,
  onChanged: onChanged,
  onClear: onClear,
  suffix: suffix,
  clearTooltip: clearTooltip,
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
  // AC4 — the variant carries the whole surface treatment
  // -------------------------------------------------------------------------
  group('AC4 — variant surface treatment', () {
    testWidgets('outlined: sm radius, opaque fill, visible resting hairline', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            variant: WpSearchFieldVariant.outlined,
          ),
        ),
      );

      expect(_boxDecoration(tester).borderRadius, WpRadius.borderSm);
      expect(_boxDecoration(tester).color, WpColorsDark.surfaceVariant);
      expect(_boxDecoration(tester).boxShadow, isNull);
      expect(
        _borderDecoration(tester).border!.top.color,
        WpColorsDark.borderSubtle,
      );
    });

    testWidgets('raised: md radius, shadow instead of a resting stroke', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpSearchFieldVariant.raised),
        ),
      );

      expect(_boxDecoration(tester).borderRadius, WpRadius.borderMd);
      expect(_boxDecoration(tester).boxShadow, WpShadows.subtle);
      // Transparent rather than absent, so focus animates a colour instead of
      // conjuring a border out of nothing.
      expect(_borderDecoration(tester).border!.top.color, Colors.transparent);
    });

    testWidgets('raised: light theme takes the halved light shadow', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpSearchFieldVariant.raised),
          brightness: Brightness.light,
        ),
      );

      // The dark-theme alpha reads as a grey haze over light's pearl
      // surfaces — the same reason the list tiles this field floats above
      // resolve their lift through `subtleFor`.
      expect(_boxDecoration(tester).boxShadow, WpShadows.subtleLight);
    });

    testWidgets('capsule: full radius, translucent fill, hairline', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpSearchFieldVariant.capsule),
        ),
      );

      expect(_boxDecoration(tester).borderRadius, WpRadius.borderFull);
      expect(_boxDecoration(tester).color, WpColorsDark.surfaceMutedFill);
      expect(
        _borderDecoration(tester).border!.top.color,
        WpColorsDark.borderSubtle,
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5 — focus is the border, and only the border
  // -------------------------------------------------------------------------
  group('AC5 — focus', () {
    testWidgets('thickens the border to accent without resizing the field', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            focusNode: node,
            variant: WpSearchFieldVariant.raised,
          ),
        ),
      );

      final restingSize = tester.getSize(find.byType(WpSearchField));
      expect(_borderDecoration(tester).border!.top.width, 1);

      node.requestFocus();
      await tester.pumpAndSettle();

      expect(_borderDecoration(tester).border!.top.color, WpColorsDark.accent);
      expect(_borderDecoration(tester).border!.top.width, 1.5);
      // foregroundDecoration paints over the child rather than insetting it.
      expect(tester.getSize(find.byType(WpSearchField)), restingSize);
    });
  });

  // -------------------------------------------------------------------------
  // AC6 — suffix slot
  // -------------------------------------------------------------------------
  group('AC6 — suffix slot', () {
    testWidgets('renders beside the clear button, not in place of it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'abc');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            suffix: const Icon(LucideIcons.circleHelp),
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.x), findsOneWidget);
      expect(find.byIcon(LucideIcons.circleHelp), findsOneWidget);
      expect(
        tester.getCenter(find.byIcon(LucideIcons.x)).dx,
        lessThan(tester.getCenter(find.byIcon(LucideIcons.circleHelp)).dx),
      );
    });

    testWidgets('survives on its own while the field is empty', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(
            controller: controller,
            suffix: const Icon(LucideIcons.circleHelp),
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.x), findsNothing);
      expect(find.byIcon(LucideIcons.circleHelp), findsOneWidget);
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
  // AC8 — one centre line
  // -------------------------------------------------------------------------
  group('AC8 — vertical rhythm', () {
    testWidgets('the leading icon, the text and the clear button sit on the '
        'same centre line', (tester) async {
      final controller = TextEditingController(text: 'meeting notes');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        makeTestable(
          _field(controller: controller, variant: WpSearchFieldVariant.raised),
        ),
      );

      // The prefix/suffix icon slots hold the box at Material's 48 dp floor,
      // which is taller than the text row's own padded height. Without
      // `textAlignVertical` the input keeps its own top-aligned box and the
      // text rides 4 dp above both icons.
      final field = tester.getRect(find.byType(WpSearchField)).center.dy;
      expect(tester.getRect(find.byIcon(LucideIcons.search)).center.dy, field);
      expect(tester.getRect(find.byIcon(LucideIcons.x)).center.dy, field);
      expect(tester.getRect(find.byType(EditableText)).center.dy, field);
    });
  });
}
