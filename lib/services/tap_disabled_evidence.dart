/// When the system last switched an event tap off (a `tapDisabled` host
/// event): the one real evidence, besides a clearly worse latency, that a slow
/// keyboard tap costs hotkey presses (#915). Kept free of imports so the
/// modifier-key monitor (writer) and the disturbance gate (reader) share it
/// without a dependency cycle.
library;

class TapDisabledEvidence {
  DateTime? _lastAt;
  DateTime? get lastAt => _lastAt;

  void record(DateTime at) => _lastAt = at;
}

/// The process-wide instance.
final TapDisabledEvidence tapDisabledEvidence = TapDisabledEvidence();
