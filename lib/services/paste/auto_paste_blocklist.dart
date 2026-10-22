/// Decision rule for the auto-paste block list (AUF-1).
///
/// The block list is a comma-separated list of app identifiers. Each entry is
/// normalised with [normalizeAppIdentifier] (case-insensitive, trailing `.exe`
/// dropped), so `1password.exe` and `1Password` are the same entry on Windows.
///
/// Matching:
///   - macOS: exact match, or a prefix match on the bundle id at a dot boundary
///     (entry `com.1password` matches `com.1password.1password`).
///   - Windows and Linux: exact match after normalisation only.
///
/// The target is the same [AppTargetEvidence] the app-profile resolver reads,
/// so a rule and a block-list entry always agree on which app is meant.
///
/// Fail-closed (AUF-1): an empty list never blocks (today's behaviour). A
/// non-empty list with an unknown target (no evidence, blank, lookup missing
/// or failed) does not auto-paste; the transcript stays in the clipboard. This
/// applies on every platform, including macOS.
library;

import '../desktop_paste/focused_target/linux_focused_target.dart'
    show LinuxFocusStatus;
import '../app_profiles/app_profile.dart' show normalizeAppIdentifier;
import '../app_profiles/app_profile_resolver.dart' show AppTargetEvidence;

/// Outcome of [evaluateAutoPasteBlocklist].
enum AutoPasteBlocklistVerdict {
  /// Auto-paste may proceed.
  allowed,

  /// The target app is on the list.
  listed,

  /// The list is set, but the target app could not be identified.
  targetUnknown,
}

/// Whether the target app can be named in this session.
///
/// macOS (bundle id) and Windows (exe name) always report a target. On Linux
/// it depends on the session ([linuxStatus], V1 Wayland): X11 and Wayland
/// compositors WhisPaste can ask report one; GNOME without the WhisPaste
/// extension and unsupported compositors do not, so there the list fails
/// closed and the settings show a hint. A status that is still being probed
/// (null) shows no hint yet.
bool autoPasteTargetDetectionAvailable({
  required bool isLinux,
  required LinuxFocusStatus? linuxStatus,
}) =>
    !isLinux ||
    linuxStatus == null ||
    linuxStatus == LinuxFocusStatus.available;

/// macOS entries that have no dot (e.g. `Safari`). Such an entry only matches a
/// bundle id that is exactly the same, so the editor warns about it (GS-075).
List<String> autoPasteShortPrefixEntries(String raw) {
  return [
    for (final part in raw.split(','))
      if (normalizeAppIdentifier(part) case final key? when !key.contains('.'))
        key,
  ];
}

/// Normalised, non-empty entries of a raw comma-separated [raw] list.
Set<String> parseAutoPasteBlocklist(String raw) {
  return {for (final part in raw.split(',')) ?normalizeAppIdentifier(part)};
}

/// Evaluates the block list for one paste. See the library doc for the rules.
AutoPasteBlocklistVerdict evaluateAutoPasteBlocklist({
  required String raw,
  required AppTargetEvidence? target,
  required bool isMacOS,
}) {
  final entries = parseAutoPasteBlocklist(raw);
  if (entries.isEmpty) return AutoPasteBlocklistVerdict.allowed;

  final keys = {
    for (final identifier in target?.identifiers ?? const <String>[])
      ?normalizeAppIdentifier(identifier),
  };
  if (keys.isEmpty) return AutoPasteBlocklistVerdict.targetUnknown;

  for (final key in keys) {
    for (final entry in entries) {
      if (key == entry) return AutoPasteBlocklistVerdict.listed;
      if (isMacOS && key.startsWith('$entry.')) {
        return AutoPasteBlocklistVerdict.listed;
      }
    }
  }
  return AutoPasteBlocklistVerdict.allowed;
}

/// The stored entries in their written form, in order, without blanks and
/// without a second spelling of an entry that is already there (same key).
/// Old values read unchanged; this is only a view of the stored string.
List<String> autoPasteBlocklistEntries(String raw) {
  final seen = <String>{};
  return [
    for (final part in raw.split(','))
      if (part.trim() case final entry when entry.isNotEmpty)
        if (normalizeAppIdentifier(entry) case final key? when seen.add(key))
          entry,
  ];
}

/// Whether [identifier] is listed, by the same key rule the block list uses.
bool autoPasteBlocklistContains(String raw, String? identifier) {
  final key = normalizeAppIdentifier(identifier);
  if (key == null) return false;
  return parseAutoPasteBlocklist(raw).contains(key);
}

/// [raw] with [identifier] appended. Blank identifiers and identifiers that are
/// already listed (by key) leave the value unchanged.
String autoPasteBlocklistWith(String raw, String identifier) {
  final trimmed = identifier.trim();
  if (trimmed.isEmpty || autoPasteBlocklistContains(raw, trimmed)) return raw;
  return [...autoPasteBlocklistEntries(raw), trimmed].join(', ');
}

/// The identifiers typed or pasted into the manual entry field. Line breaks
/// separate entries, as do commas; each entry is trimmed and blanks are dropped.
List<String> autoPasteIdentifiersFromInput(String text) => [
  for (final part in text.split(RegExp(r'[\r\n,]+')))
    if (part.trim() case final identifier when identifier.isNotEmpty)
      identifier.trim(),
];

/// [raw] with every one of [identifiers] appended, in order (see
/// [autoPasteBlocklistWith] for the rules per entry).
String autoPasteBlocklistWithAll(String raw, Iterable<String> identifiers) {
  var value = raw;
  for (final identifier in identifiers) {
    value = autoPasteBlocklistWith(value, identifier);
  }
  return value;
}

/// [raw] without the entries that match [identifier] by key.
String autoPasteBlocklistWithout(String raw, String identifier) {
  final key = normalizeAppIdentifier(identifier);
  return [
    for (final entry in autoPasteBlocklistEntries(raw))
      if (normalizeAppIdentifier(entry) != key) entry,
  ].join(', ');
}

/// An app the user recently dictated into, from the history target app.
class RecentTargetApp {
  const RecentTargetApp({required this.identifier, required this.lastUsed});

  /// The identifier as the history stored it (bundle id, exe, WM_CLASS).
  final String identifier;

  /// When the app was last the dictation target.
  final DateTime lastUsed;
}

/// Distinct target apps of [entries], newest first. Apps are identified by
/// their normalised key, so `Chrome.exe` and `chrome` count once. Entries
/// without a target app are skipped.
List<RecentTargetApp> recentTargetApps(
  Iterable<({String? targetApp, DateTime timestamp})> entries,
) {
  final sorted = entries.toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final seen = <String>{};
  final apps = <RecentTargetApp>[];
  for (final entry in sorted) {
    final target = entry.targetApp?.trim();
    if (target == null || target.isEmpty) continue;
    final key = normalizeAppIdentifier(target);
    if (key == null || !seen.add(key)) continue;
    apps.add(RecentTargetApp(identifier: target, lastUsed: entry.timestamp));
  }
  return apps;
}
