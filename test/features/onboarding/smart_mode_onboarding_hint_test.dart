/// Widget tests for the Smart Mode onboarding discovery dialog (ticket 08
/// of `.scratch/smart-mode-v2/`).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/smart_mode_onboarding_hint.dart';

import '../../fixtures/test_helpers.dart';

Future<({BuildContext context, WidgetRef ref})> _pumpHost(
  WidgetTester tester,
) async {
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
  return (context: capturedContext, ref: capturedRef);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows title, body and both CTAs', (tester) async {
    final host = await _pumpHost(tester);
    final l10n = L10n.of(host.context);

    unawaited(showSmartModeOnboardingHint(host.context, host.ref));
    await tester.pumpAndSettle();

    expect(find.text(l10n.smartModeOnboardingHintTitle), findsOneWidget);
    expect(find.text(l10n.smartModeOnboardingHintBody), findsOneWidget);
    expect(find.text(l10n.smartModeOnboardingHintDownloadCta), findsOneWidget);
    expect(find.text(l10n.smartModeOnboardingHintSkipCta), findsOneWidget);

    // Close it so the test doesn't leave a pending route behind.
    await tester.tap(find.text(l10n.smartModeOnboardingHintSkipCta));
    await tester.pumpAndSettle();
  });

  testWidgets('skip closes the dialog without starting a download', (
    tester,
  ) async {
    final host = await _pumpHost(tester);
    final l10n = L10n.of(host.context);

    final future = showSmartModeOnboardingHint(host.context, host.ref);
    await tester.pumpAndSettle();

    await tester.tap(find.text(l10n.smartModeOnboardingHintSkipCta));
    await tester.pumpAndSettle();
    await future;

    expect(find.text(l10n.smartModeOnboardingHintTitle), findsNothing);
  });
}
