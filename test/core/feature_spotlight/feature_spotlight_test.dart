/// Tests for the pure functions behind the feature spotlight registry —
/// `.scratch/feature-spotlight/issues/01-spotlight-mechanism.md`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/feature_spotlight/feature_spotlight.dart';
import 'package:whispaste/core/onboarding/onboarding_revision.dart';

/// A registry entry never actually needs its localized text resolved in
/// these tests — only the id/platform shape drives the pure functions.
FeatureSpotlightEntry _entry(String id, {Set<OnboardingPlatform>? platforms}) =>
    FeatureSpotlightEntry(
      id: id,
      title: (l10n) => 'title $id',
      description: (l10n) => 'description $id',
      platforms: platforms,
    );

void main() {
  group('kFeatureSpotlightRegistry', () {
    test('every entry has a unique, non-empty id', () {
      final ids = kFeatureSpotlightRegistry.map((e) => e.id).toList();
      expect(ids, isNotEmpty);
      expect(ids.every((id) => id.isNotEmpty), isTrue);
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('snippet_picker is declared before side_panel — the older feature '
        'must come first so the newer one shows first (newest-first '
        'ordering, see the maintainer note on kFeatureSpotlightRegistry)', () {
      final ids = kFeatureSpotlightRegistry.map((e) => e.id).toList();
      expect(
        ids.indexOf('snippet_picker'),
        lessThan(ids.indexOf('side_panel')),
      );
    });

    test('side_panel applies to every platform — the Linux native host shipped '
        '(feat(side-panel): add Linux native side panel)', () {
      final entry = kFeatureSpotlightRegistry.firstWhere(
        (e) => e.id == 'side_panel',
      );
      expect(entry.platforms, isNull);
    });

    test('snippet_picker applies to every platform — already shipped on '
        'macOS, Windows and Linux', () {
      final entry = kFeatureSpotlightRegistry.firstWhere(
        (e) => e.id == 'snippet_picker',
      );
      expect(entry.platforms, isNull);
    });

    test('interactive_snippets is declared before smart_mode — it shipped '
        'first, so Smart Mode shows first (newest-first ordering)', () {
      final ids = kFeatureSpotlightRegistry.map((e) => e.id).toList();
      expect(
        ids.indexOf('interactive_snippets'),
        lessThan(ids.indexOf('smart_mode')),
      );
      expect(
        ids.indexOf('side_panel'),
        lessThan(ids.indexOf('interactive_snippets')),
      );
    });

    test('interactive_snippets applies to every platform', () {
      final entry = kFeatureSpotlightRegistry.firstWhere(
        (e) => e.id == 'interactive_snippets',
      );
      expect(entry.platforms, isNull);
    });

    test('smart_mode is scoped to macos+windows — the local engine is not '
        'bundled for Linux (smartModeLibraryPathFor throws there)', () {
      final entry = kFeatureSpotlightRegistry.firstWhere(
        (e) => e.id == 'smart_mode',
      );
      expect(entry.platforms, {
        OnboardingPlatform.macos,
        OnboardingPlatform.windows,
      });
    });
  });

  group('pendingFeatureSpotlights', () {
    test('an empty registry yields no pending entries', () {
      expect(
        pendingFeatureSpotlights(
          registry: const [],
          platform: OnboardingPlatform.macos,
          seenIds: const {},
        ),
        isEmpty,
      );
    });

    test('an already-seen entry is excluded', () {
      final registry = [_entry('a')];
      expect(
        pendingFeatureSpotlights(
          registry: registry,
          platform: OnboardingPlatform.macos,
          seenIds: {'a'},
        ),
        isEmpty,
      );
    });

    test('an entry scoped to another platform is excluded', () {
      final registry = [
        _entry('a', platforms: {OnboardingPlatform.windows}),
      ];
      expect(
        pendingFeatureSpotlights(
          registry: registry,
          platform: OnboardingPlatform.macos,
          seenIds: const {},
        ),
        isEmpty,
      );
      expect(
        pendingFeatureSpotlights(
          registry: registry,
          platform: OnboardingPlatform.windows,
          seenIds: const {},
        ),
        hasLength(1),
      );
    });

    test('an entry with no platform scope applies everywhere', () {
      final registry = [_entry('a')];
      for (final platform in OnboardingPlatform.values) {
        expect(
          pendingFeatureSpotlights(
            registry: registry,
            platform: platform,
            seenIds: const {},
          ),
          hasLength(1),
        );
      }
    });

    test(
      'multiple pending entries are bundled newest-first — declaration '
      'order is oldest-first, so the result is the reverse of the registry',
      () {
        final registry = [_entry('a'), _entry('b'), _entry('c')];
        final pending = pendingFeatureSpotlights(
          registry: registry,
          platform: OnboardingPlatform.macos,
          seenIds: const {},
        );
        expect(pending.map((e) => e.id).toList(), ['c', 'b', 'a']);
      },
    );

    test('a mix of seen and unseen entries only returns the unseen ones, '
        'still newest-first', () {
      final registry = [_entry('a'), _entry('b'), _entry('c')];
      final pending = pendingFeatureSpotlights(
        registry: registry,
        platform: OnboardingPlatform.macos,
        seenIds: {'b'},
      );
      expect(pending.map((e) => e.id).toList(), ['c', 'a']);
    });
  });

  group('FeatureSpotlightEntry.appliesTo', () {
    test('null platforms applies to every platform', () {
      final entry = _entry('a');
      for (final platform in OnboardingPlatform.values) {
        expect(entry.appliesTo(platform), isTrue);
      }
    });

    test('a non-null set restricts to its members', () {
      final entry = _entry('a', platforms: {OnboardingPlatform.linux});
      expect(entry.appliesTo(OnboardingPlatform.linux), isTrue);
      expect(entry.appliesTo(OnboardingPlatform.macos), isFalse);
      expect(entry.appliesTo(OnboardingPlatform.windows), isFalse);
    });
  });

  group('parseFeatureSpotlightSeenIds / serializeFeatureSpotlightSeenIds', () {
    test('parsing the empty string yields an empty set', () {
      expect(parseFeatureSpotlightSeenIds(''), isEmpty);
    });

    test('parsing trims whitespace and drops empty segments', () {
      expect(parseFeatureSpotlightSeenIds(' a, b ,,c '), {'a', 'b', 'c'});
    });

    test('serializing sorts ids for a stable, deterministic string', () {
      expect(serializeFeatureSpotlightSeenIds({'c', 'a', 'b'}), 'a,b,c');
    });

    test('round-trip preserves the id set', () {
      const ids = {'feature-x', 'feature-y'};
      final serialized = serializeFeatureSpotlightSeenIds(ids);
      expect(parseFeatureSpotlightSeenIds(serialized), ids);
    });

    test('merging the same shown ids twice (double-dismiss) is idempotent — '
        'produces the same serialized string both times', () {
      final current = parseFeatureSpotlightSeenIds('a');
      final shown = {'b', 'c'};
      final firstMerge = serializeFeatureSpotlightSeenIds({
        ...current,
        ...shown,
      });
      final secondMerge = serializeFeatureSpotlightSeenIds({
        ...parseFeatureSpotlightSeenIds(firstMerge),
        ...shown,
      });
      expect(secondMerge, firstMerge);
    });
  });
}
