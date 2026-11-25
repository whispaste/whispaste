/// Learning key hints in the recording pill (overlay E).
///
/// The pill names the stop hotkey next to the stop square and the cancel key
/// next to the close glyph ([OverlayKeyHints]). Frequent users know both keys
/// after a while, so each hint goes away on its own once its key is learned:
///
/// * Stop hint: after [stopsToLearn] dictations stopped with the hotkey.
///   Stops by click or auto-stop do not count, so someone who always clicks
///   keeps the hint.
/// * Cancel hint: after [cancelsToLearn] cancels with the cancel key, or
///   after [dictationsToRetireCancel] finished dictations (cancelling is rare,
///   the hint must not stay forever).
///
/// "Learned" is measured on the action itself, not on the bare number of
/// dictations. A changed key starts its counter again (new key, learn anew).
/// Someone returning after [returnGap] without a dictation sees both hints
/// again for [refreshDictations] dictations. The setting
/// `overlayKeyHintsAlways` turns learning off.
///
/// Privacy: only local counters and one date in SharedPreferences; nothing
/// leaves the device, and the counters are device state, not part of the
/// settings export.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart';
import '../../core/logging/app_logger.dart';

final _log = AppLogger('OverlayHintLearning');

/// Hotkey stops after which the stop hint is learned.
const int stopsToLearn = 10;

/// Cancel-key presses after which the cancel hint is learned.
const int cancelsToLearn = 3;

/// Finished dictations after which the cancel hint retires anyway.
const int dictationsToRetireCancel = 50;

/// Time without a dictation after which both hints come back.
const Duration returnGap = Duration(days: 30);

/// Dictations that show both hints again after a [returnGap].
const int refreshDictations = 3;

/// Stable identity of the dictation hotkey: a changed hotkey resets the stop
/// counter. Not shown to anyone.
String stopKeyIdentity(HotkeySettings h) => h.hotkeyDoubleTapKey.isNotEmpty
    ? 'single:${h.hotkeyDoubleTapKey}'
    : '${h.hotkeyModifiers}+${h.hotkeyKey}';

/// Which key hints a live recording shows.
typedef KeyHintVisibility = ({bool showStop, bool showCancel});

/// The learning state. Counters belong to the key they were counted for
/// ([stopKey], [cancelKey]); for any other key they read as zero.
@immutable
class OverlayHintLearningState {
  const OverlayHintLearningState({
    this.stopKey,
    this.stopsByHotkey = 0,
    this.cancelKey,
    this.cancelsByKey = 0,
    this.completed = 0,
    this.lastDictationAt,
    this.refreshLeft = 0,
  });

  /// Hotkey identity the stop counter belongs to; null before the first one.
  final String? stopKey;
  final int stopsByHotkey;

  /// Cancel key the cancel counters belong to; null before the first one.
  final String? cancelKey;
  final int cancelsByKey;

  /// Finished dictations (not cancelled) since the cancel key was last set.
  final int completed;

  /// End of the last dictation, finished or cancelled.
  final DateTime? lastDictationAt;

  /// Dictations left that still show both hints after a return.
  final int refreshLeft;

  static const OverlayHintLearningState initial = OverlayHintLearningState();

  OverlayHintLearningState copyWith({
    String? stopKey,
    int? stopsByHotkey,
    String? cancelKey,
    int? cancelsByKey,
    int? completed,
    DateTime? lastDictationAt,
    int? refreshLeft,
  }) => OverlayHintLearningState(
    stopKey: stopKey ?? this.stopKey,
    stopsByHotkey: stopsByHotkey ?? this.stopsByHotkey,
    cancelKey: cancelKey ?? this.cancelKey,
    cancelsByKey: cancelsByKey ?? this.cancelsByKey,
    completed: completed ?? this.completed,
    lastDictationAt: lastDictationAt ?? this.lastDictationAt,
    refreshLeft: refreshLeft ?? this.refreshLeft,
  );

  @override
  bool operator ==(Object other) =>
      other is OverlayHintLearningState &&
      other.stopKey == stopKey &&
      other.stopsByHotkey == stopsByHotkey &&
      other.cancelKey == cancelKey &&
      other.cancelsByKey == cancelsByKey &&
      other.completed == completed &&
      other.lastDictationAt == lastDictationAt &&
      other.refreshLeft == refreshLeft;

  @override
  int get hashCode => Object.hash(
    stopKey,
    stopsByHotkey,
    cancelKey,
    cancelsByKey,
    completed,
    lastDictationAt,
    refreshLeft,
  );

