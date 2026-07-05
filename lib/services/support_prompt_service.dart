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

/// Snapshot of the support prompt service state.
class SupportPromptState {
  const SupportPromptState({this.shouldShowPrompt = false});

  final bool shouldShowPrompt;

  SupportPromptState copyWith({bool? shouldShowPrompt}) => SupportPromptState(
    shouldShowPrompt: shouldShowPrompt ?? this.shouldShowPrompt,
  );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

/// Own, independent persisted flag — never read or written by
/// [ReviewPromptNotifier], and this service never writes to any of its keys.
const _keyPermanentlyDismissed = 'support_prompt_permanently_dismissed';

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
  /// [SupportPromptState.shouldShowPrompt] to `true`.
  ///
  /// Conditions:
  /// 1. Not permanently dismissed (dismissal is a hard, permanent cap — see
  ///    [markResolved]).
  /// 2. Total active recordings >= [_minRecordings].
  /// 3. The review prompt is not currently pending in this session, and was
  ///    not shown/snoozed within [_coordinationWindowDays] days — this is the
  ///    mutual-exclusion-in-timing check; it never reads or writes the review
  ///    prompt's own counter, only its shown/snooze timestamps.
  Future<void> checkAndMaybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Permanent dismissal — no cooldown or upgrade re-activates it.
      if (prefs.getBool(_keyPermanentlyDismissed) == true) return;

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

      dev.log(
        'Support prompt: conditions met (recordings=$count)',
        name: 'SupportPrompt',
      );
      state = state.copyWith(shouldShowPrompt: true);
    } on Exception catch (e) {
      dev.log('Support prompt check failed: $e', name: 'SupportPrompt');
    }
  }

  /// Resolves the prompt — whichever action the user took (opening a support
  /// link, or explicitly dismissing). Per this issue's "dauerhaft
  /// dismissbar" requirement, resolution is a hard, permanent cap: the
  /// support prompt never appears again on this install once resolved, so a
  /// user who dismisses it is never asked again in short succession (or
  /// ever again this install).
  Future<void> markResolved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyPermanentlyDismissed, true);
    } on Exception catch (e) {
      dev.log('Support prompt markResolved failed: $e', name: 'SupportPrompt');
    } finally {
      state = state.copyWith(shouldShowPrompt: false);
    }
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
