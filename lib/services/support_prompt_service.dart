/// Support prompt service — tracks usage milestones and surfaces a
/// support/sponsor nudge after the user has had substantial positive
/// experience with the app.
///
/// Mechanically analogous to [ReviewPromptNotifier] (`review_prompt_service.dart`)
/// but with entirely independent persisted state — its own SharedPreferences
/// keys and its own recording-count threshold. The two prompts are never
/// coupled through shared counters; they are only coordinated in *timing*
/// (see [checkAndMaybePrompt]) so they never appear in close succession.
///
/// No resolution is ever permanent. An explicit dismiss buys a 90-day snooze;
/// opening a sponsoring link buys a 9-month quiet period, after which exactly
/// one recurring-sponsoring follow-up is offered. Regardless of path, a hard
/// cap of [_impressionCap] total impressions per install is enforced — see
/// CONTEXT.md §6.8.
///
/// Uses SharedPreferences to persist prompt history across sessions.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/database.dart';
import 'review_prompt_service.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Which prompt copy/variant is due to be shown.
enum SupportPromptKind {
  /// The regular support/sponsor ask.
  initial,

  /// The one-time, distinct follow-up offering to turn a prior link click
  /// into recurring monthly sponsoring. Only reachable after [initial] was
  /// resolved via a link click and the post-link quiet period has elapsed.
  recurringFollowUp,
}

/// Snapshot of the support prompt service state.
class SupportPromptState {
  const SupportPromptState({
    this.shouldShowPrompt = false,
    this.kind = SupportPromptKind.initial,
  });

  final bool shouldShowPrompt;
  final SupportPromptKind kind;

  SupportPromptState copyWith({
    bool? shouldShowPrompt,
    SupportPromptKind? kind,
  }) => SupportPromptState(
    shouldShowPrompt: shouldShowPrompt ?? this.shouldShowPrompt,
    kind: kind ?? this.kind,
  );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

/// Total number of times the prompt (in any variant) has been shown.
const _keyImpressionCount = 'support_prompt_impression_count';

/// Timestamp of the last explicit dismiss — starts a [_snoozeDays] snooze.
const _keySnoozeMs = 'support_prompt_snooze_ms';

/// Timestamp of the last sponsoring-link click — starts a
/// [_postLinkQuietDays] quiet period before the recurring follow-up.
const _keyPostLinkMs = 'support_prompt_post_link_ms';

/// Whether a sponsoring link has ever been opened — gates whether the next
/// eligible show is the recurring follow-up rather than the initial ask.
const _keyLinkClicked = 'support_prompt_link_clicked';

/// Whether the one-time recurring follow-up has already been shown — once
/// `true`, the prompt never shows again regardless of the impression cap.
const _keyFollowUpShown = 'support_prompt_followup_shown';

/// Hard cap on total impressions (any variant) per install. Independent of
/// resolution path — see CONTEXT.md §6.8.
const _impressionCap = 3;

/// Snooze length after an explicit dismiss.
const _snoozeDays = 90;

/// Quiet period after a sponsoring-link click, before the one-time recurring
/// follow-up becomes eligible. ~9 months at 30 days/month, matching this
/// codebase's existing day-based cooldown convention.
const _postLinkQuietDays = 270;

/// Minimum recordings before the support prompt is eligible to show.
///
/// Deliberately much higher than the review prompt's 12-recording threshold
/// (see `_minRecordings` in `review_prompt_service.dart`) so the two moments
/// read as clearly distinct usage milestones rather than back-to-back asks:
/// by 40 completed recordings a user has an established, durable habit with
/// the app, which is a materially stronger signal for a support ask than the
/// review prompt's "getting started" threshold.
const _minRecordings = 40;

/// Read-only coordination keys — these are [ReviewPromptNotifier]'s own
/// persisted key *names*, duplicated here (not imported, since they are
/// library-private in `review_prompt_service.dart`) purely so this service
/// can check — never write — whether the review prompt was recently shown
/// or snoozed. This is a one-directional, read-only mutual-exclusion check;
/// it does not create any shared counter or mutable state between the two
/// services.
const _reviewKeyLastShownMs = 'review_prompt_last_shown';
const _reviewKeyLastSnoozeMs = 'review_prompt_last_snooze';

/// Coordination window (days). If the review prompt was shown or snoozed
/// within this many days, the support prompt stays silent this check —
/// ensuring the two nudges never land in close temporal proximity. Matches
/// the order of magnitude of the review prompt's own cooldowns (30/60 days).
const _coordinationWindowDays = 30;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages when to show the in-app support/sponsor prompt.
///
/// Call [checkAndMaybePrompt] after a successful transcription to evaluate
/// whether conditions are met. When [state.shouldShowPrompt] becomes `true`,
/// show the support dialog and call [markResolved] afterward.
class SupportPromptNotifier extends Notifier<SupportPromptState> {
  @override
  SupportPromptState build() => const SupportPromptState();

