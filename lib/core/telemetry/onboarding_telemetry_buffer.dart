/// Hold for onboarding telemetry until the user's privacy choice.
///
/// Decision 5a: onboarding step
/// events do not leave the device before the user has seen the privacy
/// switches. Until then they wait here:
///
///  - choice "on": every buffered event is sent once, in order, with its
///    original timestamp (Matomo `cdt`); later events go straight out;
///  - choice "off": the buffer and its local copy are discarded and nothing
///    is sent, ever again for this process;
///  - app exit or restart before the choice (GR-033): with a [store] the held
///    events survive on this device only and the next [begin] restores them,
///    so a first run that needs a restart (paste access on macOS, a crash)
///    keeps its early funnel steps. A copy with an event older than
///    [maxHeldAge] belongs to an abandoned first run and is dropped. Nothing
///    is sent before the choice either way.
///
/// Matomo accepts a custom timestamp without `token_auth` only up to 24 hours
/// back, so an event held longer is sent dated [maxBackdate] ago instead of
/// at its original time; order and counts of the funnel stay intact.
///
/// Crash reports are held the same way ([holdsCrashReports]): they are not
/// sent before the choice, and that is deliberate — they cannot be replayed.
///
/// The buffer is capped at [capacity] events; the oldest falls out first.
///
/// Pure Dart, no Riverpod: sender and store are injected, so the rules are
/// testable without a network, a disk or a widget tree.
library;

import 'dart:convert';

/// One onboarding event as held by [OnboardingTelemetryBuffer].
final class BufferedTelemetryEvent {
  const BufferedTelemetryEvent({
    required this.category,
    required this.action,
    required this.name,
    required this.at,
  });

  final String category;
  final String action;
  final String? name;

  /// When the event happened, not when it was sent.
  final DateTime at;

  BufferedTelemetryEvent _datedAt(DateTime when) => BufferedTelemetryEvent(
    category: category,
    action: action,
    name: name,
    at: when,
  );

  Map<String, Object?> toJson() => {
    'c': category,
    'a': action,
    'n': ?name,
    't': at.toUtc().millisecondsSinceEpoch,
  };

  /// Null for anything that is not a well-formed stored event.
  static BufferedTelemetryEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final c = json['c'];
    final a = json['a'];
    final n = json['n'];
    final t = json['t'];
    if (c is! String || a is! String || t is! int) return null;
    if (n != null && n is! String) return null;
    return BufferedTelemetryEvent(
      category: c,
      action: a,
      name: n as String?,
      at: DateTime.fromMillisecondsSinceEpoch(t, isUtc: true),
    );
  }
}

/// Local copy of the held events, so a restart before the privacy choice
/// loses nothing (GR-033). Implementations never throw from [save] or
/// [clear]; a failed [load] yields an empty list.
abstract interface class OnboardingTelemetryStore {
  Future<List<BufferedTelemetryEvent>> load();
  void save(List<BufferedTelemetryEvent> events);
  void clear();
}

/// Encodes held events for an [OnboardingTelemetryStore] backed by a string.
String encodeHeldEvents(List<BufferedTelemetryEvent> events) =>
    jsonEncode([for (final e in events) e.toJson()]);

/// Decodes [encodeHeldEvents]; anything malformed is skipped.
List<BufferedTelemetryEvent> decodeHeldEvents(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    return [for (final item in list) ?BufferedTelemetryEvent.fromJson(item)];
  } on FormatException {
    return const [];
  }
}

enum _BufferMode {
  /// No first run in progress: events go straight through.
  direct,

  /// First run, choice still open: events are held.
  pending,

  /// Choice "on": events go straight through.
  optedIn,

  /// Choice "off": events are dropped.
  optedOut,
}

