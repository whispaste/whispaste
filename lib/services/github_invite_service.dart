/// GitHub star invitation for Store builds (Mac App Store, Microsoft Store).
///
/// Store builds get no GitHub option in the rating dialog, so this separate,
/// later nudge offers the repository instead. It is independent of the native
/// store rating request: it has its own SharedPreferences keys, its own
/// milestone, and it never relates to the rating itself (no stars scale, no
/// satisfaction question, no gating).
///
/// Rules (growth review, ledger "Freigabe GitHub-Einladung"):
///  - Store channel only. Other channels keep their own dialog.
///  - Milestone: at least [_minRecordings] active recordings, which is later
///    than the native rating request.
///  - At most [_maxImpressions] displays in total across sessions.
///  - At least [_minDaysBetweenImpressions] days between two displays.
///  - "Nicht mehr fragen" is permanent. Opening GitHub also ends the invitation.
///  - Never in the same session as the native rating request (shared
///    display arbiter) and never while a recording is running (checked by
///    the watcher at display time).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/data/database.dart';
import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';
import 'shared_prefs_safe_read.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Snapshot of the GitHub invitation state.
class GitHubInviteState {
  const GitHubInviteState({
    this.shouldShowInvite = false,
    this.channel = DeployChannel.portable,
  });

  final bool shouldShowInvite;
  final DeployChannel channel;

  GitHubInviteState copyWith({
    bool? shouldShowInvite,
    DeployChannel? channel,
  }) => GitHubInviteState(
    shouldShowInvite: shouldShowInvite ?? this.shouldShowInvite,
    channel: channel ?? this.channel,
  );
}

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const _keyImpressionCount = 'github_invite_impression_count';
const _keyLastShownMs = 'github_invite_last_shown';
const _keyPermanentlyDismissed = 'github_invite_permanently_dismissed';
const _keyStarOpened = 'github_invite_star_opened';

/// Recordings before the invitation is eligible. Deliberately later than the
/// native rating request (12 recordings).
const _minRecordings = 40;

/// Hard cap of displays across all sessions.
const _maxImpressions = 2;

/// Minimum days between two displays, also after "Später".
const _minDaysBetweenImpressions = 30;

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Decides when the GitHub invitation is due. Call [checkAndMaybeInvite]
/// after a successful transcription, like the other nudges.
class GitHubInviteNotifier extends Notifier<GitHubInviteState> {
  static final _log = AppLogger('GitHubInvite');

  @override
  GitHubInviteState build() {
    final channel = ref.read(deployChannelProvider);
    return GitHubInviteState(channel: channel);
  }

  /// Sets [GitHubInviteState.shouldShowInvite] when all rules are met.
  /// [now] is injectable for testing.
  Future<void> checkAndMaybeInvite({DateTime? now}) async {
    try {
      if (state.channel != DeployChannel.store) return;

      final prefs = await SharedPreferences.getInstance();
      if (readBoolPrefSafe(prefs, _keyPermanentlyDismissed) == true) return;
      if (readBoolPrefSafe(prefs, _keyStarOpened) == true) return;

      final impressions = readIntPrefSafe(prefs, _keyImpressionCount) ?? 0;
      if (impressions >= _maxImpressions) return;

      final current = now ?? DateTime.now();
      final lastShownMs = readIntPrefSafe(prefs, _keyLastShownMs) ?? 0;
      if (lastShownMs > 0 &&
          current
                  .difference(DateTime.fromMillisecondsSinceEpoch(lastShownMs))
                  .inDays <
              _minDaysBetweenImpressions) {
        return;
      }

      final db = ref.read(historyDatabaseProvider);
      final count = await db.countActive();
      if (count < _minRecordings) return;

      _log.info('invite due (recordings=$count, impressions=$impressions)');
      state = state.copyWith(shouldShowInvite: true);
    } on Exception catch (e) {
      _log.error('invite check failed: $e', e);
    }
  }

  /// Ends a due invitation without recording anything (for example while a
  /// recording runs, or when another prompt owns the display window).
  void deferInvite() {
    state = state.copyWith(shouldShowInvite: false);
  }

  /// Records that the invitation was displayed. Counts toward the cap.
  Future<void> recordImpression({DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (readIntPrefSafe(prefs, _keyImpressionCount) ?? 0) + 1;
      await prefs.setInt(_keyImpressionCount, count);
      await prefs.setInt(
        _keyLastShownMs,
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } on Exception catch (e) {
      _log.error('recordImpression failed: $e', e);
    }
  }

  /// The user opened the repository from the invitation. No further invites.
  Future<void> markStarOpened() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyStarOpened, true);
    } on Exception catch (e) {
      _log.error('markStarOpened failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowInvite: false);
    }
  }

  /// Ends the invitation. [permanent] is "Nicht mehr fragen". Otherwise the
  /// 30-day spacing from [recordImpression] applies ("Später" / dismissed).
  Future<void> dismiss({required bool permanent}) async {
    try {
      if (permanent) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_keyPermanentlyDismissed, true);
      }
    } on Exception catch (e) {
      _log.error('dismiss failed: $e', e);
    } finally {
      state = state.copyWith(shouldShowInvite: false);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global GitHub invitation provider.
final githubInviteProvider =
    NotifierProvider<GitHubInviteNotifier, GitHubInviteState>(
      GitHubInviteNotifier.new,
    );
