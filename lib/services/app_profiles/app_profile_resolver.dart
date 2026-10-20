/// Picks the app profile for one recording (WP-33a) and decides which optional
/// context it may use.
///
/// Profile precedence, fixed and tested:
///   1. the manual choice from the dock quick menu, if it names a profile that
///      still exists (a choice of "no profile" beats any rule);
///   2. the first rule, in stored profile order and then rule order, whose
///      identifier matches the target app in front at recording start;
///   3. no profile: today's behaviour.
library;

import 'app_profile.dart';
import 'app_profile_consent.dart';

/// What the user picked in the dock quick menu. Held in memory only; it is
/// not persisted, so every app start begins with [ProfileChoiceAutomatic].
sealed class ProfileChoice {
  const ProfileChoice();
}

/// Let the target-app rules decide (the default).
final class ProfileChoiceAutomatic extends ProfileChoice {
  const ProfileChoiceAutomatic();
}

/// Use no profile for the next recording(s), even if a rule matches.
final class ProfileChoiceNone extends ProfileChoice {
  const ProfileChoiceNone();
}

/// Force one profile, regardless of the target app.
final class ProfileChoiceProfile extends ProfileChoice {
  const ProfileChoiceProfile(this.profileId);

  final String profileId;
}

/// What the detector saw for the target app at recording start.
///
/// Per-platform contract (pinned here, implemented by the native channel):
///   - macOS: [identifiers] = [bundle id], e.g. `com.apple.mail`;
///     [teamId] = code-signing team identifier, read natively from the running
///     process (never from Info.plist or user input), or `null` if unavailable.
///   - Windows: [identifiers] = [exe base name without `.exe`], e.g. `chrome`
///     for `chrome.exe`; [teamId] is always `null`.
///   - Linux X11: [identifiers] = [WM_CLASS instance], e.g. `google-chrome`
///     (the native host sends the instance only; the class normalises to the
///     same key in practice); [teamId] is always `null`.
///   - Wayland or unknown target: [identifiers] is empty, the whole evidence is
///     `null` (no profile by rule, no clipboard context).
class AppTargetEvidence {
  const AppTargetEvidence({this.identifiers = const [], this.teamId});

  final List<String> identifiers;
  final String? teamId;
}

/// The target evidence for the app in front, from the native identifier the
/// paste host reports (bundle id, exe name or WM_CLASS). Null when there is no
/// identifier, which the block list and the resolver both treat as unknown.
AppTargetEvidence? targetEvidenceFromNativeId(String? nativeId) {
  final trimmed = nativeId?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return AppTargetEvidence(identifiers: [trimmed]);
}

/// Why the resolver picked what it picked. Shown as text in the dock, never
/// as colour alone.
enum AppProfileSelection { manual, rule, none }

/// Result of [resolveAppProfile].
class ResolvedAppProfile {
  const ResolvedAppProfile(this.profile, this.selection, {this.matchedRule});

  const ResolvedAppProfile.none()
    : profile = null,
      selection = AppProfileSelection.none,
      matchedRule = null;

  final AppProfile? profile;
  final AppProfileSelection selection;

  /// The rule whose identifier matched the target by name, if any. GS-072: the
  /// binding check looks at this rule only, never at the profile's other rules.
  final AppMatchRule? matchedRule;
}

/// Finds the first rule of [profile] whose name key is one of [candidates].
AppMatchRule? _firstNameMatch(AppProfile profile, Set<String> candidates) {
  for (final rule in profile.rules) {
    final key = rule.matchKey;
    if (key != null && candidates.contains(key)) return rule;
  }
  return null;
}

Set<String> _candidatesOf(AppTargetEvidence? target) {
  if (target == null) return const {};
  return {
    for (final identifier in target.identifiers)
      ?normalizeAppIdentifier(identifier),
  };
}

