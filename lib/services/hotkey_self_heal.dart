/// Self-healing rules for the global hotkey registration.
///
/// The native registration can stop delivering presses without any signal
/// the app receives (the macOS and Windows plugins report success on every
/// register call). [HotkeyService] therefore re-registers the main hotkey on
/// a few triggers. This file holds the pure decisions behind that: when a
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
    required this.modifierOnlyActive,
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

  /// A modifier-only trigger (double tap) owns the observer instead of a
  /// combination.
  final bool modifierOnlyActive;
}

/// Why a heal must not run now, or null when it may run.
String? hotkeyHealBlocker(HotkeyHealState state) {
  if (!state.hotkeyEnabled) return 'hotkey disabled';
  if (state.dictationBusy) return 'dictation active';
  if (state.keyHeld) return 'hotkey held';
  if (state.captureActive) return 'hotkey recorder or onboarding open';
  if (state.modifierOnlyActive) return 'modifier-only trigger';
  return null;
}

/// Minimum spacing between two heals that actually run. Stalls can repeat in
/// bursts, and a wake is often followed by a stall; one heal covers both.
const Duration kHotkeyHealMinInterval = Duration(seconds: 30);

/// A key counts as held for at most this long without a key-up. Windows and
/// Linux report no key-up for every press, so a lost release must not block
/// heals for good; a real hold of this length is not a use case.
const Duration kHotkeyHeldStaleAfter = Duration(minutes: 2);

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
  static int _listening = 0;
  static void Function(bool listening)? _onListeningChanged;

  static bool get active => _depth > 0;

  /// A recorder is listening for keys right now.
  static bool get listening => _listening > 0;

  static void begin() => _depth++;

  static void end() {
    if (_depth > 0) _depth--;
  }

  /// A recorder starts listening. Also counts as an open capture.
  static void beginListening() {
    _depth++;
    _listening++;
    if (_listening == 1) _onListeningChanged?.call(true);
  }

  /// The recorder from [beginListening] stops listening.
  static void endListening() {
    if (_listening == 0) return;
    _listening--;
    end();
    if (_listening == 0) _onListeningChanged?.call(false);
  }

  /// Called when [listening] turns on or off. One listener: the hotkey
  /// service. Passing null removes it.
  static void setListeningListener(void Function(bool listening)? listener) =>
      _onListeningChanged = listener;

  /// Test helper: forgets all open captures and the listener.
  @visibleForTesting
  static void reset() {
    _depth = 0;
    _listening = 0;
    _onListeningChanged = null;
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
