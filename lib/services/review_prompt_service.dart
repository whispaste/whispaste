/// Review prompt service — tracks usage milestones and surfaces a rating
/// prompt after the user has had enough positive experience with the app.
///
/// Uses SharedPreferences to persist prompt history across sessions.
/// Respects the deploy channel to surface the correct review flow.
library;

import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_info.dart' as app_info;
import '../core/data/database.dart';
import 'deploy_channel_service.dart';

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

/// Minimum recordings before the prompt is eligible to show.
const _minRecordings = 12;

/// Minimum days between prompt displays after a completed review action
/// (`markShown`). Materially shorter than [_notNowDaysBetweenPrompts].
const _minDaysBetweenPrompts = 30;

/// Minimum days before re-prompting a "not now" snooze. Materially longer than
/// [_minDaysBetweenPrompts] so a snooze buys more quiet time than a completed
/// action.
const _notNowDaysBetweenPrompts = 60;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages when to show the in-app review / rating prompt.
///
/// Call [checkAndMaybePrompt] after a successful transcription to evaluate
/// whether conditions are met. When [state.shouldShowPrompt] becomes `true`,
/// show [ReviewPromptDialog] and call [markShown] or [dismiss] afterward.
class ReviewPromptNotifier extends Notifier<ReviewPromptState> {
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
  ///    (or > [_notNowDaysBetweenPrompts] after a "not now" snooze), unless a
  ///    version upgrade re-activates the prompt once.
  ///
  /// [appVersion] is the current app version used for version-change detection;
  /// it defaults to the global app version and is injectable for testing.
  Future<void> checkAndMaybePrompt({String? appVersion}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // "Never again" is permanent — no upgrade or cooldown re-activates it.
      if (prefs.getBool(_keyPermanentlyDismissed) == true) return;

      final db = ref.read(historyDatabaseProvider);
      final count = await db.countActive();
      if (count < _minRecordings) return;

      final version = appVersion ?? app_info.appVersion;

      // Version-upgrade re-prompt: a noticeable version change re-activates the
      // prompt once, overriding the snooze / shown cooldowns. The persisted
      // last-shown version is updated when the prompt becomes eligible so the
      // re-prompt fires exactly once per upgrade.
      final lastShownVersion = prefs.getString(_keyLastShownAppVersion) ?? '';
      if (version != lastShownVersion && lastShownVersion.isNotEmpty) {
        await prefs.setString(_keyLastShownAppVersion, version);
        dev.log(
          'Review prompt: version upgrade re-prompt '
          '($lastShownVersion → $version, recordings=$count)',
          name: 'ReviewPrompt',
        );
        state = state.copyWith(shouldShowPrompt: true);
        return;
      }

      // Same-version cooldowns (differential): a "not now" snooze buys more
      // quiet time than a completed review action.
      final now = DateTime.now();
      final lastShownMs = prefs.getInt(_keyLastShownMs) ?? 0;
      if (lastShownMs > 0 &&
          now
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastShownMs))
                  .inDays <
              _minDaysBetweenPrompts) {
        return;
      }
      final lastSnoozeMs = prefs.getInt(_keyLastSnoozeMs) ?? 0;
      if (lastSnoozeMs > 0 &&
          now
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastSnoozeMs))
                  .inDays <
              _notNowDaysBetweenPrompts) {
        return;
      }

      await prefs.setString(_keyLastShownAppVersion, version);
      dev.log(
        'Review prompt: conditions met (recordings=$count)',
        name: 'ReviewPrompt',
      );
      state = state.copyWith(shouldShowPrompt: true);
    } on Exception catch (e) {
      dev.log('Review prompt check failed: $e', name: 'ReviewPrompt');
    }
  }

  /// Records that the prompt was shown and resets [shouldShowPrompt].
  Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt(_keyShownCount) ?? 0) + 1;
      await prefs.setInt(
        _keyLastShownMs,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setInt(_keyShownCount, count);
    } on Exception catch (e) {
      dev.log('Review prompt markShown failed: $e', name: 'ReviewPrompt');
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
      dev.log('Review prompt dismiss failed: $e', name: 'ReviewPrompt');
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
