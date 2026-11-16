/// Self-healing rules for the global hotkey registration.
///
/// The native registration can stop delivering presses without any signal
/// the app receives (the system drops a grab silently, for example after a
/// wake). A refused register call is reported on all three systems since #770,
/// but a grab that was lost without a call is not. [HotkeyService] therefore
/// re-registers the main hotkey on a few triggers. This file holds the pure decisions behind that: when a
/// heal must wait, how often it may run, and when repeated failures earn the
/// user a toast.
library;

import 'package:flutter/widgets.dart';

/// What asked for a re-registration. Written into the single log line.
enum HotkeyHealTrigger { wake, memoryPressure, uiStall, timer }

/// Snapshot of the app state a heal depends on. Read by [HotkeyService] right
/// before it runs.
class HotkeyHealState {
  const HotkeyHealState({
    required this.hotkeyEnabled,
    required this.dictationBusy,
    required this.keyHeld,
    required this.captureActive,
  });

  /// The main hotkey is switched on in the settings.
  final bool hotkeyEnabled;

  /// A dictation is recording or transcribing.
  final bool dictationBusy;

  /// Some action's key is currently held down (hold mode would lose its
  /// release if the registration changed now).
  final bool keyHeld;

  /// The hotkey recorder or the onboarding hotkey step is open.
  final bool captureActive;
}

/// Why a heal must not run now, or null when it may run.
String? hotkeyHealBlocker(HotkeyHealState state) {
  if (!state.hotkeyEnabled) return 'hotkey disabled';
  if (state.dictationBusy) return 'dictation active';
  if (state.keyHeld) return 'hotkey held';
  if (state.captureActive) return 'hotkey recorder or onboarding open';
  return null;
}

/// Minimum spacing between two heals that actually run. Stalls can repeat in
/// bursts, and a wake is often followed by a stall; one heal covers both.
const Duration kHotkeyHealMinInterval = Duration(seconds: 30);

/// A key counts as held for at most this long without a key-up. Windows and
/// Linux report no key-up for every press, so a lost release must not block
/// heals for good; a real hold of this length is not a use case.
const Duration kHotkeyHeldStaleAfter = Duration(minutes: 2);

/// How often a hold-to-talk press is compared with the real key state while
/// the hotkey counts as held (#774). A lost release (screen lock, user switch,
/// secure desktop, an app that swallowed the event) is noticed within one
/// interval and ends the press like a normal release. A cheap hardware read,
/// so the interval is short enough to feel prompt.
const Duration kHotkeyHeldProbeInterval = Duration(milliseconds: 750);

/// A held-key read slower than this means the UI thread stalled (#1194). The
/// key events of that moment are then still queued behind the read, so "up"
/// from the hardware is not yet proof that a release got lost.
const Duration kHotkeyProbeStallThreshold = Duration(milliseconds: 250);

/// How long the check waits for the queued real events after a stalled read
/// before it ends the press itself (#1194). The real release carries the
/// native time; the check's own release only has the (late) arrival time, and
/// would turn a double tap into a hold plus a refused second start.
const Duration kHotkeyProbeStallGrace = Duration(milliseconds: 400);

/// Safety-net period for a heal even without any trigger.
const Duration kHotkeyHealInterval = Duration(minutes: 5);

/// Consecutive failed heals after which the user gets a toast.
const int kHotkeyHealFailureToastThreshold = 3;

/// Throttle and failure streak of the heal. Owned by one [HotkeyService].
class HotkeyHealGate {
  HotkeyHealGate({
    this.minInterval = kHotkeyHealMinInterval,
    this.toastThreshold = kHotkeyHealFailureToastThreshold,
  });

  final Duration minInterval;
  final int toastThreshold;

  DateTime? _lastRunAt;
  int _failures = 0;

  /// Whether a heal at [now] comes too soon after the last one that ran.
  bool isThrottled(DateTime now) =>
      _lastRunAt != null && now.difference(_lastRunAt!) < minInterval;

  /// Records that a heal started at [now].
  void markRun(DateTime now) => _lastRunAt = now;

  /// Counts a failed heal. Returns true exactly when the streak reaches the
  /// toast threshold, so the user is told once per streak.
  bool recordFailure() {
    _failures++;
    return _failures == toastThreshold;
  }

  /// A heal succeeded: the streak starts over.
  void recordSuccess() => _failures = 0;

  int get consecutiveFailures => _failures;
}

