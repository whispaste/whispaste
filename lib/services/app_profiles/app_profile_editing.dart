/// Pure rules of the Profile editor in Settings (ticket 13, part 2): the
/// profile limit, the new-profile id, the order, names, app rules and the
/// hotkey conflicts the editor explains. No widgets here, so the rules are
/// tested without a window.
library;

import '../hotkey_conflicts.dart' show HotkeyBinding, findHotkeyCollision;
import '../profile_hotkey_plan.dart'
    show kProfileHotkeyActionPrefix, profileHotkeyActionId;
import 'app_profile.dart';

/// The most profiles a user can keep (ticket 13: up to 9). Nine keeps the tray
/// submenu and the list of profile hotkeys readable.
const int kMaxAppProfiles = 9;

/// Whether one more profile fits under [kMaxAppProfiles].
bool canAddAppProfile(List<AppProfile> profiles) =>
    profiles.length < kMaxAppProfiles;

/// A new profile id. Stable once stored; it is also part of the hotkey action
/// id and the tray entry id.
String newAppProfileId(DateTime now) =>
    'profile-${now.microsecondsSinceEpoch.toRadixString(36)}';

/// [name] trimmed, or null when it is blank. The editor does not save a blank
/// name.
String? cleanAppProfileName(String name) {
  final trimmed = name.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The profile ids in the order after moving [id] by [delta] places: -1 moves
/// it up, +1 moves it down. An unknown id, or a move past either end, returns
/// the order unchanged.
List<String> movedAppProfileIds(
  List<AppProfile> profiles,
  String id,
  int delta,
) {
  final ids = [for (final profile in profiles) profile.id];
  final from = ids.indexOf(id);
  if (from < 0) return ids;
  final to = from + delta;
  if (to < 0 || to >= ids.length) return ids;
  ids
    ..removeAt(from)
    ..insert(to, id);
  return ids;
}

/// The name of the profile that already claims the app [identifier], when it
/// is a different profile or the same profile listed twice. Null when the
/// identifier is free (or blank). The editor refuses such a rule, because the
/// first match in profile order would otherwise decide silently.
String? appRuleClashName({
  required String identifier,
  required AppProfile profile,
  required List<AppProfile> profiles,
}) {
  final key = normalizeAppIdentifier(identifier);
  if (key == null) return null;
  for (final other in profiles) {
    for (final rule in other.rules) {
      if (rule.matchKey != key) continue;
      return other.name;
    }
  }
  return null;
}

/// Why a profile hotkey cannot be used, as the editor words it.
sealed class ProfileHotkeyConflict {
  const ProfileHotkeyConflict();
}

/// The combination has no modifier. A bare key would be grabbed system-wide.
final class ProfileHotkeyNeedsModifier extends ProfileHotkeyConflict {
  const ProfileHotkeyNeedsModifier();
}

/// Another WhisPaste hotkey already holds the combination.
final class ProfileHotkeyTakenByApp extends ProfileHotkeyConflict {
  const ProfileHotkeyTakenByApp(this.actionLabel);

  /// The translated name of that hotkey's action.
  final String actionLabel;
}

/// Another profile already holds the combination.
final class ProfileHotkeyTakenByProfile extends ProfileHotkeyConflict {
  const ProfileHotkeyTakenByProfile(this.profileName);

  final String profileName;
}

/// The conflict for giving [profileId] the combination [key] + [modifiers],
/// or null when it is free.
///
/// [appBindings] are the switched-on app hotkeys (see `activeHotkeyBindings`).
/// Other profiles are checked in both directions by default, so a new
/// combination never silently takes one from a profile. With [onlyEarlier]
/// the check mirrors the planner, which lets the first profile of the list
/// keep a combination: that is how a stored, refused hotkey is explained.
ProfileHotkeyConflict? profileHotkeyConflict({
  required String key,
  required String modifiers,
  required String profileId,
  required List<AppProfile> profiles,
  required List<HotkeyBinding> appBindings,
  bool onlyEarlier = false,
}) {
  if (modifiers.trim().isEmpty) return const ProfileHotkeyNeedsModifier();
  final profileBindings = <HotkeyBinding>[];
  for (final other in profiles) {
    if (other.id == profileId) break;
    if (!other.hasHotkey) continue;
    profileBindings.add(_bindingOf(other));
  }
  if (!onlyEarlier) {
    final seenBefore = profiles.indexWhere((p) => p.id == profileId);
    for (final other in profiles.skip(seenBefore + 1)) {
      if (other.hasHotkey) profileBindings.add(_bindingOf(other));
    }
  }
  final hit = findHotkeyCollision(
    modifiers: modifiers,
    key: key,
    bindings: [...appBindings, ...profileBindings],
  );
  if (hit == null) return null;
  if (hit.actionId.startsWith(kProfileHotkeyActionPrefix)) {
    return ProfileHotkeyTakenByProfile(hit.actionLabel);
  }
  return ProfileHotkeyTakenByApp(hit.actionLabel);
}

HotkeyBinding _bindingOf(AppProfile profile) => HotkeyBinding(
  actionId: profileHotkeyActionId(profile.id),
  actionLabel: profile.name,
  key: profile.hotkeyKey!,
  modifiers: profile.hotkeyModifiers ?? '',
);