  @override
  String toString() =>
      'OverlayHintLearningState(stopKey: $stopKey, stops: $stopsByHotkey, '
      'cancelKey: $cancelKey, cancels: $cancelsByKey, completed: $completed, '
      'last: $lastDictationAt, refresh: $refreshLeft)';
}

/// Pure rules of the learning hints. Every method takes the current keys so a
/// changed key counts from zero without a separate change listener.
abstract final class OverlayHintLearning {
  /// Which hints a live recording shows right now.
  static KeyHintVisibility decide(
    OverlayHintLearningState state, {
    required bool always,
    required String stopKey,
    required String cancelKey,
    required DateTime now,
  }) {
    if (always || _refreshing(state, now)) {
      return (showStop: true, showCancel: true);
    }
    final stops = state.stopKey == stopKey ? state.stopsByHotkey : 0;
    final sameCancel = state.cancelKey == cancelKey;
    final cancels = sameCancel ? state.cancelsByKey : 0;
    final completed = sameCancel ? state.completed : 0;
    return (
      showStop: stops < stopsToLearn,
      showCancel:
          cancels < cancelsToLearn && completed < dictationsToRetireCancel,
    );
  }

  /// A dictation was stopped by the dictation hotkey.
  static OverlayHintLearningState recordHotkeyStop(
    OverlayHintLearningState state, {
    required String stopKey,
  }) {
    final base = state.stopKey == stopKey ? state.stopsByHotkey : 0;
    return state.copyWith(stopKey: stopKey, stopsByHotkey: base + 1);
  }

  /// A dictation finished (stopped by any means and not discarded).
  static OverlayHintLearningState recordCompleted(
    OverlayHintLearningState state, {
    required String cancelKey,
    required DateTime now,
  }) {
    final s = _forCancelKey(state, cancelKey);
    return _ended(s.copyWith(completed: s.completed + 1), state, now);
  }

  /// A dictation was cancelled; [byKey] when the cancel key did it.
  static OverlayHintLearningState recordCancel(
    OverlayHintLearningState state, {
    required bool byKey,
    required String cancelKey,
    required DateTime now,
  }) {
    final s = _forCancelKey(state, cancelKey);
    final counted = byKey ? s.copyWith(cancelsByKey: s.cancelsByKey + 1) : s;
    return _ended(counted, state, now);
  }

  static OverlayHintLearningState _forCancelKey(
    OverlayHintLearningState state,
    String cancelKey,
  ) => state.cancelKey == cancelKey
      ? state
      : OverlayHintLearningState(
          stopKey: state.stopKey,
          stopsByHotkey: state.stopsByHotkey,
          cancelKey: cancelKey,
          lastDictationAt: state.lastDictationAt,
          refreshLeft: state.refreshLeft,
        );

  /// Stamps the end of a dictation and counts down a return refresher. The
  /// first dictation after a [returnGap] already is one of the
  /// [refreshDictations].
  static OverlayHintLearningState _ended(
    OverlayHintLearningState next,
    OverlayHintLearningState before,
    DateTime now,
  ) {
    final returning = _away(before, now);
    final refresh = returning
        ? refreshDictations - 1
        : (before.refreshLeft > 0 ? before.refreshLeft - 1 : 0);
    return OverlayHintLearningState(
      stopKey: next.stopKey,
      stopsByHotkey: next.stopsByHotkey,
      cancelKey: next.cancelKey,
      cancelsByKey: next.cancelsByKey,
      completed: next.completed,
      lastDictationAt: now,
      refreshLeft: refresh,
    );
  }

  static bool _away(OverlayHintLearningState s, DateTime now) {
    final last = s.lastDictationAt;
    return last != null && now.difference(last) > returnGap;
  }

  static bool _refreshing(OverlayHintLearningState s, DateTime now) =>
      _away(s, now) || s.refreshLeft > 0;
}

// ── Persistence ─────────────────────────────────────────────────────────────

const _kStopKey = 'overlay_hints_stop_key';
const _kStops = 'overlay_hints_stops_by_hotkey';
const _kCancelKey = 'overlay_hints_cancel_key';
const _kCancels = 'overlay_hints_cancels_by_key';
const _kCompleted = 'overlay_hints_completed';
const _kLast = 'overlay_hints_last_dictation_ms';
const _kRefresh = 'overlay_hints_refresh_left';

