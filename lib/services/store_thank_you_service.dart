/// Store thank-you hint service — manages the one-time "Danke für deine
/// Unterstützung" hint shown to Store-channel users after onboarding.
///
/// Trigger conditions (all must hold):
///   - App was installed via [DeployChannel.store].
///   - The [_keyShown] SharedPreferences flag is not yet set.
///   - Onboarding has been completed in this or a previous session.
///
/// After the hint is shown, [StoreThankYouNotifier.markShown] persists the
/// flag so the hint never repeats across app restarts.
///
/// The pure [shouldShowStoreThankYou] function is extracted at the top level
/// so unit tests can assert the gating logic without any side effects.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/logging/app_logger.dart';
import 'deploy_channel_service.dart';

final _log = AppLogger('StoreThankYou');

// ---------------------------------------------------------------------------
// SharedPreferences key
// ---------------------------------------------------------------------------

const _keyShown = 'store_thank_you_shown';

// ---------------------------------------------------------------------------
// Pure gating predicate
// ---------------------------------------------------------------------------

/// Returns `true` when the one-time store thank-you hint should be shown.
///
/// Extracted as a top-level function so unit tests can assert the complete
/// gating matrix without touching providers, SharedPreferences, or widgets.
///
/// [channel] must be [DeployChannel.store] and [flagAlreadySet] must be
/// `false` for the predicate to be `true`. All other channel/flag combinations
/// return `false`.
bool shouldShowStoreThankYou({
  required DeployChannel channel,
  required bool flagAlreadySet,
}) => channel == DeployChannel.store && !flagAlreadySet;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Snapshot of the store thank-you hint state.
class StoreThankYouState {
  const StoreThankYouState({this.shouldShow = false});

  final bool shouldShow;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the one-time store thank-you hint lifecycle.
///
/// Typical usage (handled automatically by [StoreThankYouWatcher]):
///   1. After onboarding completes, call [checkAndMaybeShow].
///   2. When [shouldShow] becomes `true`, surface the hint dialog.
///   3. Call [markShown] (regardless of which button the user tapped).
class StoreThankYouNotifier extends Notifier<StoreThankYouState> {
  @override
  StoreThankYouState build() => const StoreThankYouState();

  /// Checks conditions and, if met, transitions [shouldShow] to `true`.
  ///
  /// No-ops when [onboardingCompleted] is `false` or the prefs flag is already
  /// set.  Safe to call multiple times — the prefs flag prevents double-shows.
  Future<void> checkAndMaybeShow({required bool onboardingCompleted}) async {
    if (!onboardingCompleted) return;
    try {
      final channel = ref.read(deployChannelProvider);
      final prefs = await SharedPreferences.getInstance();
      final flagSet = prefs.getBool(_keyShown) ?? false;

      if (shouldShowStoreThankYou(channel: channel, flagAlreadySet: flagSet)) {
        _log.info('Store thank-you: conditions met, scheduling hint');
        state = const StoreThankYouState(shouldShow: true);
      }
    } on Exception catch (e) {
      _log.debug('Store thank-you check failed (non-fatal): $e');
    }
  }

  /// Persists the "already shown" flag and resets [shouldShow] to `false`.
  ///
  /// Idempotent — safe to call multiple times (e.g., once from a button handler
  /// and once from the dialog-close teardown path as a safety net).
  Future<void> markShown() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyShown, true);
      _log.info('Store thank-you: shown flag persisted');
    } on Exception catch (e) {
      _log.debug('Store thank-you markShown failed (non-fatal): $e');
    } finally {
      state = const StoreThankYouState(shouldShow: false);
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global store thank-you hint provider.
final storeThankYouProvider =
    NotifierProvider<StoreThankYouNotifier, StoreThankYouState>(
      StoreThankYouNotifier.new,
    );
