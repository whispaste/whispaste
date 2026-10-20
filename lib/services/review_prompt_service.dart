/// Review prompt service — tracks usage milestones and surfaces a rating
/// prompt after the user has had enough positive experience with the app.
///
/// Uses SharedPreferences to persist prompt history across sessions.
/// Respects the deploy channel to surface the correct review flow.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_info.dart' as app_info;
import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';
import 'shared_prefs_safe_read.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Snapshot of the review prompt service state.
class ReviewPromptState {
  const ReviewPromptState({
    this.shouldShowPrompt = false,
    this.channel = DeployChannel.portable,
  });

  final bool shouldShowPrompt;
  final DeployChannel channel;

  ReviewPromptState copyWith({
    bool? shouldShowPrompt,
    DeployChannel? channel,
  }) => ReviewPromptState(
    shouldShowPrompt: shouldShowPrompt ?? this.shouldShowPrompt,
    channel: channel ?? this.channel,
  );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const _keyLastShownMs = 'review_prompt_last_shown';
const _keyLastSnoozeMs = 'review_prompt_last_snooze';
const _keyLastShownAppVersion = 'review_prompt_last_shown_version';
const _keyPermanentlyDismissed = 'review_prompt_permanently_dismissed';
const _keyShownCount = 'review_prompt_shown_count';
const _keyLastVersionRepromptMs = 'review_prompt_last_version_reprompt';
const _keyUnpastedEntryIds = 'review_prompt_unpasted_entry_ids';
const _keyNativeRequestsMs = 'review_prompt_native_request_ms';

/// Minimum recordings before the prompt is eligible to show.
const _minRecordings = 12;

/// At most this many native store rating requests in [_nativeRequestWindowDays]
/// (growth review GR-009). Only the last [_maxNativeRequestsPerWindow] request
/// times are kept, which is enough to decide the cap.
const _maxNativeRequestsPerWindow = 3;
const _nativeRequestWindowDays = 365;

/// Minimum days between prompt displays after a completed review action
/// (`markShown`). Materially shorter than [_notNowDaysBetweenPrompts].
const _minDaysBetweenPrompts = 30;

/// Minimum days before re-prompting a "not now" snooze. Materially longer than
/// [_minDaysBetweenPrompts] so a snooze buys more quiet time than a completed
/// action.
const _notNowDaysBetweenPrompts = 60;

/// Minimum days between two version-upgrade re-prompts. A version change may
/// re-activate the prompt at most once in this window (growth review R-03).
const _versionRepromptDaysBetween = 365;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages when to show the in-app review / rating prompt.
///
/// Call [checkAndMaybePrompt] after a successful transcription to evaluate
/// whether conditions are met. When [state.shouldShowPrompt] becomes `true`,
/// show [ReviewPromptDialog] and call [markShown] or [dismiss] afterward.
class ReviewPromptNotifier extends Notifier<ReviewPromptState> {
  static final _log = AppLogger('ReviewPrompt');

  @override
  ReviewPromptState build() {
    final channel = ref.read(deployChannelProvider);
    return ReviewPromptState(channel: channel);
  }

