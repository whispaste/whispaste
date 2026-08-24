/// Unit tests for [ClipboardHistoryRingBuffer].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_entry.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_ring_buffer.dart';

ClipboardHistoryEntry _textEntry(String text, {DateTime? at}) =>
    ClipboardHistoryEntry.text(text, capturedAt: at ?? DateTime(2026, 1, 1));

ClipboardHistoryEntry _imageEntry(int bytes, {DateTime? at}) =>
    ClipboardHistoryEntry.image(
      List<int>.filled(bytes, 0),
      capturedAt: at ?? DateTime(2026, 1, 1),
    );

void main() {
  group('ClipboardHistoryRingBuffer', () {
    test('newest entry is first', () {
      final buffer = ClipboardHistoryRingBuffer(
        maxEntries: 10,
        maxTotalBytes: 1000,
      );
      buffer.add(_textEntry('first'));
      buffer.add(_textEntry('second'));
      expect(buffer.entries.map((e) => e.textValue), ['second', 'first']);
    });

    test('evicts oldest entries once the entry cap is exceeded', () {
      final buffer = ClipboardHistoryRingBuffer(
        maxEntries: 2,
        maxTotalBytes: 1000,
      );
      buffer.add(_textEntry('a'));
      buffer.add(_textEntry('b'));
      buffer.add(_textEntry('c'));
      expect(buffer.entries.map((e) => e.textValue), ['c', 'b']);
    });

    test('evicts oldest entries once the byte cap is exceeded', () {
      final buffer = ClipboardHistoryRingBuffer(
        maxEntries: 100,
        maxTotalBytes: 1500,
      );
      buffer.add(_imageEntry(1000));
      buffer.add(_imageEntry(1000));
      expect(buffer.entries, hasLength(1));
    });

    test('a single entry larger than the byte cap is still kept alone', () {
      final buffer = ClipboardHistoryRingBuffer(
        maxEntries: 100,
        maxTotalBytes: 500,
      );
      buffer.add(_imageEntry(2000));
      expect(buffer.entries, hasLength(1));
    });

    test('clear empties the buffer', () {
      final buffer = ClipboardHistoryRingBuffer(
        maxEntries: 10,
        maxTotalBytes: 1000,
      );
      buffer.add(_textEntry('a'));
      buffer.clear();
      expect(buffer.entries, isEmpty);
    });
  });
}
