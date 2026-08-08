/// One-time notice for a macOS Accessibility (TCC) permission reset that
/// coincided with an app update.
///
/// Background (2026-07-21 investigation, Sentry FLUTTER_WHISPASTE-BC/the
/// ad-hoc-signed-Sequoia migration): switching an installed app's code-
/// signing identity — e.g. the ad-hoc → Apple Developer-ID signing
/// migration a user's app went through on its way to a stable-signed
/// release — makes macOS treat the update as a different app for TCC
/// purposes and silently drops the Auto-Paste grant. The only way to
/// discover this today is stumbling into Settings → After Transcription;
/// there is no proactive nudge right after the update that caused it.
///
/// Design mirrors `legacy_residue_cleanup.dart`: the decision
/// ([shouldShowTccResetNotice]) is a pure function, fully testable without
/// SharedPreferences. The gate ([maybeMarkTccResetNoticeVersion]) is a thin
/// wrapper that persists "the notice question has been decided for version
/// X" so it is asked at most once per app version — not on every launch,
/// and never for a version the notice has already fired (or explicitly
/// skipped) for.
library;

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../core/onboarding/onboarding_surface.dart';
import 'paster.dart';

final _log = AppLogger('TccResetNotice');

// ---------------------------------------------------------------------------
// Pure decision function
// ---------------------------------------------------------------------------

/// Whether the "your Auto-Paste permission was reset" notice should fire.
///
/// `true` iff **all** of:
/// - [lastSeenVersion] is non-null (a prior launch was recorded — a fresh
///   install has no "reset" to report; onboarding handles that case) AND
///   differs from [currentVersion] (a real update just happened),
/// - the onboarding surface is not on top — [onboardingCompleted] is `true`
///   and [onboardingManuallyOpen] is `false`. Whoever is looking at the
///   five-step flow already has its dedicated Auto-Paste step in front of
///   them, whether that is a first run or a review reopened from Settings.
/// - [isMacOS] is `true` (the only platform where TCC/Accessibility applies),
/// - [capabilityStatus] is [PasteCapabilityStatus.permissionMissing].
///
/// Pure function — no I/O, no providers. Fully unit-testable.
bool shouldShowTccResetNotice({
  required String? lastSeenVersion,
  required String currentVersion,
  required bool onboardingCompleted,
  required bool isMacOS,
  required PasteCapabilityStatus? capabilityStatus,
  bool onboardingManuallyOpen = false,
}) {
  if (lastSeenVersion == null) return false;
  if (lastSeenVersion == currentVersion) return false;
  if (onboardingSurfaceActive(
    onboardingCompleted: onboardingCompleted,
    manuallyOpen: onboardingManuallyOpen,
  )) {
    return false;
  }
  if (!isMacOS) return false;
  return capabilityStatus == PasteCapabilityStatus.permissionMissing;
}

// ---------------------------------------------------------------------------
// Version-gated wrapper — decides (and records) at most once per app version
// ---------------------------------------------------------------------------

const _keyLastSeenVersionForTccNotice = 'tcc_reset_notice_last_seen_version';

/// Runs [shouldShowTccResetNotice] against the persisted "last seen version"
/// and [currentVersion], then always advances the persisted version to
/// [currentVersion] — so the question is decided at most once per version,
/// regardless of the answer.
///
/// Fire-and-forget safe: any SharedPreferences failure is caught and logged;
/// `false` is returned (never nag on a broken prefs read/write).
Future<bool> maybeMarkTccResetNoticeVersion({
  required String currentVersion,
  required bool onboardingCompleted,
  required bool isMacOS,
  required PasteCapabilityStatus? capabilityStatus,
  bool onboardingManuallyOpen = false,
}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenVersion = prefs.getString(_keyLastSeenVersionForTccNotice);
    final shouldShow = shouldShowTccResetNotice(
      lastSeenVersion: lastSeenVersion,
      currentVersion: currentVersion,
      onboardingCompleted: onboardingCompleted,
      isMacOS: isMacOS,
      capabilityStatus: capabilityStatus,
      onboardingManuallyOpen: onboardingManuallyOpen,
    );
    await prefs.setString(_keyLastSeenVersionForTccNotice, currentVersion);
    if (shouldShow) {
      _log.info(
        'TCC reset notice: showing (last=$lastSeenVersion current=$currentVersion)',
      );
    }
    return shouldShow;
  } catch (e) {
    _log.debug('TCC reset notice gate failed (non-fatal): $e');
    return false;
  }
}