/// Resolves the profile for a recording. Rule order is the stored order, so a
/// tie between two profiles always goes to the earlier one (DEV-239).
ResolvedAppProfile resolveAppProfile({
  required ProfileChoice choice,
  required List<AppProfile> profiles,
  required AppTargetEvidence? target,
}) {
  switch (choice) {
    case ProfileChoiceNone():
      return const ResolvedAppProfile.none();
    case ProfileChoiceProfile(:final profileId):
      for (final profile in profiles) {
        if (profile.id == profileId) {
          return ResolvedAppProfile(
            profile,
            AppProfileSelection.manual,
            matchedRule: _firstNameMatch(profile, _candidatesOf(target)),
          );
        }
      }
    // A stale id (profile deleted meanwhile) falls back to the automatic rules.
    case ProfileChoiceAutomatic():
      break;
  }

  final candidates = _candidatesOf(target);
  if (candidates.isEmpty) return const ResolvedAppProfile.none();
  for (final profile in profiles) {
    final rule = _firstNameMatch(profile, candidates);
    if (rule != null) {
      return ResolvedAppProfile(
        profile,
        AppProfileSelection.rule,
        matchedRule: rule,
      );
    }
  }
  return const ResolvedAppProfile.none();
}

/// Why a context source was not used. `null` on [ContextPlan.blockedBy] means
/// the source is in effect.
enum ContextBlockReason {
  /// A cloud provider needs a current, matching consent on the profile.
  consentMissing,

  /// macOS clipboard context: the matched rule has no team id, or the target
  /// reported none.
  bindingUnavailable,

  /// macOS clipboard context: the target's team id differs from the matched
  /// rule's team id.
  bindingMismatch,
}

/// The context decision for one recording. Fail-closed: any doubt yields
/// [AppProfileContextSource.none].
class ContextPlan {
  const ContextPlan(this.source, {this.blockedBy});

  final AppProfileContextSource source;
  final ContextBlockReason? blockedBy;

  bool get readsContext => source != AppProfileContextSource.none;
}

/// Decides which context source a profile may use for one recording.
///
/// - No profile, or source [AppProfileContextSource.none]: nothing is read.
/// - A cloud provider needs a consent that covers the current provider, the
///   profile's source and the current text version (see [AppProfileConsent]).
///   A local provider needs no consent; the dock indicator still shows.
/// - Selection: name-bound. The text comes from the target app itself.
/// - Clipboard on macOS: needs the matched rule (GS-072) to carry a team id
///   equal to the target's team id. Windows and Linux: the name match is enough.
ContextPlan planContext({
  required ResolvedAppProfile resolved,
  required bool providerIsLocal,
  required String providerId,
  required AppTargetEvidence? target,
  required bool isMacOS,
}) {
  final profile = resolved.profile;
  final source = profile?.contextSource ?? AppProfileContextSource.none;
  if (profile == null || source == AppProfileContextSource.none) {
    return const ContextPlan(AppProfileContextSource.none);
  }
  if (!providerIsLocal) {
    final consent = profile.consent;
    final covered =
        consent != null &&
        consent.covers(currentProviderId: providerId, source: source);
    if (!covered) {
      return const ContextPlan(
        AppProfileContextSource.none,
        blockedBy: ContextBlockReason.consentMissing,
      );
    }
  }
  if (source == AppProfileContextSource.selection) {
    return const ContextPlan(AppProfileContextSource.selection);
  }
  if (!isMacOS) {
    return const ContextPlan(AppProfileContextSource.clipboard);
  }
  final ruleTeam = resolved.matchedRule?.teamId;
  final targetTeam = target?.teamId;
  if (ruleTeam == null || targetTeam == null) {
    return const ContextPlan(
      AppProfileContextSource.none,
      blockedBy: ContextBlockReason.bindingUnavailable,
    );
  }
  if (ruleTeam != targetTeam) {
    return const ContextPlan(
      AppProfileContextSource.none,
      blockedBy: ContextBlockReason.bindingMismatch,
    );
  }
  return const ContextPlan(AppProfileContextSource.clipboard);
}
