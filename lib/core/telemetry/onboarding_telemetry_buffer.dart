/// In-memory hold for onboarding telemetry until the user's privacy choice.
///
/// Decision 5a (`internal-notes`): onboarding step
/// events do not leave the process before the user has seen the privacy
/// switches. Until then they wait here, in memory only:
///
///  - choice "on": every buffered event is sent once, in order, with its
///    original timestamp (Matomo `cdt`); later events go straight out;
///  - choice "off": the buffer is discarded and nothing is sent, ever again
///    for this process;
///  - app exit or restart before the choice: the buffer is lost. It is never
///    persisted.
///
/// Crash reports are held the same way ([holdsCrashReports]): they are not
/// sent before the choice, and that is deliberate — they cannot be replayed.
///
/// The buffer is capped at [capacity] events; the oldest falls out first.
///
/// Pure Dart, no Riverpod: the sender is injected, so the rules are testable
/// without a network or a widget tree.
library;

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
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Maximum number of held events; the oldest is dropped first.
  final int capacity;

  final void Function(BufferedTelemetryEvent event) send;
  final DateTime Function() _clock;

  _BufferMode _mode = _BufferMode.direct;
  final List<BufferedTelemetryEvent> _held = [];

  /// Starts holding events. Called when a first run's overlay mounts; a new
  /// process always starts in direct mode, so a restart begins with an empty
  /// buffer and re-enters the hold on the next mount.
  void begin() {
    if (_mode == _BufferMode.direct) _mode = _BufferMode.pending;
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
      case _BufferMode.optedOut:
        // Dropped: the user said no.
        break;
    }
  }

  /// Applies the privacy choice. Only the first call while the choice is
  /// open has an effect; later calls are no-ops.
  void decide({required bool shareUsageStats}) {
    if (_mode != _BufferMode.pending) return;
    if (shareUsageStats) {
      _mode = _BufferMode.optedIn;
      final pending = List.of(_held);
      _held.clear();
      pending.forEach(send);
    } else {
      _mode = _BufferMode.optedOut;
      _held.clear();
    }
  }

  /// Whether the privacy choice is still open (events are being held).
  bool get isPending => _mode == _BufferMode.pending;

  /// Whether crash reports must be held as well: true only until the choice.
  bool get holdsCrashReports => isPending;

  /// Number of events currently held.
  int get pendingCount => _held.length;
}
