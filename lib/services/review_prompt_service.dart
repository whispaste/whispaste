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
  }) =>
      ReviewPromptState(
        shouldShowPrompt: shouldShowPrompt ?? this.shouldShowPrompt,
        channel: channel ?? this.channel,
      );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const _keyLastShownMs = 'review_prompt_last_shown';
const _keyPermanentlyDismissed = 'review_prompt_permanently_dismissed';
const _keyShownCount = 'review_prompt_shown_count';

/// Minimum recordings before the prompt is eligible to show.
const _minRecordings = 5;

/// Minimum days between prompt displays.
const _minDaysBetweenPrompts = 30;

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
  /// 2. Either never shown, or last shown > [_minDaysBetweenPrompts] days ago.
  /// 3. Total active recordings >= [_minRecordings].
  Future<void> checkAndMaybePrompt() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (prefs.getBool(_keyPermanentlyDismissed) == true) return;

      final lastShownMs = prefs.getInt(_keyLastShownMs) ?? 0;
      if (lastShownMs > 0) {
        final lastShown =
            DateTime.fromMillisecondsSinceEpoch(lastShownMs);
        final daysSince = DateTime.now().difference(lastShown).inDays;
        if (daysSince < _minDaysBetweenPrompts) return;
      }

      final db = ref.read(historyDatabaseProvider);
      final count = await db.countActive();
      if (count < _minRecordings) return;

      dev.log('Review prompt: conditions met (recordings=$count)', name: 'ReviewPrompt');
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
      await prefs.setInt(_keyLastShownMs, DateTime.now().millisecondsSinceEpoch);
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
  /// Otherwise, it is snoozed for [_minDaysBetweenPrompts] days.
  Future<void> dismiss({required bool permanent}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (permanent) {
        await prefs.setBool(_keyPermanentlyDismissed, true);
      } else {
        // Snooze: record the current time as "last shown" so the cooldown
        // starts from now.
        await prefs.setInt(
          _keyLastShownMs,
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
