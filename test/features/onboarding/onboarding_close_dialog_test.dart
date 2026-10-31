/// Tests for the first-run close question (Onboarding v6, V08, E4 a+b): the
/// window's X asks "Pause setup or quit WhisPaste?". Without a tray icon,
/// pausing is not offered, because nothing would bring the window back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/onboarding_close_dialog.dart';

import '../../fixtures/test_helpers.dart';

late L10n l10n;

/// The dialog action with [id]: WpButton keys itself from its testId.
Finder _button(String id) => find.byKey(ValueKey<String>(id));

/// Opens the dialog from a button and records the answer.
Future<void> _pumpDialog(
  WidgetTester tester, {
  required bool pauseAvailable,
  required void Function(OnboardingCloseChoice) onAnswer,
}) async {
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async => onAnswer(
              await showOnboardingCloseDialog(
                context: context,
                l10n: L10n.of(context),
                pauseAvailable: pauseAvailable,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('firstRunCanPause', () {
    test('needs a working tray and a tray host', () {
      expect(firstRunCanPause(trayReady: true, trayHostMissing: false), isTrue);
      expect(
        firstRunCanPause(trayReady: true, trayHostMissing: true),
        isFalse,
        reason: 'Linux GNOME without AppIndicator: the icon never shows.',
      );
      expect(
        firstRunCanPause(trayReady: false, trayHostMissing: false),
        isFalse,
      );
      expect(
        firstRunCanPause(trayReady: false, trayHostMissing: true),
        isFalse,
      );
    });
  });

  group('showOnboardingCloseDialog', () {
    testWidgets('offers pause, quit and continue when pausing is possible', (
      tester,
    ) async {
      OnboardingCloseChoice? answer;
      await _pumpDialog(
        tester,
        pauseAvailable: true,
        onAnswer: (c) => answer = c,
      );

      expect(find.text(l10n.onboardingCloseTitle), findsOneWidget);
      expect(find.text(l10n.onboardingCloseBodyPause), findsOneWidget);
      expect(_button('onboarding-close-pause'), findsOneWidget);
      expect(_button('onboarding-close-quit'), findsOneWidget);
      expect(_button('onboarding-close-continue'), findsOneWidget);

      await tester.tap(_button('onboarding-close-pause'));
      await tester.pumpAndSettle();
      expect(answer, OnboardingCloseChoice.pause);
    });

    testWidgets('without a tray only quit and continue are offered', (
      tester,
    ) async {
      await _pumpDialog(tester, pauseAvailable: false, onAnswer: (_) {});

      expect(find.text(l10n.onboardingCloseBodyNoTray), findsOneWidget);
      expect(_button('onboarding-close-pause'), findsNothing);
      expect(_button('onboarding-close-quit'), findsOneWidget);
      expect(_button('onboarding-close-continue'), findsOneWidget);
    });

    testWidgets('quit answers quit', (tester) async {
      OnboardingCloseChoice? answer;
      await _pumpDialog(
        tester,
        pauseAvailable: true,
        onAnswer: (c) => answer = c,
      );

      await tester.tap(_button('onboarding-close-quit'));
      await tester.pumpAndSettle();
      expect(answer, OnboardingCloseChoice.quit);
    });

    testWidgets('continue setup and dismissing both keep the setup open', (
      tester,
    ) async {
      OnboardingCloseChoice? answer;
      await _pumpDialog(
        tester,
        pauseAvailable: true,
        onAnswer: (c) => answer = c,
      );
      await tester.tap(_button('onboarding-close-continue'));
      await tester.pumpAndSettle();
      expect(answer, OnboardingCloseChoice.continueSetup);

      await _pumpDialog(
        tester,
        pauseAvailable: true,
        onAnswer: (c) => answer = c,
      );
      await tester.tapAt(const Offset(5, 5)); // outside the card
      await tester.pumpAndSettle();
      expect(answer, OnboardingCloseChoice.continueSetup);
    });
  });
}
