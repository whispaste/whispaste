// Guard for the screenshot generators (#1988): a screen framed by the shared
// UX fixtures must leave no timer behind once the tree is gone. The test
// binding fails the test on a pending timer ("A Timer is still pending"),
// which turned every capture of the support page and the overview red,
// although the PNGs were fine. Real errors got lost among them.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/help/support_page.dart';
import 'package:whispaste/features/overview/overview_page.dart';
import 'package:whispaste/services/social_stats/social_stats_service.dart';

import 'ux_fixtures.dart';

/// Frames [screen], unmounts it and expects a clean teardown. The binding's
/// own pending-timer check at the end of the test is the main guard; the
/// expectations here make a failed capture visible before it.
Future<void> _expectCleanUnmount(WidgetTester tester, UxScreen screen) async {
  final db = await openSeededUxDatabase(tester);
  addTearDown(() => tester.runAsync(db.close));
  await pumpUxScreen(
    tester,
    screen: screen,
    db: db,
    size: kUxSize1100,
    scale: 1,
    theme: 'navy',
    locale: 'de',
  );
  // Deliberately no drain after the unmount: the generators end the same way.
  await tester.pumpWidget(const SizedBox());
  expect(find.byKey(const ValueKey(kUxCaptureKey)), findsNothing);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('the support page asks no server and leaves no timer', (
    tester,
  ) async {
    await _expectCleanUnmount(
      tester,
      UxScreen(
        id: 'support',
        activePageId: 'help',
        build: () => const SupportPage(),
      ),
    );
  });

  testWidgets('the framed screens never fetch community numbers online', (
    tester,
  ) async {
    final db = await openSeededUxDatabase(tester);
    addTearDown(() => tester.runAsync(db.close));
    await pumpUxBody(
      tester,
      body: const SizedBox(),
      db: db,
      size: kUxSize1100,
      theme: 'navy',
      locale: 'de',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey(kUxCaptureKey))),
    );
    expect(
      container.read(socialStatsFetcherProvider),
      isA<UxOfflineSocialStatsFetcher>(),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the overview closes its database streams on unmount', (
    tester,
  ) async {
    await _expectCleanUnmount(
      tester,
      UxScreen(
        id: 'overview',
        activePageId: 'overview',
        build: () => const OverviewPage(),
      ),
    );
  });
}
