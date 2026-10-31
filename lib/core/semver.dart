/// Shared SemVer parsing + precedence comparison (semver.org §11), including
/// pre-release precedence.
///
/// Extracted from `stable_revert_hint_service.dart`, which had the only
/// correct implementation in this codebase. `update_service.dart`'s prior
/// `isNewer`/`parseSemver` stripped the pre-release suffix entirely, so
/// `1.2.44-beta.6` compared equal to `1.2.44-beta.5` and beta-to-beta
/// updates were never detected as newer.
library;

/// A parsed `major.minor.patch[-prerelease][+build]` version. Build
/// metadata is discarded (semver.org §10 — it never affects precedence).
class ParsedSemver {
  const ParsedSemver(this.core, this.preRelease);

  /// [major, minor, patch].
  final List<int> core;

  /// e.g. `beta.1`, or `null` for a plain release.
  final String? preRelease;
}

/// Parses `[v]X.Y.Z[-prerelease][+build]`. Returns `null` on malformed input
/// (fewer than 3 numeric core components).
ParsedSemver? parseSemver(String version) {
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
    return ParsedSemver(
      core,
      (preRelease?.isEmpty ?? true) ? null : preRelease,
    );
  } on FormatException {
    return null;
  }
}

/// SemVer pre-release precedence (semver.org §11): dot-separated identifiers
/// compared left-to-right, numeric identifiers compared numerically,
/// everything else lexically. Fewer identifiers ranks lower when the shared
/// prefix is equal.
int comparePreRelease(String a, String b) {
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

/// Full SemVer precedence: negative/zero/positive for `a </=/> b`. A plain
/// release always outranks a pre-release of the same numeric core.
int compareParsedSemver(ParsedSemver a, ParsedSemver b) {
  for (var i = 0; i < 3; i++) {
    if (a.core[i] != b.core[i]) return a.core[i].compareTo(b.core[i]);
  }
  if (a.preRelease == null && b.preRelease == null) return 0;
  if (a.preRelease == null) return 1; // a=release, b=pre-release
  if (b.preRelease == null) return -1; // a=pre-release, b=release
  return comparePreRelease(a.preRelease!, b.preRelease!);
}

/// Returns `true` if [candidate] has strictly higher SemVer precedence than
/// [current]. Returns `false` (never claims "newer") if either fails to
/// parse.
bool isSemverNewer(String candidate, String current) {
  final a = parseSemver(candidate);
  final b = parseSemver(current);
  if (a == null || b == null) return false;
  return compareParsedSemver(a, b) > 0;
}
