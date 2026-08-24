/// The feature spotlight registry — `.scratch/feature-spotlight/issues/
/// 01-spotlight-mechanism.md`.
///
/// Mirrors `onboarding_revision.dart`'s shape closely: a registry of entries
/// a future feature appends to, a pure function that turns "registry +
/// platform + what a user has seen" into the set of entries still due, and
/// an overridable provider seam so nothing in the built app can be pushed
/// into a spotlight showing except through that seam.
///
/// Every consumer takes the registry as a parameter or reads it via
/// [featureSpotlightRegistryProvider], never the constant directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/generated/app_localizations.dart';
import '../onboarding/onboarding_revision.dart' show OnboardingPlatform;

/// One feature to spotlight for users who already completed onboarding.
/// [title]/[description] are closures over [L10n] rather than plain strings
/// so every entry is forced through the generated localizations (all
/// supported UI languages) instead of a single hardcoded string. [platforms]
/// is the entry's scope — `null` (the default) means "applies on every
/// platform"; a non-null set restricts it.
class FeatureSpotlightEntry {
  const FeatureSpotlightEntry({
    required this.id,
    required this.title,
    required this.description,
    this.platforms,
    this.image,
  });

  /// Stable, opaque identifier — persisted verbatim into
  /// `OnboardingSettings.seenFeatureSpotlightIds` once shown. Never reuse an
  /// id for a different feature; never rename an existing entry's id (it
  /// would make already-seen users see it again).
  final String id;

  final String Function(L10n l10n) title;
  final String Function(L10n l10n) description;

  /// `null` = applies to all platforms.
  final Set<OnboardingPlatform>? platforms;

  /// Optional asset path to a static mini-screenshot shown above the
  /// entry's text (`_FeatureSpotlightDialog` in `feature_spotlight_notice
  /// .dart`). `null` = text-only, same as before this field existed — not
  /// every entry needs a picture. See `assets/feature_spotlight/README.md`
  /// for the capture/export convention (340×212 logical px, 2× export,
  /// static only — no GIF/loop, unlike the onboarding beat clips).
  final String? image;

  bool appliesTo(OnboardingPlatform platform) =>
      platforms == null || platforms!.contains(platform);
}

typedef FeatureSpotlightRegistry = List<FeatureSpotlightEntry>;

/// Maintainer note: append new entries at the END of this list. There is no
/// version field (unlike the onboarding revision registry) — declaration
/// order stands in for chronological order, oldest first, and
/// [pendingFeatureSpotlights] reverses it to show newest-first. Inserting an
/// entry anywhere but the end changes what "newest" means for every entry
/// after it.
final FeatureSpotlightRegistry kFeatureSpotlightRegistry = [
  // Older feature (already shipped cross-platform, macOS + Windows +
  // Linux — `feat(snippet-picker): add Windows native shell`, `feat(linux):
  // add uinput Auto-Paste and native Snippet-Picker shell`), declared FIRST
  // so it shows SECOND (see the ordering note above). Not a new-feature
  // announcement but a discoverability push, per `.scratch/
  // feature-spotlight/issues/03-second-entry-snippet.md` — a chunk of the
  // target audience (older, less tech-savvy existing users, `docs/
  // zielgruppe.md`) never found the Snippet sidebar entry on their own.
  FeatureSpotlightEntry(
    id: 'snippet_picker',
    title: (l10n) => l10n.featureSpotlightSnippetPickerTitle,
    description: (l10n) => l10n.featureSpotlightSnippetPickerDescription,
    image: 'assets/feature_spotlight/snippet_picker.webp',
  ),
  // `.scratch/feature-spotlight/issues/02-first-entry-side-panel.md`. No
  // Linux native host yet (windows/macos have SidePanelHost, linux does
  // not) -- platforms stays macos+windows, not null.
  FeatureSpotlightEntry(
    id: 'side_panel',
    title: (l10n) => l10n.featureSpotlightSidePanelTitle,
    description: (l10n) => l10n.featureSpotlightSidePanelDescription,
    platforms: const {OnboardingPlatform.macos, OnboardingPlatform.windows},
    image: 'assets/feature_spotlight/side_panel.webp',
  ),
];

/// Overridable seam for the registry. Every call site reads the registry
/// through this provider (or takes one as a parameter), never
/// [kFeatureSpotlightRegistry] directly — with an empty registry wired in as
/// a global constant, nothing in the built app could ever be pushed into a
/// spotlight showing to test it.
final featureSpotlightRegistryProvider = Provider<FeatureSpotlightRegistry>(
  (ref) => kFeatureSpotlightRegistry,
);

/// The entries in [registry] not yet in [seenIds] that apply to [platform],
/// newest first (see the maintainer note on [kFeatureSpotlightRegistry] for
/// why "newest" is the reverse of declaration order).
///
/// Pure, and deliberately not a provider: the caller already holds the
/// registry, the platform and the seen-ids it needs.
List<FeatureSpotlightEntry> pendingFeatureSpotlights({
  required FeatureSpotlightRegistry registry,
  required OnboardingPlatform platform,
  required Set<String> seenIds,
}) {
  final pending = registry
      .where(
        (entry) => entry.appliesTo(platform) && !seenIds.contains(entry.id),
      )
      .toList();
  return pending.reversed.toList();
}

/// Parses `OnboardingSettings.seenFeatureSpotlightIds`'s comma-separated
/// storage format into a set of ids. Mirrors
/// `BehaviorSettings.autoPasteBlocklist`'s parsing convention (trim,
/// drop-empty) — the same pattern used at
/// `lib/services/paste/desktop_paster.dart`'s `_checkBlocklist`.
Set<String> parseFeatureSpotlightSeenIds(String raw) =>
    raw.split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toSet();

/// Serializes a set of seen ids back into the comma-separated storage
/// format. Sorted so the output is deterministic — repeated dismiss calls
/// that merge the same ids produce byte-identical strings, making the write
/// path naturally idempotent.
String serializeFeatureSpotlightSeenIds(Set<String> ids) {
  final sorted = ids.toList()..sort();
  return sorted.join(',');
}
