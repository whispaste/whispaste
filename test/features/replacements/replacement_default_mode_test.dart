// UX-124: a new entry's match mode does not follow every keystroke in the
// trigger field. The default (newEntryMatch) is settled once the trigger
// field is left, and a hint says why the entry starts as Similar.
// UX-125: the list marks Similar entries.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';
import 'package:whispaste/services/replacements/text_replacement_matcher.dart';
import 'package:whispaste/widgets/wp_segmented_selector.dart';

import '../../fixtures/test_helpers.dart';

class _TwoEntries extends ReplacementsNotifier {
  @override
  Future<List<Replacement>> build() async => [
    Replacement(
      id: 'exact',
      createdAt: DateTime(2026, 10, 31),
      triggers: const ['omw'],
      replacement: 'on my way',
    ),
    Replacement(
      id: 'similar',
      createdAt: DateTime(2026, 10, 31),
      triggers: const ['kubernetes'],
      replacement: 'Kubernetes',
      matchMode: TextReplacementMatchMode.fuzzy,
      fuzzyThreshold: fuzzyThresholdStrict,
    ),
  ];
}

void main() {
  const modeKey = ValueKey('replacements-match-mode-choice');
  const hintKey = ValueKey('replacements-similar-default-hint');
  const triggerKey = ValueKey('replacements-trigger-field-0');
  const replacementKey = ValueKey('replacements-replacement-field');

  TextReplacementMatchMode selectedMode(WidgetTester tester) => tester
      .widget<WpSegmentedChoice<TextReplacementMatchMode>>(find.byKey(modeKey))
      .selected;

  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      makeTestable(const ReplacementsPage(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pumpAndSettle();
  }

  Future<void> typeTrigger(WidgetTester tester, String text) async {
    await tester.tap(find.byKey(triggerKey));
    await tester.enterText(find.byKey(triggerKey), text);
    await tester.pumpAndSettle();
  }

  Future<void> leaveTrigger(WidgetTester tester) async {
    await tester.tap(find.byKey(replacementKey));
    await tester.pumpAndSettle();
  }

  testWidgets('typing a long trigger does not switch the mode', (tester) async {
    await openAddDialog(tester);
    await typeTrigger(tester, 'kub');
    await typeTrigger(tester, 'kubernetes');

    expect(selectedMode(tester), TextReplacementMatchMode.exact);
    expect(find.byKey(hintKey), findsNothing);
  });

  testWidgets('leaving the trigger settles Similar and says so', (
    tester,
  ) async {
    await openAddDialog(tester);
    await typeTrigger(tester, 'kubernetes');
    await leaveTrigger(tester);

    expect(selectedMode(tester), TextReplacementMatchMode.fuzzy);
    expect(find.byKey(hintKey), findsOneWidget);

    // Editing the trigger afterwards keeps the settled mode.
    await typeTrigger(tester, 'kubernetes cluster');
    expect(selectedMode(tester), TextReplacementMatchMode.fuzzy);
  });

  testWidgets('a short trigger settles Exact, without the hint', (
    tester,
  ) async {
    await openAddDialog(tester);
    await typeTrigger(tester, 'omw');
    await leaveTrigger(tester);

    expect(selectedMode(tester), TextReplacementMatchMode.exact);
    expect(find.byKey(hintKey), findsNothing);
  });

  testWidgets('a mode the user picked is kept and drops the hint', (
    tester,
  ) async {
    await openAddDialog(tester);
    await typeTrigger(tester, 'kubernetes');
    await leaveTrigger(tester);
    // The segment has no per-option id; pick through its callback.
    tester
        .widget<WpSegmentedChoice<TextReplacementMatchMode>>(
          find.byKey(modeKey),
        )
        .onChanged(TextReplacementMatchMode.exact);
    await tester.pumpAndSettle();

    expect(selectedMode(tester), TextReplacementMatchMode.exact);
    expect(find.byKey(hintKey), findsNothing);
  });

  testWidgets('the list marks Similar entries only', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const ReplacementsPage(),
        locale: const Locale('en'),
        overrides: [replacementsProvider.overrideWith(_TwoEntries.new)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('replacements-row-similar')), findsOne);
    expect(
      find.byKey(const ValueKey('replacements-row-similar-similar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('replacements-row-exact-similar')),
      findsNothing,
    );
  });
}