/// Reads the state from [prefs]; a missing or broken value reads as zero.
@visibleForTesting
OverlayHintLearningState readHintLearning(SharedPreferences prefs) {
  int intOf(String k) {
    final v = prefs.get(k);
    return v is int && v >= 0 ? v : 0;
  }

  String? strOf(String k) {
    final v = prefs.get(k);
    return v is String && v.isNotEmpty ? v : null;
  }

  final lastMs = prefs.get(_kLast);
  return OverlayHintLearningState(
    stopKey: strOf(_kStopKey),
    stopsByHotkey: intOf(_kStops),
    cancelKey: strOf(_kCancelKey),
    cancelsByKey: intOf(_kCancels),
    completed: intOf(_kCompleted),
    lastDictationAt: lastMs is int
        ? DateTime.fromMillisecondsSinceEpoch(lastMs)
        : null,
    refreshLeft: intOf(_kRefresh),
  );
}

Future<void> _write(SharedPreferences prefs, OverlayHintLearningState s) async {
  Future<void> str(String k, String? v) =>
      v == null ? prefs.remove(k) : prefs.setString(k, v);
  await str(_kStopKey, s.stopKey);
  await prefs.setInt(_kStops, s.stopsByHotkey);
  await str(_kCancelKey, s.cancelKey);
  await prefs.setInt(_kCancels, s.cancelsByKey);
  await prefs.setInt(_kCompleted, s.completed);
  final last = s.lastDictationAt;
  if (last == null) {
    await prefs.remove(_kLast);
  } else {
    await prefs.setInt(_kLast, last.millisecondsSinceEpoch);
  }
  await prefs.setInt(_kRefresh, s.refreshLeft);
}

/// Clock of the learning store; tests override it.
final overlayHintClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Holds the learning state, loads it once and writes every change back.
/// Until the load finishes the state is [OverlayHintLearningState.initial],
/// which shows both hints.
class OverlayHintLearningStore extends Notifier<OverlayHintLearningState> {
  Future<SharedPreferences>? _prefs;
  Future<void>? _loading;

  @override
  OverlayHintLearningState build() {
    _prefs = SharedPreferences.getInstance();
    _loading = _load();
    return OverlayHintLearningState.initial;
  }

  Future<void> _load() async {
    try {
      final loaded = readHintLearning(await _prefs!);
      if (!ref.mounted) return;
      state = loaded;
    } on Object catch (e) {
      _log.debug('hint learning not loaded: ${e.runtimeType}');
    }
  }

  AppSettings get _settings =>
      ref.read(settingsProvider).value ?? AppSettings.defaults;
  DateTime _now() => ref.read(overlayHintClockProvider)();

  /// Which hints the live recording pill shows now.
  KeyHintVisibility visibility(AppSettings s) => OverlayHintLearning.decide(
    state,
    always: s.overlayKeyHintsAlways,
    stopKey: stopKeyIdentity(s.hotkey),
    cancelKey: s.audioInput.cancelDictationKey,
    now: _now(),
  );

  /// The dictation hotkey stopped a recording.
  Future<void> recordHotkeyStop() {
    final stopKey = stopKeyIdentity(_settings.hotkey);
    return _apply(
      (s) => OverlayHintLearning.recordHotkeyStop(s, stopKey: stopKey),
    );
  }

  /// A recording finished and goes on to transcription.
  Future<void> recordCompleted() {
    final cancelKey = _settings.audioInput.cancelDictationKey;
    final now = _now();
    return _apply(
      (s) => OverlayHintLearning.recordCompleted(
        s,
        cancelKey: cancelKey,
        now: now,
      ),
    );
  }

  /// A recording was discarded; [byKey] when the cancel key did it.
  Future<void> recordCancel({required bool byKey}) {
    final cancelKey = _settings.audioInput.cancelDictationKey;
    final now = _now();
    return _apply(
      (s) => OverlayHintLearning.recordCancel(
        s,
        byKey: byKey,
        cancelKey: cancelKey,
        now: now,
      ),
    );
  }

  /// Applies [step] once the stored state is loaded, so an event right after
  /// start never overwrites the stored counters, and writes the result back.
  Future<void> _apply(
    OverlayHintLearningState Function(OverlayHintLearningState) step,
  ) async {
    try {
      await _loading;
      if (!ref.mounted) return;
      final next = step(state);
      if (next == state) return;
      state = next;
      await _write(await _prefs!, next);
    } on Object catch (e) {
      _log.debug('hint learning not saved: ${e.runtimeType}');
    }
  }
}

final overlayHintLearningProvider =
    NotifierProvider<OverlayHintLearningStore, OverlayHintLearningState>(
      OverlayHintLearningStore.new,
    );
