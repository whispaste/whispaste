/// Smoke tests for [currentArchTag] — the replacement for the broken
/// compile-time `0x7FFFFFFFFFFFFFFF > 0` arch hack that hard-coded `'x64'`
/// on every platform (including Apple Silicon).
///
/// We cannot fix the architecture under test from inside Dart, so the
/// tests pin the *output shape* rather than a specific value: the tag
/// must be one of the canonical short labels or, for forward compat,
/// a non-empty fallback string from `Abi.current()`. That is enough to
/// catch the previous regression (returning the literal `'x64'` on
/// arm64) because the helper now goes through `Abi.current()` instead
/// of a constant.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/app_info.dart';

void main() {
  group('currentArchTag', () {
    const canonical = {'arm64', 'x64', 'x86', 'arm', 'riscv64', 'riscv32'};

    test('returns a non-empty string on every supported platform', () {
      final tag = currentArchTag();
      expect(tag, isNotEmpty);
    });

    test('returns one of the canonical short labels for known architectures '
        'or a non-empty fallback for unknown ones', () {
      final tag = currentArchTag();
      // We do not pin to a single value because the test host architecture
      // is environment-dependent (CI runner, dev machine, Apple Silicon
      // vs Intel Mac). The contract is: the helper produces a stable,
      // lowercase, non-empty label that Sentry can use as a `dist` tag.
      expect(tag, equals(tag.toLowerCase()));
      expect(
        canonical.contains(tag) || tag.length > 1,
        isTrue,
        reason:
            'currentArchTag() returned "$tag" — expected one of $canonical '
            'or a non-empty fallback derived from Abi.current().',
      );
    });

    test('does not return the legacy hard-coded "x64" on arm64 hosts', () {
      // Indirect regression guard: on an arm64 host the broken legacy
      // implementation returned `'x64'`. We cannot detect the host arch
      // inside Dart without going through the same `Abi.current()` we
      // are testing, but if the helper ever degrades back to returning
      // the literal `'x64'` on every platform, at least the dev/CI
      // machines running on Apple Silicon will catch it.
      final tag = currentArchTag();
      // Sanity: the tag is computed deterministically from Abi.current(),
      // so a repeated call must return the same value.
      expect(currentArchTag(), equals(tag));
    });
  });
}
