import 'clipboard_history_entry.dart';

/// RAM-only ring buffer for [ClipboardHistoryEntry]. Bounded by both an
/// entry-count cap and a total-byte cap -- images make byte size the
/// dimension that actually matters, an entry-only cap could still exhaust
/// RAM. Oldest entries are evicted first until both caps hold.
class ClipboardHistoryRingBuffer {
  ClipboardHistoryRingBuffer({
    required this.maxEntries,
    required this.maxTotalBytes,
  });

  final int maxEntries;
  final int maxTotalBytes;

  final List<ClipboardHistoryEntry> _entries = [];

  List<ClipboardHistoryEntry> get entries => List.unmodifiable(_entries);

  void add(ClipboardHistoryEntry entry) {
    _entries.insert(0, entry);
    _evict();
  }

  void clear() => _entries.clear();

  void _evict() {
    while (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    while (_entries.length > 1 && _totalBytes() > maxTotalBytes) {
      _entries.removeLast();
    }
  }

  int _totalBytes() => _entries.fold(0, (sum, e) => sum + e.byteSize);
}
