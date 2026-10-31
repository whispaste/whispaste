import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_entry.dart';
import 'package:whispaste/services/clipboard_history/clipboard_history_provider.dart';

void main() {
  group('clipboardHistoryProvider', () {
    test('starts empty', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(clipboardHistoryProvider), isEmpty);
    });

    test('add() prepends the new entry and updates state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(clipboardHistoryProvider.notifier);

      notifier.add(
        ClipboardHistoryEntry.text('first', capturedAt: DateTime(2026)),
      );
      notifier.add(
        ClipboardHistoryEntry.text('second', capturedAt: DateTime(2026)),
      );

      final state = container.read(clipboardHistoryProvider);
      expect(state, hasLength(2));
      expect(state.first.textValue, 'second');
    });

    test('clear() empties the buffer', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(clipboardHistoryProvider.notifier);
      notifier.add(ClipboardHistoryEntry.text('x', capturedAt: DateTime(2026)));

      notifier.clear();

      expect(container.read(clipboardHistoryProvider), isEmpty);
    });
  });
}
