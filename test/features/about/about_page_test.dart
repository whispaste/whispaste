import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/about/about_page.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('AboutPage review & support', () {
    testWidgets('shows always-on "Rate & support WhisPaste" entry plus its '
        'existing GitHub-Stern link — AC2', (tester) async {
      await tester.pumpWidget(
        makeTestable(const AboutPage(), locale: const Locale('en')),
      );
      await tester.pumpAndSettle();

      // The Support section sits near the bottom of the scroll view.
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -1600),
      );
      await tester.pumpAndSettle();

      // Always-on entry is present.
      expect(find.text(l10n.reviewSupportEntry), findsOneWidget);
      // The existing GitHub-Stern link is preserved.
      expect(find.text(l10n.aboutStarOnGitHub), findsOneWidget);
    });
  });
}
