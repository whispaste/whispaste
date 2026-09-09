/// Golden test for the Smart Mode onboarding hint's before/after example
/// (ticket 14, `.scratch/smart-mode-v2/issues/14-onboarding-example.md`).
///
/// The existing widget test (`smart_mode_onboarding_hint_test.dart`) already
/// covers behaviour — title/body/CTAs, skip closing the dialog — but none of
/// that catches a *visual* regression in the example card itself (wrong
/// emphasis, a row silently disappearing, a color token pointing at the
/// wrong surface). This is a picture of exactly that card.
@Tags(<String>['golden'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/smart_mode_onboarding_hint.dart';

import '../../fixtures/test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('before/after example card, dark', (tester) async {
    late BuildContext capturedContext;
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      makeTestable(
        Consumer(
          builder: (context, ref, _) {
            capturedContext = context;
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(showSmartModeOnboardingHint(capturedContext, capturedRef));
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(smartModeOnboardingHintExampleKey),
      matchesGoldenFile('goldens/smart_mode_onboarding_hint_example_dark.png'),
    );

    // Close it so the test doesn't leave a pending route behind.
    final l10n = L10n.of(capturedContext);
    await tester.tap(find.text(l10n.smartModeOnboardingHintSkipCta));
    await tester.pumpAndSettle();
  });
}
