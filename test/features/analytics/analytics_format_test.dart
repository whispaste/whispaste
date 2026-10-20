// Locale-aware formatting of the analytics money and duration figures
// (UX-004). Costs are summed from per-transcription USD prices, so the
// currency stays USD; only the rendering follows the app locale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/analytics/analytics_page.dart';

void main() {
  group('formatAnalyticsUsd', () {
    test('de: decimal comma and trailing currency symbol', () {
      final text = formatAnalyticsUsd('de', 127.05);
      expect(text, startsWith('127,05'));
      expect(text, endsWith('\$'));
      expect(text, isNot(contains('.')));
    });

    test('en: decimal point and leading symbol', () {
      expect(formatAnalyticsUsd('en', 3.12), r'$3.12');
    });
  });

  group('formatAnalyticsDuration', () {
    test('de: decimal hours with Std., minutes below one hour', () {
      final l10n = lookupL10n(const Locale('de'));
      expect(formatAnalyticsDuration(l10n, 'de', 7 * 60 + 30), '7,5 Std.');
      expect(formatAnalyticsDuration(l10n, 'de', 45), '45 Min.');
    });

    test('en: decimal point and h / min', () {
      final l10n = lookupL10n(const Locale('en'));
      expect(formatAnalyticsDuration(l10n, 'en', 7 * 60 + 30), '7.5 h');
      expect(formatAnalyticsDuration(l10n, 'en', 45), '45 min');
    });
  });
}
