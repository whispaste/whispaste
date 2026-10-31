import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clipboard_history_entry.dart';
import 'clipboard_history_ring_buffer.dart';

/// Default caps for the RAM-only clipboard history ring buffer -- see
/// PRD.md "Ring-Buffer-Limits". A handful of full-size screenshots
/// dominates the byte budget long before the entry count does, so the byte
/// cap is what actually bounds memory in practice; the entry cap just keeps
/// a burst of tiny text copies from growing the list unboundedly.
const int kClipboardHistoryMaxEntries = 50;
const int kClipboardHistoryMaxTotalBytes = 20 * 1024 * 1024;

/// Riverpod-visible view of the RAM-only clipboard history ring buffer
/// (issue 01). Nothing populates it yet -- the native monitors (issues
/// 04-05) and the Linux snapshot-on-open read (issue 06) call [add] once
/// they exist; until then this is always empty, which the side panel's
/// Clipboard-Historie section already renders correctly as its empty state.
class ClipboardHistoryNotifier extends Notifier<List<ClipboardHistoryEntry>> {
  final ClipboardHistoryRingBuffer _buffer = ClipboardHistoryRingBuffer(
    maxEntries: kClipboardHistoryMaxEntries,
    maxTotalBytes: kClipboardHistoryMaxTotalBytes,
  );

  @override
  List<ClipboardHistoryEntry> build() => _buffer.entries;

  void add(ClipboardHistoryEntry entry) {
    _buffer.add(entry);
    state = _buffer.entries;
  }

  /// RAM-only by design -- there is nothing on disk to clear, this only
  /// resets the in-memory buffer (e.g. for tests).
  void clear() {
    _buffer.clear();
    state = _buffer.entries;
  }
}

final clipboardHistoryProvider =
    NotifierProvider<ClipboardHistoryNotifier, List<ClipboardHistoryEntry>>(
      ClipboardHistoryNotifier.new,
    );
