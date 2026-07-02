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

class _ParsedVersion {
  const _ParsedVersion(this.core, this.preRelease);

  /// [major, minor, patch].
  final List<int> core;

  /// e.g. `beta.1`, or `null` for a plain release.
  final String? preRelease;
}

_ParsedVersion? _parseVersion(String version) {
  final clean = version.startsWith('v') ? version.substring(1) : version;
  final noBuild = clean.split('+').first; // strip build metadata ("+4")
  final dashIndex = noBuild.indexOf('-');
  final corePart = dashIndex == -1 ? noBuild : noBuild.substring(0, dashIndex);
  final preRelease = dashIndex == -1 ? null : noBuild.substring(dashIndex + 1);
  final parts = corePart.split('.');
  if (parts.length < 3) return null;
  try {
    final core = [
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    ];
    return _ParsedVersion(
      core,
      (preRelease?.isEmpty ?? true) ? null : preRelease,
    );
  } on FormatException {
    return null;
  }
}

/// SemVer pre-release precedence: dot-separated identifiers compared
/// left-to-right, numeric identifiers compared numerically, everything else
/// lexically. A version with fewer identifiers has lower precedence when the
/// shared prefix is equal (per semver.org §11).
int _comparePreRelease(String a, String b) {
  final aParts = a.split('.');
  final bParts = b.split('.');
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < len; i++) {
    final an = int.tryParse(aParts[i]);
    final bn = int.tryParse(bParts[i]);
    final cmp = (an != null && bn != null)
        ? an.compareTo(bn)
        : aParts[i].compareTo(bParts[i]);
    if (cmp != 0) return cmp;
  }
  return aParts.length.compareTo(bParts.length);
}

/// Returns `true` when [installed] has strictly higher SemVer precedence
/// than [stableLatest] — the edge case from PRD §7.3: the installed beta is
/// ahead of what the stable feed currently offers, so Sparkle/WinSparkle
/// cannot present an update (they never downgrade).
///
/// Returns `false` (never shows the hint) when either version fails to
/// parse — an unparseable feed must not be treated as "ahead".
@visibleForTesting
bool isInstalledAheadOfStable(String installed, String stableLatest) {
  final a = _parseVersion(installed);
  final b = _parseVersion(stableLatest);
  if (a == null || b == null) return false;

  for (var i = 0; i < 3; i++) {
    if (a.core[i] != b.core[i]) return a.core[i] > b.core[i];
  }
  // Equal numeric core — SemVer precedence: a plain release outranks a
  // pre-release of the same core version.
  if (a.preRelease == null && b.preRelease == null) return false; // equal
  if (a.preRelease == null) {
    return true; // installed=release, stable=pre-release
  }
  if (b.preRelease == null) {
    return false; // installed=pre-release, stable=release
  }
  return _comparePreRelease(a.preRelease!, b.preRelease!) > 0;
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
