import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The coffee buttons (Ko-fi, Buy Me a Coffee) exist only in direct builds.
/// Store builds get the store's own tip or nothing (support_capabilities.dart,
/// coffeeSupportTarget). The handbook paragraph must say so in every app
/// language, not promise the buttons for every build (PAR-043).
void main() {
  test('the coffee paragraph separates direct downloads from store builds', () {
    for (final lang in ['de', 'en', 'es', 'he', 'pt', 'ru']) {
      final arb =
          jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
              as Map<String, dynamic>;
      final text = arb['manualC16S2B2'] as String? ?? '';
      expect(text, contains('{k1}'), reason: '$lang placeholder');
      expect(text, contains('Ko-fi'), reason: '$lang Ko-fi named');
      expect(
        text,
        contains('Store'),
        reason: '$lang must name the store builds that get no external links',
      );
    }
  });
}
