/// The handbook's setup chapter names the onboarding as the app shows it
/// (#1921): the five phase labels of the top bar, in every language, and no
/// longer a count of steps with dots.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _phaseKeys = [
  'onboardingPhaseStart',
  'onboardingPhasePersonalize',
  'onboardingPhasePermissions',
  'onboardingPhaseSetup',
  'onboardingPhaseTry',
];

void main() {
  final arbs = Directory('lib/core/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_[a-z]+\.arb$').hasMatch(f.path))
      .toList();

  test('all languages are checked', () {
    expect(arbs, hasLength(greaterThanOrEqualTo(9)));
  });

  for (final file in arbs) {
    test('${file.uri.pathSegments.last}: setup intro names the phases', () {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final intro = arb['manualC01S1B1'] as String;
      for (final key in _phaseKeys) {
        expect(intro, contains(arb[key] as String), reason: key);
      }
    });
  }
}
