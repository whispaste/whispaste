import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Onboarding ARB key parity', () {
    late Map<String, dynamic> arbEn;
    late Map<String, dynamic> arbDe;
    late Map<String, dynamic> arbHe;

    setUpAll(() {
      Map<String, dynamic> loadArb(String path) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist');
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }

      arbEn = loadArb('lib/core/l10n/app_en.arb');
      arbDe = loadArb('lib/core/l10n/app_de.arb');
      arbHe = loadArb('lib/core/l10n/app_he.arb');
    });

    test('every onboarding* key in app_en.arb exists and is non-empty in '
        'app_de.arb and app_he.arb', () {
      final onboardingKeys = arbEn.keys
          .where((key) => !key.startsWith('@') && key.startsWith('onboarding'))
          .toList();

      expect(onboardingKeys, isNotEmpty);

      final violations = <String>[];

      for (final key in onboardingKeys) {
        for (final entry in {'de': arbDe, 'he': arbHe}.entries) {
          final locale = entry.key;
          final arb = entry.value;
          final value = arb[key];
          if (value is! String || value.trim().isEmpty) {
            violations.add('  "$key" missing or empty in app_$locale.arb');
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason: 'Onboarding ARB parity violations:\n${violations.join('\n')}',
      );
    });
  });
}
