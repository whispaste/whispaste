import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/paste/input_idle.dart';

InputIdleSnapshot _quiet({double keyIdle = 1e9, double mouseIdle = 1e9}) =>
    InputIdleSnapshot(
      keyIdle: keyIdle,
      mouseIdle: mouseIdle,
      syntheticIdle: 1e9,
    );

void main() {
  const elapsed = Duration(seconds: 2);

  group('userInputSince (DEV-185, GS-056)', () {
    test('an unknown snapshot counts as typed', () {
      expect(userInputSince(elapsed, null), isTrue);
    });

    test('no key or click since the insert is quiet', () {
      expect(userInputSince(elapsed, _quiet()), isFalse);
    });

    test('a key down inside the insert window counts as typed', () {
      expect(userInputSince(elapsed, _quiet(keyIdle: 1)), isTrue);
    });

    test('a key down before the insert does not count', () {
      expect(userInputSince(elapsed, _quiet(keyIdle: 5)), isFalse);
    });

    test('a click inside the insert window counts as typed (GS-056)', () {
      expect(userInputSince(elapsed, _quiet(mouseIdle: 1.5)), isTrue);
    });

    test('a click before the insert does not count', () {
      expect(userInputSince(elapsed, _quiet(mouseIdle: 3)), isFalse);
    });

    test('our own synthetic key-down is not typing', () {
      // The key event is as recent as our synthetic one (within tolerance).
      const snapshot = InputIdleSnapshot(
        keyIdle: 0.5,
        mouseIdle: 1e9,
        syntheticIdle: 0.5,
      );
      expect(userInputSince(elapsed, snapshot), isFalse);
    });

    test('a key after our synthetic key-down counts as typed', () {
      // The hardware key is 0.3 s more recent than our synthetic one.
      const snapshot = InputIdleSnapshot(
        keyIdle: 0.2,
        mouseIdle: 1e9,
        syntheticIdle: 0.5,
      );
      expect(userInputSince(elapsed, snapshot), isTrue);
    });

    test('keys within the tolerance after our synthetic one are hidden', () {
      // Known limit: 0.03 s later is inside syntheticKeyTolerance (50 ms).
      const snapshot = InputIdleSnapshot(
        keyIdle: 0.47,
        mouseIdle: 1e9,
        syntheticIdle: 0.5,
      );
      expect(userInputSince(elapsed, snapshot), isFalse);
    });
  });
}
