/// Health rules for the native observer behind a modifier-only or fn hotkey
/// (#773).
///
/// A combination is held by the system and re-registered by the self-heal in
/// `hotkey_self_heal.dart`. A single key has no registration to renew: an
/// observer (macOS event tap, Windows hook, Linux XInput2 watch) reads every
/// key press, and it can stop without any call failing: the system disables
/// a tap, the hook is dropped, the Input Monitoring grant is withdrawn. This
/// file holds the pure decisions: how a native reply reads, and when a dead
/// observer is rebuilt, given up, or replaced by the stored combination.
library;

/// What the native host says about its observer right now.
enum ObserverHealth {
  /// Running and allowed to read the keyboard.
  healthy,

  /// Not delivering key events (tap disabled, hook gone, watch closed).
  dead,

  /// The system withdrew the right to read the keyboard (macOS Input
  /// Monitoring). A rebuild cannot help until the user grants it again.
  permissionRevoked,

  /// The host cannot tell (a host without the health call, an error, no
  /// answer). Never acted upon: a guess would rebuild a working observer.
  unknown,
}

/// How often a running observer is asked for its health.
const Duration kObserverHealthInterval = Duration(seconds: 15);

/// Healthy answers in a row after which the rebuild count starts over. An
/// observer that answers healthy once after each rebuild and dies again
/// right away must still run out of attempts (about a minute of health).
const int kObserverStableChecks = 4;

/// Rebuilds in a row (without a stable healthy phase in between) before the
/// observer is given up and the stored combination takes over.
const int kObserverRebuildMaxAttempts = 3;

/// Reads a native reply into an [ObserverHealth]. The macOS host answers its
/// `status` call with `listenAccess` and, once it reports the tap, `tapActive`;
/// the Windows and Linux hosts answer `modifierHealth` with `active`. Missing
/// keys are not a verdict: only a `false` or `true` that is really there
/// counts, so an older host without the keys reads as healthy only when the
/// permission is granted, and as unknown when it says nothing.
ObserverHealth observerHealthFromReply(Object? reply) {
  if (reply is! Map) return ObserverHealth.unknown;
  if (reply['listenAccess'] == false) return ObserverHealth.permissionRevoked;
  if (reply['active'] == false || reply['tapActive'] == false) {
    return ObserverHealth.dead;
  }
  if (reply['active'] == true ||
      reply['tapActive'] == true ||
      reply['listenAccess'] == true) {
    return ObserverHealth.healthy;
  }
  return ObserverHealth.unknown;
}

/// What the service does after one health answer.
enum ObserverHealthAction {
  /// Nothing to do.
  none,

  /// Tear the observer down and start it again.
  rebuild,

  /// The right to read the keyboard is gone: use the stored combination and
  /// tell the user where to grant it again.
  fallbackPermission,

  /// Rebuilds did not help: use the stored combination and tell the user.
  fallbackExhausted,
}

/// Counts rebuilds of one observer. Owned by one `HotkeyService`.
class ObserverHealthTracker {
  ObserverHealthTracker({this.maxAttempts = kObserverRebuildMaxAttempts});

  /// Rebuilds allowed in a row.
  final int maxAttempts;

  int _attempts = 0;
  int _healthyRun = 0;

  /// Rebuilds made since the last healthy answer.
  int get attempts => _attempts;

  /// The action for [health]. A `dead` answer spends one attempt, so an
  /// observer that comes back and dies again right away still runs out.
  ObserverHealthAction decide(ObserverHealth health) {
    switch (health) {
      case ObserverHealth.healthy:
        if (++_healthyRun >= kObserverStableChecks) _attempts = 0;
        return ObserverHealthAction.none;
      case ObserverHealth.unknown:
        return ObserverHealthAction.none;
      case ObserverHealth.permissionRevoked:
        return ObserverHealthAction.fallbackPermission;
      case ObserverHealth.dead:
        _healthyRun = 0;
        if (_attempts >= maxAttempts) {
          return ObserverHealthAction.fallbackExhausted;
        }
        _attempts++;
        return ObserverHealthAction.rebuild;
    }
  }

  /// A new observer was asked for from outside (settings, resume): start over.
  void reset() {
    _attempts = 0;
    _healthyRun = 0;
  }
}

/// Why the single key was given up. Carried by the notice to the UI.
enum ObserverLossReason { permissionRevoked, repeatedFailure }
