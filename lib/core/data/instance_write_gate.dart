/// Keeps the history database closed while the single-instance check could
/// not run (#1647).
///
/// `SingleInstanceService` tells a second launch from a technical failure:
/// when no lock file can be created at all, it cannot know whether another
/// WhisPaste already writes to the same data. It then closes this gate. The
/// history database refuses to open with [InstanceCheckUnavailableException]
/// until the user confirms on the start screen that no other WhisPaste is
/// open, so two instances never write to the same file unnoticed.
library;

/// Thrown by the history database while [InstanceWriteGate.closed] is true.
/// The start gate shows its own screen for it; nothing was opened or changed.
class InstanceCheckUnavailableException implements Exception {
  const InstanceCheckUnavailableException();

  @override
  String toString() =>
      'InstanceCheckUnavailableException: the single-instance check could '
      'not run; the history database stays closed until the user confirms';
}

/// Process-wide switch read by the history database before it opens.
abstract final class InstanceWriteGate {
  static bool _closed = false;

  /// True while the database must not open.
  static bool get closed => _closed;

  /// The single-instance check could not run: keep the database closed.
  static void close() => _closed = true;

  /// The user confirmed that no other WhisPaste is open, or a later check
  /// succeeded: the database may open.
  static void open() => _closed = false;

  /// Throws [InstanceCheckUnavailableException] while the gate is closed.
  static void ensureOpen() {
    if (_closed) throw const InstanceCheckUnavailableException();
  }
}
