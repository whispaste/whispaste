import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_fingerprint.dart';

void main() {
  group('ClipboardFingerprint', () {
    test('equal for identical text', () {
      final a = ClipboardFingerprint.ofText('hello world');
      final b = ClipboardFingerprint.ofText('hello world');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differs for different text', () {
      final a = ClipboardFingerprint.ofText('hello world');
      final b = ClipboardFingerprint.ofText('hello world!');
      expect(a, isNot(equals(b)));
    });

    test('differs for text of the same length but different content', () {
      final a = ClipboardFingerprint.ofText('aaaa');
      final b = ClipboardFingerprint.ofText('bbbb');
      expect(a, isNot(equals(b)));
    });

    test('empty text is a valid, stable fingerprint', () {
      final a = ClipboardFingerprint.ofText('');
      final b = ClipboardFingerprint.ofText('');
      expect(a, equals(b));
      expect(a.length, 0);
    });
  });
}
