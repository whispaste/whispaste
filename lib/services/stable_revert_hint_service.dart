/// Edge-case hint for switching Beta → Stable **before** the corresponding
/// stable version has shipped (PRD §7.3, AC-7).
///
/// Sparkle/WinSparkle never downgrade. If a user installs a beta
/// (`X.Y.Z-beta.N`) and then flips the release-channel toggle back to
/// Stable while the stable feed still serves an older `X.Y.(Z-1)`, the
/// self-updater silently does nothing — no update is offered, and the user
/// is stuck on the beta with no feedback. This module detects that edge
/// case (fetch the *stable* appcast, parse its version, compare against the
/// installed version) and surfaces a one-time hint pointing at the manual
/// stable download (GitHub Releases). No silent downgrade, no auto-download.
///
/// After a stable promotion (issue 05 — the stable feed now serves
/// `X.Y.Z` or newer), the comparison flips and no hint is shown; the normal
/// auto-update path (`auto_updater_service.dart`) takes over instead.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_info.dart';
import '../core/logging/app_logger.dart';
import '../core/semver.dart' as semver;
import 'auto_updater_service.dart';
import 'http_model_fetcher.dart' show buildDioWithSentry;
import 'update_channel_service.dart';

final _log = AppLogger('StableRevertHint');

// ---------------------------------------------------------------------------
// Pure parsing — no network, fully unit-testable
// ---------------------------------------------------------------------------

final _shortVersionStringPattern = RegExp(
  r'<sparkle:shortVersionString>\s*([^<\s]+)\s*</sparkle:shortVersionString>',
);
final _enclosureVersionAttrPattern = RegExp(r'sparkle:version="([^"]+)"');

/// Extracts the release version from a Sparkle appcast XML document.
///
/// Prefers `<sparkle:shortVersionString>` (the human-facing SemVer string);
/// falls back to the `sparkle:version` enclosure attribute. Returns `null`
/// when neither is present (malformed/empty feed — callers must treat that
/// as "no comparison possible", never as "hint due").
@visibleForTesting
String? parseAppcastVersion(String xml) {
  final shortVersion = _shortVersionStringPattern.firstMatch(xml)?.group(1);
  if (shortVersion != null && shortVersion.isNotEmpty) return shortVersion;
  final attrVersion = _enclosureVersionAttrPattern.firstMatch(xml)?.group(1);
  return (attrVersion != null && attrVersion.isNotEmpty) ? attrVersion : null;
}

// ---------------------------------------------------------------------------
// Pure SemVer precedence comparison — no network, fully unit-testable
// ---------------------------------------------------------------------------

/// Returns `true` when [installed] has strictly higher SemVer precedence
/// than [stableLatest] — the edge case from PRD §7.3: the installed beta is
/// ahead of what the stable feed currently offers, so Sparkle/WinSparkle
/// cannot present an update (they never downgrade).
///
/// Returns `false` (never shows the hint) when either version fails to
/// parse — an unparseable feed must not be treated as "ahead". Delegates to
/// the shared `core/semver.dart` comparator (see its doc for precedence
/// rules).
@visibleForTesting
bool isInstalledAheadOfStable(String installed, String stableLatest) {
  final a = semver.parseSemver(installed);
  final b = semver.parseSemver(stableLatest);
  if (a == null || b == null) return false;
  return semver.compareParsedSemver(a, b) > 0;
}

// ---------------------------------------------------------------------------
// Network seam — overridable in tests, defaults to a real fetch
// ---------------------------------------------------------------------------

/// Fetches the raw appcast XML body at [url]. Overridable in tests so the
/// comparison flow can be exercised end-to-end without a real network call.
@visibleForTesting
Future<String> Function(String url) fetchAppcastFn = _defaultFetchAppcast;

Future<String> _defaultFetchAppcast(String url) async {
  final dio = buildDioWithSentry(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  );
  try {
    final response = await dio.get<String>(url);
    return response.data ?? '';
  } finally {
    dio.close();
  }
}

// ---------------------------------------------------------------------------
// State + Notifier
// ---------------------------------------------------------------------------

/// Whether the "beta ahead of stable" hint should be shown, and the version
/// to link to when it is.
class StableRevertHintState {
  const StableRevertHintState({this.visible = false, this.stableVersion});

  final bool visible;
  final String? stableVersion;
}

/// Drives the one-time "beta ahead of stable" hint (PRD §7.3, AC-7).
///
/// [checkAfterSwitchToStable] is called exactly once — from the release-
/// channel toggle's `onChanged` handler when the user switches to Stable —
/// never from `build()`/rebuilds, so the hint is not re-evaluated on every
/// settings-page render (only on the explicit switch action). [dismiss]
/// clears it; the state stays cleared until the next switch-to-stable event.
class StableRevertHintNotifier extends Notifier<StableRevertHintState> {
  @override
  StableRevertHintState build() => const StableRevertHintState();

  /// Fetches the stable appcast, parses its version, and shows the hint iff
  /// the installed version is ahead of it. Never throws — a broken/offline
  /// fetch just skips the hint (no false positive, no crash).
  Future<void> checkAfterSwitchToStable({
    String? installedVersionOverride,
  }) async {
    final installed = installedVersionOverride ?? appVersion;
    try {
      final xml = await fetchAppcastFn(appcastFeedUrl(UpdateChannel.stable));
      final stableVersion = parseAppcastVersion(xml);
      if (stableVersion == null) {
        _log.debug('Stable appcast had no parseable version — skipping hint');
        state = const StableRevertHintState();
        return;
      }
      state = isInstalledAheadOfStable(installed, stableVersion)
          ? StableRevertHintState(visible: true, stableVersion: stableVersion)
          : const StableRevertHintState();
    } on Exception catch (e) {
      _log.debug('Stable-feed revert check failed (non-fatal): $e');
      state = const StableRevertHintState();
    }
  }

  /// Dismisses the hint. Stays dismissed until the next switch-to-stable.
  void dismiss() {
    state = const StableRevertHintState();
  }
}

final stableRevertHintProvider =
    NotifierProvider<StableRevertHintNotifier, StableRevertHintState>(
      StableRevertHintNotifier.new,
    );
