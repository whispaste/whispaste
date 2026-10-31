/// PAR-056 / R18-2 (a): the double-tap fallback notice names the reason of
/// each OS. macOS: Input Monitoring; Windows: refused key observation; Linux:
/// the session reports no key release. Other systems keep the generic text.
library;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  for (final code in ['de', 'en', 'es', 'pt', 'he', 'ru']) {
    final l10n = lookupL10n(Locale(code));

    test('[$code] each OS has its own settings notice', () {
      final notices = {
        'mac': doubleTapFallbackNotice(l10n, isMacOS: true),
        'windows': doubleTapFallbackNotice(
          l10n,
          isMacOS: false,
          isWindows: true,
          isLinux: false,
        ),
        'linux': doubleTapFallbackNotice(
          l10n,
          isMacOS: false,
          isWindows: false,
          isLinux: true,
        ),
        'other': doubleTapFallbackNotice(
          l10n,
          isMacOS: false,
          isWindows: false,
          isLinux: false,
        ),
      };
      expect(notices['windows'], l10n.settingsDoubleTapFallbackNoticeWindows);
      expect(notices['linux'], l10n.settingsDoubleTapFallbackNoticeLinux);
      expect(notices['other'], l10n.settingsDoubleTapFallbackNotice);
      expect(notices.values.toSet().length, 4, reason: 'four distinct texts');
    });

    test('[$code] onboarding hint follows the same OS split', () {
      expect(
        onboardingDoubleTapFallbackHint(
          l10n,
          isMacOS: false,
          isWindows: true,
          isLinux: false,
        ),
        l10n.onboardingTriggerDoubleTapFallbackHintWindows,
      );
      expect(
        onboardingDoubleTapFallbackHint(
          l10n,
          isMacOS: false,
          isWindows: false,
          isLinux: true,
        ),
        l10n.onboardingTriggerDoubleTapFallbackHintLinux,
      );
    });
  }
}
