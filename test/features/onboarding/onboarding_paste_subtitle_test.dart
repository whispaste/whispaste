import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

/// The Auto-Paste page subtitle is chosen per platform. Linux has no system
/// permission dialog, so it must not show the macOS text ("macOS fragt dich
/// gleich …"), which told the user to answer a prompt that never comes.
void main() {
  final en = lookupL10n(const Locale('en'));
  final de = lookupL10n(const Locale('de'));

  test('Linux shows its own subtitle, not the macOS text', () {
    final text = onboardingPasteSubtitleFor(en, TargetPlatform.linux);
    expect(text, en.onboardingPasteSubtitleLinux);
    expect(text, isNot(en.onboardingPasteSubtitle));
    expect(text, isNot(en.onboardingPasteSubtitleWin));
  });

  test('macOS keeps the macOS subtitle', () {
    expect(
      onboardingPasteSubtitleFor(de, TargetPlatform.macOS),
      de.onboardingPasteSubtitle,
    );
  });

  test('Windows keeps the Windows subtitle', () {
    expect(
      onboardingPasteSubtitleFor(de, TargetPlatform.windows),
      de.onboardingPasteSubtitleWin,
    );
  });

  test('the Linux subtitle names no other platform in any app language', () {
    for (final code in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
      final l10n = lookupL10n(Locale(code));
      final text = l10n.onboardingPasteSubtitleLinux;
      expect(text.trim(), isNotEmpty, reason: 'app_$code.arb');
      expect(text, isNot(contains('macOS')), reason: 'app_$code.arb');
      expect(text, isNot(contains('Windows')), reason: 'app_$code.arb');
    }
  });
}
