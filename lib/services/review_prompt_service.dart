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
// Content-free count of confirmed dictations written while "Aufnahmen
// speichern" is off (history-off): with no entry there is nothing to count.
const _keyHistoryFreeCount = 'review_prompt_history_free_count';

/// Minimum recordings before the prompt is eligible to show.
const _minRecordings = 20;

/// Minimum distinct dictation days before the prompt is eligible: a good
/// moment is steady use, not one busy afternoon.
const _minDictationDays = 3;

/// Minimum days between the first dictation and the first prompt.
const _minDaysInUse = 7;

/// Minimum days between prompt displays after a completed review action
/// (`markShown`): at most one ask in 60 days. Materially shorter than
/// [_notNowDaysBetweenPrompts].
const _minDaysBetweenPrompts = 60;

/// Minimum days before re-prompting a "not now" snooze. Materially longer than
/// [_minDaysBetweenPrompts] so a snooze buys more quiet time than a completed
/// action.
const _notNowDaysBetweenPrompts = 90;

/// Minimum days between two version-upgrade re-prompts. A version change may
/// re-activate the prompt at most once in this window (growth review R-03).
const _versionRepromptDaysBetween = 365;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages when to show the in-app review / rating prompt.
///
/// Call [checkAndMaybePrompt] after a successful transcription to evaluate
/// whether conditions are met; the Übersicht asks again on each visit. While
/// [state.shouldShowPrompt] is `true` its hint place shows the rate/share
/// card, whose actions call [markShown] or [dismiss].
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
      final now = DateTime.now();
      if (!reviewPromptUsageMet(
        recordings: count,
        dictationDays: await db.analyticsActiveDays(),
        firstDictationDay: await db.analyticsFirstActiveDay(),
        now: now,
      )) {
        return;
      }

      final version = appVersion ?? app_info.appVersion;

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

  /// Counts one confirmed dictation that was not written to the history
  /// because saving is off. Stores only a number, never the text.
  Future<void> countHistoryFreeDictation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = readHistoryFreeDictationCount(prefs) + 1;
      await prefs.setInt(_keyHistoryFreeCount, count);
    } on Exception catch (e) {
      _log.error('countHistoryFreeDictation failed: $e', e);
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

/// Whether the user chose "Don't ask again" for the rating reminder.
final reviewPromptOptOutProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return readBoolPrefSafe(prefs, _keyPermanentlyDismissed) == true;
});

/// Lifts the "Don't ask again" choice. Shown count, snooze and cooldowns are
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
  final withoutHistory = readHistoryFreeDictationCount(prefs);
  return (eligible < 0 ? 0 : eligible) + withoutHistory;
}

/// Confirmed dictations counted while history saving was off. A missing or
/// foreign-typed value reads as none. Shared with the GitHub invite count.
int readHistoryFreeDictationCount(SharedPreferences prefs) =>
    readIntPrefSafe(prefs, _keyHistoryFreeCount) ?? 0;

/// Entry ids of the stored failed-paste dictations. A missing or foreign-typed
/// value reads as none.
List<String> _readUnpastedEntryIds(SharedPreferences prefs) {
  final raw = prefs.get(_keyUnpastedEntryIds);
  if (raw is! List<String>) return <String>[];
  return List<String>.of(raw);
}

/// Whether the usage alone allows the prompt: [_minRecordings] eligible
/// recordings on at least [_minDictationDays] days, the first of them at least
/// [_minDaysInUse] days before [now]. Cooldowns and "never again" come on top.
bool reviewPromptUsageMet({
  required int recordings,
  required int dictationDays,
  required DateTime? firstDictationDay,
  required DateTime now,
}) =>
    recordings >= _minRecordings &&
    dictationDays >= _minDictationDays &&
    firstDictationDay != null &&
    now.difference(firstDictationDay).inDays >= _minDaysInUse;
