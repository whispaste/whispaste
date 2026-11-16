/// Holds every background connection of the app until the first-run privacy
/// choice is made (#686, internal-notes §6.5).
///
/// A fresh install sends nothing of its own accord (usage statistics, update
/// checks) before the user has seen the privacy switches. The gate is held
/// from the start while onboarding is not completed and opens exactly once:
/// when the onboarding commits the privacy choice or completes. It is never
/// persisted, so a restart before the choice holds again.
///
/// Pure Dart, no Riverpod and no clock: testable without a network.
library;

final class FirstRunNetworkGate {
  /// [held] is `true` for a first run whose privacy choice is still open.
  FirstRunNetworkGate({required bool held}) {
    _held = held;
  }

  late bool _held;
  final List<void Function()> _waiting = [];

  /// Whether background connections must still wait.
  bool get isHeld => _held;

  /// Whether background connections may run.
  bool get isOpen => !_held;

  /// Opens the gate and runs everything queued with [whenOpen], in order.
  /// Later calls do nothing.
  void open() {
    if (!_held) return;
    _held = false;
    final queued = List.of(_waiting);
    _waiting.clear();
    for (final action in queued) {
      action();
    }
  }

  /// Runs [action] now when the gate is open, otherwise once when it opens.
  /// Queued actions are dropped if the process ends first.
  void whenOpen(void Function() action) {
    if (_held) {
      _waiting.add(action);
    } else {
      action();
    }
  }
}