  /// Checks whether conditions are met and, if so, sets
  /// [ReviewPromptState.shouldShowPrompt] to `true`.
  ///
  /// Conditions:
  /// 1. Not permanently dismissed.
  /// 2. Total active recordings >= [_minRecordings].
  /// 3. Either never shown, or last shown > [_minDaysBetweenPrompts] days ago
  ///    (or > [_notNowDaysBetweenPrompts] after a "not now" snooze).
  /// 4. A version upgrade may additionally show the prompt once, but only when
  ///    conditions 1 and 3 hold and no version re-prompt happened in the last
  ///    [_versionRepromptDaysBetween] days. A snooze is never overridden.
  ///
  /// [appVersion] is the current app version used for version-change detection;
  /// it defaults to the global app version and is injectable for testing.
  Future<void> checkAndMaybePrompt({String? appVersion}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // "Never again" is permanent — no upgrade or cooldown re-activates it.
      // Safe read: this key can be a bundle-ID-migrated String (see
      // shared_prefs_safe_read.dart).
      if (readBoolPrefSafe(prefs, _keyPermanentlyDismissed) == true) return;

      final db = ref.read(historyDatabaseProvider);
      final count = await countEligibleRecordings(prefs, db);
      if (count < _minRecordings) return;

      final version = appVersion ?? app_info.appVersion;
      final now = DateTime.now();

      // Safe reads: these keys can be bundle-ID-migrated Strings (see
      // shared_prefs_safe_read.dart) — confirmed crashing in production as
      // Sentry FLUTTER_WHISPASTE-BQ before this fix.
      final lastShownMs = readIntPrefSafe(prefs, _keyLastShownMs) ?? 0;
      final inShownCooldown =
          lastShownMs > 0 &&
          now
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastShownMs))
                  .inDays <
              _minDaysBetweenPrompts;
      final lastSnoozeMs = readIntPrefSafe(prefs, _keyLastSnoozeMs) ?? 0;
      final inSnooze =
          lastSnoozeMs > 0 &&
          now
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastSnoozeMs))
                  .inDays <
              _notNowDaysBetweenPrompts;

      // Version-upgrade re-prompt: a version change may show the prompt once,
      // at most once per [_versionRepromptDaysBetween] days. It never overrides
      // a snooze or the post-action cooldown. If it is blocked, the persisted
      // version is left unchanged so a later launch can still re-evaluate.
      final lastShownVersion = prefs.getString(_keyLastShownAppVersion) ?? '';
      if (version != lastShownVersion && lastShownVersion.isNotEmpty) {
        final lastRepromptMs =
            readIntPrefSafe(prefs, _keyLastVersionRepromptMs) ?? 0;
        final repromptAllowed =
            lastRepromptMs == 0 ||
            now
                    .difference(
                      DateTime.fromMillisecondsSinceEpoch(lastRepromptMs),
                    )
                    .inDays >=
                _versionRepromptDaysBetween;
        if (repromptAllowed && !inShownCooldown && !inSnooze) {
          await prefs.setString(_keyLastShownAppVersion, version);
          await prefs.setInt(
            _keyLastVersionRepromptMs,
            now.millisecondsSinceEpoch,
          );
          _log.info(
            'version upgrade re-prompt '
            '($lastShownVersion → $version, recordings=$count)',
          );
          state = state.copyWith(shouldShowPrompt: true);
          return;
        }
      }

      if (inShownCooldown || inSnooze) return;

      await prefs.setString(_keyLastShownAppVersion, version);
      _log.info('conditions met (recordings=$count)');
      state = state.copyWith(shouldShowPrompt: true);
    } on Exception catch (e) {
      _log.error('check failed: $e', e);
    }
  }

  /// Marks the history entry of a dictation whose paste failed (GR-012). The
  /// entry stays in the history but no longer counts toward [_minRecordings].
  /// A null [entryId] (nothing was written to the history) changes nothing.
  Future<void> countUnpastedDictation({required String? entryId}) async {
    if (entryId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _readUnpastedEntryIds(prefs);
      if (ids.contains(entryId)) return;
      ids.add(entryId);
      await prefs.setStringList(_keyUnpastedEntryIds, ids);
    } on Exception catch (e) {
      _log.error('countUnpastedDictation failed: $e', e);
    }
  }

  /// Whether a native store rating request may still be made (GR-009): fewer
  /// than [_maxNativeRequestsPerWindow] requests within the last
  /// [_nativeRequestWindowDays] days. Fails closed when preferences cannot be
  /// read.
  Future<bool> nativeRequestAllowed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cutoff = DateTime.now().subtract(
        const Duration(days: _nativeRequestWindowDays),
      );
      final recent = _readNativeRequestTimes(
        prefs,
      ).where((ms) => DateTime.fromMillisecondsSinceEpoch(ms).isAfter(cutoff));
      return recent.length < _maxNativeRequestsPerWindow;
    } on Exception catch (e) {
      _log.error('nativeRequestAllowed failed: $e', e);
      return false;
    }
  }

  /// Records a native store rating request that the OS accepted (GR-009) and
  /// applies the post-action cooldown ([markShown]).
  Future<void> markNativeRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final times = [
        ..._readNativeRequestTimes(prefs),
        DateTime.now().millisecondsSinceEpoch,
      ];
      final kept = times.length > _maxNativeRequestsPerWindow
          ? times.sublist(times.length - _maxNativeRequestsPerWindow)
          : times;
      await prefs.setStringList(_keyNativeRequestsMs, [
        for (final ms in kept) '$ms',
      ]);
    } on Exception catch (e) {
      _log.error('markNativeRequested failed: $e', e);
    }
    await markShown();
  }

  /// Ends a due prompt without recording anything, for example when another
  /// nudge owns the display window or a hotkey closed the dialog.
  void deferPrompt() {
    state = state.copyWith(shouldShowPrompt: false);
  }

  /// Records that the prompt was shown and resets [shouldShowPrompt].
  Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Safe read: this key can be a bundle-ID-migrated String (see
      // shared_prefs_safe_read.dart).
      final count = (readIntPrefSafe(prefs, _keyShownCount) ?? 0) + 1;
      await prefs.setInt(
        _keyLastShownMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt(_keyShownCount, count);
    } on Exception catch (e) {
      _log.error('markShown failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Dismisses the prompt.
  ///
  /// If [permanent] is `true`, the prompt will never appear again.
  /// Otherwise, it is snoozed for [_notNowDaysBetweenPrompts] days —
  /// materially longer than the [_minDaysBetweenPrompts] cooldown that follows
  /// a completed review action ([markShown]).
  Future<void> dismiss({required bool permanent}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (permanent) {
        await prefs.setBool(_keyPermanentlyDismissed, true);
      } else {
        // Snooze: record the current time under the dedicated snooze key so
        // the longer "not now" cooldown applies independently of the shorter
        // post-action cooldown.
        await prefs.setInt(
          _keyLastSnoozeMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } on Exception catch (e) {
      _log.error('dismiss failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global review prompt provider.
final reviewPromptProvider =
    NotifierProvider<ReviewPromptNotifier, ReviewPromptState>(
      ReviewPromptNotifier.new,
    );

/// Whether the user chose "Never ask again" for the rating reminder.
final reviewPromptOptOutProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return readBoolPrefSafe(prefs, _keyPermanentlyDismissed) == true;
});

/// Lifts the "Never ask again" choice. Shown count, snooze and cooldowns are
/// left as they are, so the reminder still follows the usual pauses.
Future<void> clearReviewPromptOptOut() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_keyPermanentlyDismissed);
}

/// Active history entries minus those whose dictation's paste failed
/// (GR-012). Shared by the review and the support prompt. The failed entries
/// are looked up by id, so an entry that history trimming or deletion has
/// moved out of the active set stops counting against the total, and an
/// entry counts at most once.
Future<int> countEligibleRecordings(
  SharedPreferences prefs,
  HistoryDatabase db,
) async {
  final ids = _readUnpastedEntryIds(prefs);
  var activeUnpasted = 0;
  if (ids.isNotEmpty) {
    final states = await db.activeStateOfEntries(ids);
    // Rows that no longer exist at all can never count again: forget them.
    final kept = [
      for (final id in ids)
        if (states.containsKey(id)) id,
    ];
    if (kept.length != ids.length) {
      await prefs.setStringList(_keyUnpastedEntryIds, kept);
    }
    activeUnpasted = kept.where((id) => states[id] == true).length;
  }
  final eligible = await db.countActive() - activeUnpasted;
  return eligible < 0 ? 0 : eligible;
}

/// Entry ids of the stored failed-paste dictations. A missing or foreign-typed
/// value reads as none.
List<String> _readUnpastedEntryIds(SharedPreferences prefs) {
  final raw = prefs.get(_keyUnpastedEntryIds);
  if (raw is! List<String>) return <String>[];
  return List<String>.of(raw);
}

/// Epoch-millisecond times of the stored native store rating requests. A
/// missing or foreign-typed value reads as no requests.
List<int> _readNativeRequestTimes(SharedPreferences prefs) {
  final raw = prefs.get(_keyNativeRequestsMs);
  if (raw is! List<String>) return const [];
  return [
    for (final s in raw)
      if (int.tryParse(s) != null) int.parse(s),
  ];
}
