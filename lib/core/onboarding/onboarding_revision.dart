/// The onboarding revision registry — `.scratch/onboarding-revisions/issues/01`.
///
/// WhisPaste stamps every user with the onboarding *content* revision they
/// last saw (`OnboardingSettings.onboardingContentVersion`, distinct from
/// `onboardingFlowVersion`, which only tracks the step-sequence *shape* a
/// saved resume position indexes into — see that field's doc comment). This
/// file supplies the other half: the registry of revision *reasons* a
/// future feature appends single entries to, and the two pure functions
/// that turn "registry + platform + what a user has seen" into a yes/no
/// trigger.
///
/// The registry starts empty (`kOnboardingRevisionRegistry`) — this ticket
/// only builds the mechanism, not a first real revision (see the parent
/// PRD, "Offene Entscheidungen" #4, for where the first entry will come
/// from). Every consumer takes the registry as a parameter or reads it via
/// [onboardingRevisionRegistryProvider], never the constant directly — with
/// an empty registry wired in as a global constant, nothing in the built
/// app could ever be pushed into a revision run to test it.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';

/// The desktop platforms WhisPaste ships on. Mirrors the app's own
/// platform-inclusivity stance (`CONTEXT.md` §1) rather than reusing
/// Flutter's `TargetPlatform`, which also carries mobile values this app
/// never runs on.
enum OnboardingPlatform { macos, windows, linux }

/// The platform this process is actually running on. A thin, deliberately
/// non-injected wrapper around `dart:io`'s `Platform` — same shape as the
/// private `_platformTag()` helper in `paste_capability_notifier.dart`. Only
/// the *edges* (settings load, the surface-active provider) call this; the
/// pure functions below take an [OnboardingPlatform] parameter instead, so
/// tests never depend on the host they run on.
OnboardingPlatform currentOnboardingPlatform() {
  if (Platform.isMacOS) return OnboardingPlatform.macos;
  if (Platform.isWindows) return OnboardingPlatform.windows;
  return OnboardingPlatform.linux;
}

/// One reason to run the onboarding flow again for users who already
/// finished it. [reason] is a closure over [L10n] rather than a plain
/// string so every entry is forced to go through the generated
/// localizations (all supported UI languages) instead of a single
/// hardcoded string. [platforms] is the entry's scope — `null` (the
/// default) means "applies on every platform"; a non-null set restricts it.
class OnboardingRevisionEntry {
  const OnboardingRevisionEntry({
    required this.version,
    required this.reason,
    this.platforms,
  });

  /// Registry counting starts at `1` — `0` is reserved for
  /// `OnboardingSettings.onboardingContentVersion`'s "never stamped" state.
  final int version;

  final String Function(L10n l10n) reason;

  /// `null` = applies to all platforms.
  final Set<OnboardingPlatform>? platforms;

  bool appliesTo(OnboardingPlatform platform) =>
      platforms == null || platforms!.contains(platform);
}

typedef OnboardingRevisionRegistry = List<OnboardingRevisionEntry>;

/// Starts empty on purpose — see the file doc comment.
const OnboardingRevisionRegistry kOnboardingRevisionRegistry = [];

/// Overridable seam for the registry. Every call site — the settings load's
/// grandfathering migration, and the surface-active predicate that will
/// consume [onboardingRevisionDue] — reads the registry through this
/// provider (or takes one as a parameter), never [kOnboardingRevisionRegistry]
/// directly.
final onboardingRevisionRegistryProvider = Provider<OnboardingRevisionRegistry>(
  (ref) => kOnboardingRevisionRegistry,
);

/// The highest revision version that applies to [platform], across every
/// entry in [registry]. An empty registry (or one with no entry scoped to
/// this platform) yields `0` — the same value as "never stamped", so an
/// empty registry can never make [onboardingRevisionDue] true.
int targetOnboardingContentVersion(
  OnboardingRevisionRegistry registry,
  OnboardingPlatform platform,
) {
  var target = 0;
  for (final entry in registry) {
    if (entry.appliesTo(platform) && entry.version > target) {
      target = entry.version;
    }
  }
  return target;
}

/// The reasons a user on [seenContentVersion] has not been shown yet —
/// every registry entry that applies to [platform] and is newer than what
/// this user was last stamped with, localized through [l10n].
///
/// Newest first, on purpose: a user who skipped several versions gets the
/// most recent change first, so the one line the notice strip can afford
/// (`welcome_step.dart`) always carries the freshest reason rather than the
/// oldest one. Duplicates are collapsed — two entries may well name the same
/// change once a revision is re-issued for a second platform.
///
/// Pure, and deliberately not a provider: the caller already holds the
/// registry, the platform and the settings it needs, and a provider would
/// have to reach for [L10n] (a widget-tree value) to build its result.
List<String> pendingOnboardingRevisionReasons({
  required OnboardingRevisionRegistry registry,
  required OnboardingPlatform platform,
  required int seenContentVersion,
  required L10n l10n,
}) {
  final pending =
      registry
          .where(
            (entry) =>
                entry.appliesTo(platform) && entry.version > seenContentVersion,
          )
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));

  final reasons = <String>[];
  for (final entry in pending) {
    final reason = entry.reason(l10n).trim();
    if (reason.isEmpty || reasons.contains(reason)) continue;
    reasons.add(reason);
  }
  return reasons;
}

/// Whether a revision run should trigger: onboarding must already be
/// complete (a first run is never a "revision" — it is the first run), and
/// the version this user was last stamped with must be strictly below the
/// current target. Equal (already caught up) or above (a downgrade put an
/// older build with a lower registry back on the machine) never trigger.
bool onboardingRevisionDue({
  required bool onboardingCompleted,
  required int seenContentVersion,
  required int targetContentVersion,
}) {
  return onboardingCompleted && seenContentVersion < targetContentVersion;
}
