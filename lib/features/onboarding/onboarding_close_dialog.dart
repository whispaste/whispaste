/// What the window's close button does during the first run (Onboarding v6,
/// V08, decision E4 a+b): the setup can be paused or the app can quit. A
/// paused setup keeps WhisPaste in the tray or the macOS menu bar, where the
/// tray entry "Resume setup" brings the window back on the saved page.
library;

import 'package:flutter/widgets.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../widgets/dialog.dart';

/// The three answers to the first-run close question.
enum OnboardingCloseChoice { pause, quit, continueSetup }

/// Whether the first-run setup may be paused. Pausing hides the window, so
/// there must be a tray icon (or the menu bar item on macOS) to come back
/// from. A tray that initialised but has no host (Linux GNOME without the
/// AppIndicator extension) shows nothing, so it counts as no tray.
bool firstRunCanPause({
  required bool trayReady,
  required bool trayHostMissing,
}) => trayReady && !trayHostMissing;

/// Asks "Pause setup or quit WhisPaste?" when the window closes during the
/// first run. Without a tray only "Quit" and "Continue setup" are offered.
/// "Continue setup" is the recommended answer (Enter); quitting is a quiet
/// red label at the bottom, never beside it. Esc and a tap outside also mean
/// "Continue setup".
Future<OnboardingCloseChoice> showOnboardingCloseDialog({
  required BuildContext context,
  required L10n l10n,
  required bool pauseAvailable,
}) => showWpChoiceDialog<OnboardingCloseChoice>(
  context: context,
  title: l10n.onboardingCloseTitle,
  cardKey: const ValueKey('onboarding-close-dialog'),
  body: pauseAvailable
      ? l10n.onboardingCloseBodyPause
      : l10n.onboardingCloseBodyNoTray,
  cta: WpDialogCta.hero,
  dismissValue: OnboardingCloseChoice.continueSetup,
  choices: [
    WpDialogAction(
      label: l10n.onboardingCloseContinue,
      testId: 'onboarding-close-continue',
      role: WpDialogActionRole.primary,
      value: OnboardingCloseChoice.continueSetup,
    ),
    if (pauseAvailable)
      WpDialogAction(
        label: l10n.onboardingClosePause,
        testId: 'onboarding-close-pause',
        value: OnboardingCloseChoice.pause,
      ),
    WpDialogAction(
      label: l10n.trayQuit,
      testId: 'onboarding-close-quit',
      role: WpDialogActionRole.destructiveExit,
      value: OnboardingCloseChoice.quit,
    ),
  ],
);