final class OnboardingTelemetryBuffer {
  OnboardingTelemetryBuffer({
    required this.send,
    this.capacity = 200,
    this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Maximum number of held events; the oldest is dropped first.
  final int capacity;

  final void Function(BufferedTelemetryEvent event) send;

  /// Local copy across restarts; null keeps the hold in memory only.
  final OnboardingTelemetryStore? store;
  final DateTime Function() _clock;

  /// A stored copy with an older event belongs to an abandoned first run.
  static const maxHeldAge = Duration(days: 7);

  /// How far back a sent event may be dated (Matomo: 24 h without a token).
  static const maxBackdate = Duration(hours: 23);

  _BufferMode _mode = _BufferMode.direct;
  final List<BufferedTelemetryEvent> _held = [];

  /// Starts holding events. Called when a first run's overlay mounts; a new
  /// process always starts in direct mode and re-enters the hold on the next
  /// mount. With a [store], the events a previous process held before its
  /// choice are restored in front of the new ones.
  void begin() {
    if (_mode != _BufferMode.direct) return;
    _mode = _BufferMode.pending;
    final store = this.store;
    if (store != null) _restored = _restore(store);
  }

  Future<void> _restored = Future.value();

  /// Completes when the restore started by [begin] has finished.
  Future<void> get restored => _restored;

  Future<void> _restore(OnboardingTelemetryStore store) async {
    List<BufferedTelemetryEvent> stored;
    try {
      stored = await store.load();
    } on Object {
      stored = const [];
    }
    if (stored.isEmpty) return;
    final now = _clock().toUtc();
    final abandoned = stored.any((e) => now.difference(e.at) > maxHeldAge);
    if (abandoned) stored = const [];
    switch (_mode) {
      case _BufferMode.pending:
        _held
          ..insertAll(0, stored)
          ..sort((a, b) => a.at.compareTo(b.at));
        while (_held.length > capacity) {
          _held.removeAt(0);
        }
        _persist();
      case _BufferMode.optedIn:
        // The choice came before the read finished: send the restored ones too.
        stored.map(_dated).forEach(send);
        store.clear();
      case _BufferMode.optedOut || _BufferMode.direct:
        store.clear();
    }
  }

  void _persist() {
    final store = this.store;
    if (store == null) return;
    if (_held.isEmpty) {
      store.clear();
    } else {
      store.save(List.unmodifiable(_held));
    }
  }

  BufferedTelemetryEvent _dated(BufferedTelemetryEvent event) {
    final earliest = _clock().toUtc().subtract(maxBackdate);
    return event.at.isBefore(earliest) ? event._datedAt(earliest) : event;
  }

  /// Records an onboarding event according to the current mode.
  void track({required String category, required String action, String? name}) {
    final event = BufferedTelemetryEvent(
      category: category,
      action: action,
      name: name,
      at: _clock().toUtc(),
    );
    switch (_mode) {
      case _BufferMode.direct || _BufferMode.optedIn:
        send(event);
      case _BufferMode.pending:
        _held.add(event);
        if (_held.length > capacity) _held.removeAt(0);
        _persist();
      case _BufferMode.optedOut:
        // Dropped: the user said no.
        break;
    }
  }

  /// Applies the privacy choice. Only the first call while the choice is
  /// open has an effect; later calls are no-ops. The local copy is removed
  /// either way.
  void decide({required bool shareUsageStats}) {
    if (_mode != _BufferMode.pending) return;
    final pending = List.of(_held);
    _held.clear();
    store?.clear();
    if (shareUsageStats) {
      _mode = _BufferMode.optedIn;
      pending.map(_dated).forEach(send);
    } else {
      _mode = _BufferMode.optedOut;
    }
  }

  /// Whether the privacy choice is still open (events are being held).
  bool get isPending => _mode == _BufferMode.pending;

  /// Whether crash reports must be held as well: true only until the choice.
  bool get holdsCrashReports => isPending;

  /// Number of events currently held.
  int get pendingCount => _held.length;

  /// Time of the earliest held event with [action] and [name], also from a
  /// restored copy; null when none is held.
  DateTime? earliestHeld({required String action, String? name}) {
    DateTime? earliest;
    for (final e in _held) {
      if (e.action != action || e.name != name) continue;
      if (earliest == null || e.at.isBefore(earliest)) earliest = e.at;
    }
    return earliest;
  }
}
