/// Widget tests for the sponsor chip in the status bar: its two looks, its
/// tap target, and the hide menu that exists only once hiding is allowed.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/status_bar.dart';

import '../fixtures/test_helpers.dart';

Widget _bar({
  WpSupportChipMode? mode,
  VoidCallback? onTap,
  VoidCallback? onHide,
}) => makeTestable(
  Column(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      WpStatusBar(
        sttModeLabel: 'On device',
        supportChipMode: mode,
        onSupportTap: onTap,
        onSupportHide: onHide,
      ),
    ],
  ),
  locale: const Locale('en'),
);

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  testWidgets('hidden when no mode is given', (tester) async {
    await tester.pumpWidget(_bar());
    await tester.pump();

    expect(find.byKey(const ValueKey('status-bar-sponsor-chip')), findsNothing);
  });

  testWidgets('sponsor mode shows the heart and the Sponsor label', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.sponsor));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('status-bar-sponsor-chip')),
      findsOneWidget,
    );
    expect(find.text(l10n.supportChipLabel), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('thanks mode shows the thank-you label', (tester) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.thanks));
    await tester.pump();

    expect(find.text(l10n.supportChipThanksLabel), findsOneWidget);
    expect(find.text(l10n.supportChipLabel), findsNothing);
  });

  testWidgets('tap forwards to onSupportTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _bar(mode: WpSupportChipMode.sponsor, onTap: () => taps++),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('status-bar-sponsor-chip')));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('right click offers Hide only when hiding is allowed', (
    tester,
  ) async {
    await tester.pumpWidget(_bar(mode: WpSupportChipMode.thanks));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('status-bar-sponsor-chip')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('status-bar-sponsor-chip-hide')),
      findsNothing,
    );
  });

  testWidgets('right click with hiding allowed calls onSupportHide', (
    tester,
  ) async {
    var hides = 0;
    await tester.pumpWidget(
      _bar(mode: WpSupportChipMode.thanks, onHide: () => hides++),
    );
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey('status-bar-sponsor-chip')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('status-bar-sponsor-chip-hide')),
    );
    await tester.pumpAndSettle();
    expect(hides, 1);
  });
}