/// How long a recorder may keep the app's hotkeys off the system. Recording
/// a combination takes seconds; past this, the recorder is taken to be gone
/// without its dispose (core review L-14 F4), and [HotkeyService] puts the
/// hotkeys back rather than leaving them dead until the next start. Two
/// minutes (maintainer 2026-11-01, was 15): long enough to read the recorder
/// and try a few combinations, short enough that a lost recorder does not
/// cost a dictation.
const Duration kHotkeyCaptureListenLimit = Duration(minutes: 2);

/// Carries [HotkeyCaptureGuard.listenLimitExpired]; [ChangeNotifier] keeps its
/// notify method protected, so the guard fires through this subclass.
class _LimitExpiredNotifier extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Process-wide count of open hotkey captures (recorder dialogs and the
/// onboarding hotkey step). Counted, so nested or overlapping captures
/// balance out. [HotkeyService] reads [active] before a heal.
///
/// A recorder that is actually listening for keys counts in [listening] as
/// well. While it does, [HotkeyService] takes the app's system-wide hotkeys
/// off the system, because a registered combination never reaches the
/// recorder. The onboarding hotkey page only counts in [active]: its practice
/// press needs the registered hotkey.
abstract final class HotkeyCaptureGuard {
  static int _depth = 0;
  static final List<Object> _listenTokens = [];
  static DateTime? _listeningSince;
  static void Function(bool listening)? _onListeningChanged;
  static final _LimitExpiredNotifier _limitExpired = _LimitExpiredNotifier();

  /// Clock for [beginListening]; tests pin it.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static bool get active => _depth > 0;

  /// A recorder is listening for keys right now.
  static bool get listening => _listenTokens.isNotEmpty;

  /// Notifies when [releaseStale] ends the listening captures. The recorders
  /// close then, as if cancelled (#113).
  static Listenable get listenLimitExpired => _limitExpired;

  static void begin() => _depth++;

  static void end() {
    if (_depth > 0) _depth--;
  }

  /// A recorder starts listening. Also counts as an open capture. The token
  /// names this recorder: [endListening] with it ends only that recorder, so a
  /// recorder that closes late cannot end a newer one.
  static Object beginListening() {
    _depth++;
    final token = Object();
    _listenTokens.add(token);
    if (_listenTokens.length == 1) {
      _listeningSince = clock();
      _onListeningChanged?.call(true);
    }
    return token;
  }

  /// The recorder from [beginListening] stops listening. Without a [token],
  /// the most recent listening recorder stops.
  static void endListening([Object? token]) {
    if (_listenTokens.isEmpty) return;
    final index = token == null
        ? _listenTokens.length - 1
        : _listenTokens.indexOf(token);
    if (index < 0) return;
    _listenTokens.removeAt(index);
    end();
    if (_listenTokens.isEmpty) {
      _listeningSince = null;
      _onListeningChanged?.call(false);
    }
  }

  /// Ends every listening capture once [listening] has lasted longer than
  /// [limit] at [now], so the hotkeys come back. Returns true when it did, and
  /// then [listenLimitExpired] notifies the recorders. A recorder that is in
  /// fact still open and ends later is ignored by [endListening], so the
  /// counts stay balanced.
  static bool releaseStale(
    DateTime now, {
    Duration limit = kHotkeyCaptureListenLimit,
  }) {
    final since = _listeningSince;
    if (_listenTokens.isEmpty || since == null) return false;
    if (now.difference(since) <= limit) return false;
    final released = _listenTokens.length;
    _depth = _depth > released ? _depth - released : 0;
    _listenTokens.clear();
    _listeningSince = null;
    _onListeningChanged?.call(false);
    _limitExpired.fire();
    return true;
  }

  /// Called when [listening] turns on or off. One listener: the hotkey
  /// service. Passing null removes it.
  static void setListeningListener(void Function(bool listening)? listener) =>
      _onListeningChanged = listener;

  /// Test helper: forgets all open captures and the listener.
  @visibleForTesting
  static void reset() {
    _depth = 0;
    _listenTokens.clear();
    _listeningSince = null;
    _onListeningChanged = null;
    clock = DateTime.now;
  }
}

/// Wraps a page or dialog that captures a hotkey, so the global registration
/// stays untouched while it is open.
class HotkeyCaptureScope extends StatefulWidget {
  const HotkeyCaptureScope({super.key, required this.child});

  final Widget child;

  @override
  State<HotkeyCaptureScope> createState() => _HotkeyCaptureScopeState();
}

class _HotkeyCaptureScopeState extends State<HotkeyCaptureScope> {
  @override
  void initState() {
    super.initState();
    HotkeyCaptureGuard.begin();
  }

  @override
  void dispose() {
    HotkeyCaptureGuard.end();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
