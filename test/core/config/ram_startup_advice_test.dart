import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/ram_gate_config.dart';

// Maintainer decision 22 (2026-10-20): low RAM never blocks the app. It only
// changes the advice: below the threshold the compact speech model is
// recommended, and every machine can start WhisPaste.
void main() {
  group('ramStartupAdvice', () {
    test('a machine below the threshold gets the compact-model advice', () {
      expect(ramStartupAdvice(4096), RamStartupAdvice.compactSpeechModel);
      expect(ramStartupAdvice(6144), RamStartupAdvice.compactSpeechModel);
    });

    test('the threshold itself and everything above get no advice', () {
      expect(ramStartupAdvice(7500), RamStartupAdvice.none);
      expect(ramStartupAdvice(8192), RamStartupAdvice.none);
      expect(ramStartupAdvice(16384), RamStartupAdvice.none);
    });

    test('unknown RAM never advises against starting (fail-open)', () {
      expect(ramStartupAdvice(null), RamStartupAdvice.none);
    });

    test('the advice has no blocking value', () {
      expect(RamStartupAdvice.values, hasLength(2));
      expect(RamStartupAdvice.values.map((a) => a.name), [
        'none',
        'compactSpeechModel',
      ]);
    });
  });
}