  /// Checks whether conditions are met and, if so, sets
  /// [SupportPromptState.shouldShowPrompt] to `true` with the appropriate
  /// [SupportPromptState.kind].
  ///
  /// Conditions (in order):
  /// 1. The impression cap ([_impressionCap]) has not been reached.
  /// 2. The one-time recurring follow-up has not already been shown.
  /// 3. Total active recordings >= [_minRecordings].
  /// 4. The review prompt is not currently pending in this session, and was
  ///    not shown/snoozed within [_coordinationWindowDays] days — this is the
  ///    mutual-exclusion-in-timing check; it never reads or writes the review
  ///    prompt's own counter, only its shown/snooze timestamps.
  /// 5. Depending on whether a sponsoring link was ever clicked: either the
  ///    post-link quiet period ([_postLinkQuietDays]) has elapsed (→ shows
  ///    the recurring follow-up), or no dismiss snooze ([_snoozeDays]) is
  ///    currently active (→ shows the initial ask).
  Future<void> checkAndMaybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final impressions = prefs.getInt(_keyImpressionCount) ?? 0;
      if (impressions >= _impressionCap) return;

      // The recurring follow-up is one-time; once shown, nothing is left to
      // offer regardless of remaining impression budget.
      if (prefs.getBool(_keyFollowUpShown) == true) return;

      final db = ref.read(historyDatabaseProvider);
      final count = await db.countActive();
      if (count < _minRecordings) return;

      // In-session guard: if the review prompt is currently pending display,
      // never fire the support prompt alongside it.
      if (ref.read(reviewPromptProvider).shouldShowPrompt) return;

      // Cross-session guard: skip if the review prompt was shown or snoozed
      // recently, so the two nudges stay spaced apart in time.
      final now = DateTime.now();
      final reviewLastShownMs = prefs.getInt(_reviewKeyLastShownMs) ?? 0;
      if (reviewLastShownMs > 0 &&
          now
                  .difference(
                    DateTime.fromMillisecondsSinceEpoch(reviewLastShownMs),
                  )
                  .inDays <
              _coordinationWindowDays) {
        return;
      }
      final reviewLastSnoozeMs = prefs.getInt(_reviewKeyLastSnoozeMs) ?? 0;
      if (reviewLastSnoozeMs > 0 &&
          now
                  .difference(
                    DateTime.fromMillisecondsSinceEpoch(reviewLastSnoozeMs),
                  )
                  .inDays <
              _coordinationWindowDays) {
        return;
      }

      if (prefs.getBool(_keyLinkClicked) == true) {
        final postLinkMs = prefs.getInt(_keyPostLinkMs) ?? 0;
        if (postLinkMs == 0 ||
            now
                    .difference(DateTime.fromMillisecondsSinceEpoch(postLinkMs))
                    .inDays <
                _postLinkQuietDays) {
          return;
        }
        dev.log(
          'Support prompt: recurring follow-up eligible (recordings=$count)',
          name: 'SupportPrompt',
        );
        state = state.copyWith(
          shouldShowPrompt: true,
          kind: SupportPromptKind.recurringFollowUp,
        );
        return;
      }

      final snoozeMs = prefs.getInt(_keySnoozeMs) ?? 0;
      if (snoozeMs > 0 &&
          now.difference(DateTime.fromMillisecondsSinceEpoch(snoozeMs)).inDays <
              _snoozeDays) {
        return;
      }

      dev.log(
        'Support prompt: conditions met (recordings=$count)',
        name: 'SupportPrompt',
      );
      state = state.copyWith(
        shouldShowPrompt: true,
        kind: SupportPromptKind.initial,
      );
    } on Exception catch (e) {
      dev.log('Support prompt check failed: $e', name: 'SupportPrompt');
    }
  }

  /// Records an explicit dismiss ("never ask again" / "no thanks").
  ///
  /// For the initial ask, this starts a [_snoozeDays] snooze — not a
  /// permanent flag. For the recurring follow-up, there is nothing left to
  /// offer afterward, so it marks the follow-up as shown. Either way, this
  /// counts toward the hard [_impressionCap].
  Future<void> dismiss() async {
    final kind = state.kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _recordImpression(prefs);
      if (kind == SupportPromptKind.recurringFollowUp) {
        await prefs.setBool(_keyFollowUpShown, true);
      } else {
        await prefs.setInt(_keySnoozeMs, DateTime.now().millisecondsSinceEpoch);
      }
    } on Exception catch (e) {
      dev.log('Support prompt dismiss failed: $e', name: 'SupportPrompt');
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Records that a sponsoring link (GitHub Sponsors/Ko-fi) was opened.
  ///
  /// For the initial ask, this starts the [_postLinkQuietDays] quiet period
  /// after which the one-time recurring follow-up becomes eligible. For the
  /// recurring follow-up itself, there is nothing left to offer afterward, so
  /// it marks the follow-up as shown. Either way, this counts toward the hard
  /// [_impressionCap].
  Future<void> markLinkOpened() async {
    final kind = state.kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      await _recordImpression(prefs);
      if (kind == SupportPromptKind.recurringFollowUp) {
        await prefs.setBool(_keyFollowUpShown, true);
      } else {
        await prefs.setBool(_keyLinkClicked, true);
        await prefs.setInt(
          _keyPostLinkMs,
          DateTime.now().millisecondsSinceEpoch,
        );
      }
    } on Exception catch (e) {
      dev.log(
        'Support prompt markLinkOpened failed: $e',
        name: 'SupportPrompt',
      );
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
  }

  /// Increments the total impression counter — called by every resolution
  /// path ([dismiss], [markLinkOpened]), regardless of variant.
  Future<void> _recordImpression(SharedPreferences prefs) async {
    final impressions = (prefs.getInt(_keyImpressionCount) ?? 0) + 1;
    await prefs.setInt(_keyImpressionCount, impressions);
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global support prompt provider.
final supportPromptProvider =
    NotifierProvider<SupportPromptNotifier, SupportPromptState>(
      SupportPromptNotifier.new,
    );
