/// Unit tests for [SelfWriteSuppressionRegistry].
///
/// The registry must be marked *before* the clipboard write happens (see
/// PRD.md "Self-Write-Suppression") -- these tests only cover the registry's
/// own bookkeeping, not the call ordering (that's asserted at the
/// AppClipboard call sites in issue 02).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';
import 'package:whispaste/services/clipboard_history/self_write_suppression_registry.dart';

void main() {
  group('SelfWriteSuppressionRegistry', () {
    final fpA = ClipboardFingerprint.ofText('hello world');
    final fpB = ClipboardFingerprint.ofText('something else');

    test('suppresses a fingerprint that was marked', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = SelfWriteSuppressionRegistry(now: () => now);
      registry.markSelfWrite(fpA);
      expect(registry.shouldSuppress(fpA), isTrue);
    });

    test('does not suppress an unmarked fingerprint', () {
      final registry = SelfWriteSuppressionRegistry();
      expect(registry.shouldSuppress(fpB), isFalse);
    });

    test('a mark is consumed after being checked once', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = SelfWriteSuppressionRegistry(now: () => now);
      registry.markSelfWrite(fpA);
      expect(registry.shouldSuppress(fpA), isTrue);
      expect(registry.shouldSuppress(fpA), isFalse);
    });

    test('an expired mark no longer suppresses', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final registry = SelfWriteSuppressionRegistry(
        now: () => now,
        expiry: const Duration(seconds: 2),
      );
      registry.markSelfWrite(fpA);
      now = now.add(const Duration(seconds: 3));
      expect(registry.shouldSuppress(fpA), isFalse);
    });
  });
}
