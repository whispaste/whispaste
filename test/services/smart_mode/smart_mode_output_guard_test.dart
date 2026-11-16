import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/smart_mode/smart_mode_output_guard.dart';

void main() {
  group('smartModeOutputLooksLooped', () {
    test('short output is never treated as a loop, even if far longer', () {
      expect(
        smartModeOutputLooksLooped(input: 'ok', output: 'x' * 199),
        isFalse,
      );
    });

    test('output close to the input length is kept', () {
      final input = 'word ' * 60; // 300 chars
      expect(smartModeOutputLooksLooped(input: input, output: input), isFalse);
    });

    test('at least 200 chars and more than 1.5x the input is a loop', () {
      final input = 'word ' * 20; // 100 chars
      final output = 'word ' * 60; // 300 chars, above 150
      expect(smartModeOutputLooksLooped(input: input, output: output), isTrue);
    });

    test('exactly 1.5x the input is still accepted', () {
      final input = 'x' * 200;
      expect(
        smartModeOutputLooksLooped(input: input, output: 'y' * 300),
        isFalse,
      );
    });

    test('any output of 200 chars or more is a loop for an empty input', () {
      expect(smartModeOutputLooksLooped(input: '', output: 'y' * 200), isTrue);
    });
  });
}
