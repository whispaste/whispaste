/// Feature spotlight notifier — drives the one-time, dismissable hint that
/// bundles every pending [FeatureSpotlightEntry] into a single showing.
///
/// Trigger conditions (all must hold, checked in [checkAndMaybeShow]):
///   - The onboarding surface is not on top: onboarding has been completed,
///     no manual review is open, and no onboarding revision run is in
///     progress (see `onboarding_surface.dart`'s `onboardingSurfaceActive`,
///     reused unmodified — a revision run has precedence).
///   - At least one registry entry applies to the current platform and is
///     not yet in `OnboardingSettings.seenFeatureSpotlightIds`.
///
/// `seenFeatureSpotlightIds` is only ever written by [dismiss] — never by
/// [checkAndMaybeShow]. That is what gives a revision run (or a manual
/// review, or an incomplete first run) precedence without losing data: the
/// check simply no-ops while any of those is active, so the same entries are
/// recomputed as still-pending on the next app start instead of being
/// silently marked seen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/settings_provider.dart';
import '../logging/app_logger.dart';
import '../onboarding/onboarding_revision.dart';
import '../onboarding/onboarding_surface.dart';
import 'feature_spotlight.dart';

final _log = AppLogger('FeatureSpotlight');

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Snapshot of the feature spotlight state — the entries currently bundled
/// into one showing, newest first.
class FeatureSpotlightState {
  const FeatureSpotlightState({this.pending = const []});

  final List<FeatureSpotlightEntry> pending;

  bool get shouldShow => pending.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Manages the feature spotlight hint lifecycle.
///
/// Typical usage (handled automatically by `WpFeatureSpotlightWatcher`):
///   1. After onboarding completes, call [checkAndMaybeShow].
///   2. When [FeatureSpotlightState.shouldShow] becomes `true`, surface the
///      hint, listing every entry in [FeatureSpotlightState.pending].
///   3. Call [dismiss] once the user closes the hint.
class FeatureSpotlightNotifier extends Notifier<FeatureSpotlightState> {
  @override
  FeatureSpotlightState build() => const FeatureSpotlightState();

  /// Checks conditions and, if any entries are pending, populates
  /// [FeatureSpotlightState.pending].
  ///
  /// No-ops while the onboarding surface is on top — see the file doc
  /// comment for why nothing is written to `seenFeatureSpotlightIds` in that
  /// case. Safe to call multiple times; an empty pending set leaves the
  /// state untouched rather than clearing an already-populated one, so a
  /// caller that re-checks after the surface clears doesn't need to guard
  /// against wiping a showing that's already in flight.
  Future<void> checkAndMaybeShow({required bool onboardingCompleted}) async {
    if (onboardingSurfaceActive(
      onboardingCompleted: onboardingCompleted,
      manuallyOpen: ref.read(onboardingManuallyOpenProvider),
      revisionRunning: ref.read(onboardingRevisionRunProvider),
    )) {
      return;
    }
    try {
      final registry = ref.read(featureSpotlightRegistryProvider);
      final seenIds = parseFeatureSpotlightSeenIds(
        ref.read(settingsProvider).value?.onboarding.seenFeatureSpotlightIds ??
            '',
      );
      final pending = pendingFeatureSpotlights(
        registry: registry,
        platform: currentOnboardingPlatform(),
        seenIds: seenIds,
      );
      if (pending.isNotEmpty) {
        _log.info(
          'Feature spotlight: ${pending.length} entr${pending.length == 1 ? 'y' : 'ies'} pending',
        );
        state = FeatureSpotlightState(pending: pending);
      }
    } on Exception catch (e) {
      _log.debug('Feature spotlight check failed (non-fatal): $e');
    }
  }

  /// Marks every currently-pending entry as seen and persists it, then
  /// clears [FeatureSpotlightState.pending].
  ///
  /// Idempotent — calling this again with the same pending set (or after it
  /// was already cleared) merges the same ids into
  /// `seenFeatureSpotlightIds` and produces the same serialized string (see
  /// `serializeFeatureSpotlightSeenIds`'s doc comment), so a double dismiss
  /// (e.g. one from a button handler and one from a safety-net teardown
  /// path) is a safe no-op rather than a second, different write.
  Future<void> dismiss() async {
    final shownIds = state.pending.map((e) => e.id).toSet();
    state = const FeatureSpotlightState();
    if (shownIds.isEmpty) return;
    try {
      final current = parseFeatureSpotlightSeenIds(
        ref.read(settingsProvider).value?.onboarding.seenFeatureSpotlightIds ??
            '',
      );
      final merged = serializeFeatureSpotlightSeenIds({
        ...current,
        ...shownIds,
      });
      await ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              onboarding: s.onboarding.copyWith(
                seenFeatureSpotlightIds: merged,
              ),
            ),
          );
      _log.info('Feature spotlight: dismissed, ${shownIds.length} marked seen');
    } on Exception catch (e) {
      _log.debug('Feature spotlight dismiss failed (non-fatal): $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global feature spotlight provider.
final featureSpotlightProvider =
    NotifierProvider<FeatureSpotlightNotifier, FeatureSpotlightState>(
      FeatureSpotlightNotifier.new,
    );
