/// History privacy gate + optional PIN lock state.
///
/// [historyRevealedProvider] is the single "may the history be shown right
/// now" switch. Without a PIN it is the plain "Show history" gate; with a
/// PIN, [HistoryRevealedNotifier.unlockWithPin] is the only way to flip it,
/// and [historyContentHiddenProvider] additionally blanks the secondary
/// surfaces (side panel, floating-button menu, Automation API).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/data/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/path_service.dart';
import 'history_pin.dart';

final _log = AppLogger('HistoryLock');

/// Wall clock for the PIN throttle — a seam so tests can pin "now".
final historyLockClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// Permanently deletes every history entry and its retained recordings —
/// the "Forgot PIN?" path. A seam so tests do not need a database.
final historyWiperProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final files = await ref.read(historyDatabaseProvider).deleteAllHistory();
    for (final path in files) {
      await _deleteQuietly(File(path));
    }
    try {
      final dir = Directory(retainedAudioDir());
      if (dir.existsSync()) {
        await for (final entity in dir.list()) {
          if (entity is File) await _deleteQuietly(entity);
        }
      }
    } catch (e, st) {
      _log.warning('wipe: retained audio cleanup failed', e, st);
    }
  };
});

Future<void> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) await file.delete();
  } catch (e, st) {
    _log.warning('wipe: could not delete ${file.path}', e, st);
  }
}

enum HistoryPinOutcome { ok, wrong, lockedOut }

class HistoryPinResult {
  const HistoryPinResult(this.outcome, [this.retryAfter = Duration.zero]);

  final HistoryPinOutcome outcome;

  /// Remaining lockout; only non-zero for [HistoryPinOutcome.lockedOut].
  final Duration retryAfter;
}

/// Whether the History page has been revealed past its privacy gate.
///
/// Starts concealed on every app start; hiding the main window conceals it
/// again, and so does `HistorySettings.historyAutoLockMinutes` of
/// inactivity ([registerActivity] restarts that countdown).
class HistoryRevealedNotifier extends Notifier<bool> {
  Timer? _autoLock;

  @override
  bool build() {
    ref.onDispose(() => _autoLock?.cancel());
    return false;
  }

  HistorySettings get _history =>
      (ref.read(settingsProvider).value ?? AppSettings.defaults).history;

  /// Reveals without a PIN — only honoured while no PIN is set.
  void reveal() {
    if (_history.historyPin.isNotEmpty) return;
    _setRevealed();
  }

  void conceal() {
    _autoLock?.cancel();
    state = false;
  }

  /// Restarts the auto-lock countdown; call on user activity while revealed.
  void registerActivity() {
    if (state) _armAutoLock();
  }

  /// Time left before [unlockWithPin] accepts another attempt.
  Duration lockoutRemaining() {
    final until = DateTime.fromMillisecondsSinceEpoch(
      _history.historyPinLockedUntil,
    );
    final left = until.difference(ref.read(historyLockClockProvider)());
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks [pin] against the stored hash, counting misses and applying the
  /// [historyPinLockout] throttle. Also used to confirm the current PIN
  /// before it is changed or removed.
  Future<HistoryPinResult> unlockWithPin(String pin) async {
    final remaining = lockoutRemaining();
    if (remaining > Duration.zero) {
      return HistoryPinResult(HistoryPinOutcome.lockedOut, remaining);
    }
    final history = _history;
    final stored = history.historyPin;
    if (await Isolate.run(() => verifyHistoryPin(pin, stored))) {
      if (history.historyPinFailedAttempts != 0 ||
          history.historyPinLockedUntil != 0) {
        await _updateHistory(
          (h) =>
              h.copyWith(historyPinFailedAttempts: 0, historyPinLockedUntil: 0),
        );
      }
      _setRevealed();
      return const HistoryPinResult(HistoryPinOutcome.ok);
    }
    final failed = history.historyPinFailedAttempts + 1;
    final lockout = historyPinLockout(failed);
    final now = ref.read(historyLockClockProvider)();
    await _updateHistory(
      (h) => h.copyWith(
        historyPinFailedAttempts: failed,
        historyPinLockedUntil: lockout == Duration.zero
            ? 0
            : now.add(lockout).millisecondsSinceEpoch,
      ),
    );
    return lockout == Duration.zero
        ? const HistoryPinResult(HistoryPinOutcome.wrong)
        : HistoryPinResult(HistoryPinOutcome.lockedOut, lockout);
  }

  /// Stores a fresh hash of [pin] (caller validated it with
  /// [isValidHistoryPin]); a PIN implies the gate, so it is switched on.
  Future<void> setPin(String pin) async {
    final hash = await Isolate.run(() => hashHistoryPin(pin));
    await _updateHistory(
      (h) => h.copyWith(
        historyHideOnOpen: true,
        historyPin: hash,
        historyPinFailedAttempts: 0,
        historyPinLockedUntil: 0,
      ),
    );
  }

  Future<void> removePin() => _updateHistory(
    (h) => h.copyWith(
      historyPin: '',
      historyPinFailedAttempts: 0,
      historyPinLockedUntil: 0,
    ),
  );

  /// "Forgot PIN?": deletes the whole history, drops the PIN and reveals the
  /// (now empty) page. The gate itself stays on.
  Future<void> resetForgottenPin() async {
    await ref.read(historyWiperProvider)();
    await removePin();
    _setRevealed();
  }

  void _setRevealed() {
    state = true;
    _armAutoLock();
  }

  void _armAutoLock() {
    _autoLock?.cancel();
    final minutes = _history.historyAutoLockMinutes;
    if (minutes <= 0) return;
    _autoLock = Timer(Duration(minutes: minutes), conceal);
  }

  Future<void> _updateHistory(HistorySettings Function(HistorySettings) f) =>
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWithSections(history: f(s.history)));
}

final historyRevealedProvider = NotifierProvider<HistoryRevealedNotifier, bool>(
  HistoryRevealedNotifier.new,
);

/// Whether history text must be withheld from every surface: a PIN is set
/// and the history has not been unlocked. The PIN-less gate only covers the
/// History page itself, so it does not count here. Every surface reading
/// this (side panel, floating button, Automation API) is only started from
/// loaded settings, so the not-yet-loaded fallback is never consulted.
final historyContentHiddenProvider = Provider<bool>((ref) {
  final hasPin = ref.watch(
    settingsProvider.select(
      (s) => s.value?.history.historyPin.isNotEmpty ?? false,
    ),
  );
  return hasPin && !ref.watch(historyRevealedProvider);
});
