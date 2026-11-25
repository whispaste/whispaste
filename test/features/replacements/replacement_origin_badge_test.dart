// #1969: only learned and imported entries carry an origin badge. A typed
// entry has none; "Manual" on nearly every row told the user nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/replacements/replacements_page.dart';

import '../../fixtures/test_helpers.dart';

class _ThreeOrigins extends ReplacementsNotifier {
  @override
  Future<List<Replacement>> build() async => [
    for (final origin in ['manual', 'learned', 'imported'])
      Replacement(
        id: origin,
        createdAt: DateTime(2026, 11, 19),
        triggers: ['$origin trigger'],
        replacement: origin,
        origin: origin,
      ),
  ];
}

void main() {
  testWidgets('a typed entry has no origin badge', (tester) async {
    await tester.pumpWidget(
      makeTestable(
        const ReplacementsPage(),
        locale: const Locale('en'),
        overrides: [replacementsProvider.overrideWith(_ThreeOrigins.new)],
      ),
    );
    await tester.pumpAndSettle();

    Finder badge(String id) =>
        find.byKey(ValueKey('replacements-row-$id-origin'));
    expect(find.byKey(const ValueKey('replacements-row-manual')), findsOne);
    expect(badge('manual'), findsNothing);
    expect(badge('learned'), findsOneWidget);
    expect(badge('imported'), findsOneWidget);
  });
}
