/// Pins the settings search-hit highlight as a *painted* ring, not a laid-out
/// one.
///
/// The ring is transient: selecting a search suggestion sets
/// [settingsHighlightTargetProvider], and the page clears it again 1.5 s
/// later. While it was a `Border` inside `AnimatedContainer.decoration`, the
/// container inset its child by the 2 px border width — so the section the
/// user had just been sent to jumped 2 px inward on arrival and 2 px back out
/// on expiry, twice per search, at the exact moment they were trying to read
/// it. `foregroundDecoration` paints the same ring over the child at zero
/// layout cost.
///
/// The geometry assertion alone would also pass if the ring stopped rendering
/// altogether, so this file checks both halves: the ring is really there, and
/// it costs nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/settings/sections/interface_section.dart';
import 'package:whispaste/features/settings/settings_page.dart';

import '../../fixtures/test_helpers.dart';

/// The `AnimatedContainer` the page wraps around one section for its
/// highlight ring.
Finder _highlightBoxOf(Finder section) =>
    find.ancestor(of: section, matching: find.byType(AnimatedContainer)).first;

void main() {
  group('settings search highlight', () {
    testWidgets('does not move the section it highlights', (tester) async {
      await tester.pumpWidget(
        makeTestable(const SettingsPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      final section = find.byType(InterfaceSection);
      expect(section, findsOneWidget);

      final before = tester.getRect(section);
      final borderAtRest =
          (tester.widget<AnimatedContainer>(_highlightBoxOf(section)).decoration
                  as BoxDecoration?)
              ?.border;

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsPage)),
      );
      container.read(settingsHighlightTargetProvider.notifier).set('interface');

      // Past the 200 ms highlight animation, well short of the 1.5 s clear.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        tester.getRect(section),
        before,
        reason:
            'the highlight ring must not be laid out — a Border in '
            '`decoration` insets the child by its width and shifts the '
            'section the user was just sent to',
      );

      // The ring is genuinely on screen, so the geometry check above is not
      // passing on an invisible highlight.
      final highlighted = tester.widget<AnimatedContainer>(
        _highlightBoxOf(section),
      );
      expect(
        highlighted.foregroundDecoration,
        isA<BoxDecoration>().having((d) => d.border, 'border', isNotNull),
        reason: 'the highlight ring belongs in the foreground decoration',
      );
      // The background decoration is not empty any more — Ticket 14 put the
      // section on the card material, and a card's rim is a `Border` there by
      // definition. What matters is that it does not *change*: a constant
      // border costs its inset once, at every moment, which is exactly the
      // layout the section already had. The ring must add nothing to it.
      expect(
        (highlighted.decoration as BoxDecoration?)?.border,
        borderAtRest,
        reason:
            'the background decoration changed when the ring arrived — that '
            'is the layer that costs layout, so anything that moves in it '
            'moves the section with it',
      );

      // …and back out again when the page clears the target 1.5 s later.
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(
        tester.getRect(section),
        before,
        reason: 'the section must also hold still when the ring expires',
      );
    });
  });
}
