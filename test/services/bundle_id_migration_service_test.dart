import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/bundle_id_migration_service.dart';

// ---------------------------------------------------------------------------
// In-memory test double for KeyValueStore
// ---------------------------------------------------------------------------

class FakeKeyValueStore implements KeyValueStore {
  FakeKeyValueStore([Map<String, String>? initial])
    : _store = Map<String, String>.from(initial ?? {});

  final Map<String, String> _store;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.unmodifiable(_store);

  bool contains(String key) => _store.containsKey(key);
  String? operator [](String key) => _store[key];
  int get length => _store.length;
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

/// Builds a fresh set of four stores for each test.
({
  FakeKeyValueStore oldSecure,
  FakeKeyValueStore newSecure,
  FakeKeyValueStore oldPrefs,
  FakeKeyValueStore newPrefs,
})
makeStores({
  Map<String, String>? oldSecureData,
  Map<String, String>? newSecureData,
  Map<String, String>? oldPrefsData,
  Map<String, String>? newPrefsData,
}) => (
  oldSecure: FakeKeyValueStore(oldSecureData),
  newSecure: FakeKeyValueStore(newSecureData),
  oldPrefs: FakeKeyValueStore(oldPrefsData),
  newPrefs: FakeKeyValueStore(newPrefsData),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('runBundleIdMigration', () {
    // -----------------------------------------------------------------------
    // AC2/AC5: No-op when no old data present
    // -----------------------------------------------------------------------
    test('is a no-op when old stores are empty', () async {
      final s = makeStores();

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(result.ranMigration, isTrue);
      expect(result.copiedApiKeys, isEmpty);
      expect(result.copiedPreferences, isEmpty);
      // New secure store must stay untouched (no spurious writes).
      expect(s.newSecure.length, 0);
      // Marker must be set even on no-op (so it won't re-run on next start).
      expect(s.newPrefs[kBundleIdMigrationDoneKey], '1');
    });

    // -----------------------------------------------------------------------
    // AC2/AC5: Copies data when old present and new absent
    // -----------------------------------------------------------------------
    test('copies api keys when old present and new absent', () async {
      final s = makeStores(
        oldSecureData: {
          'wp_openai_api_key': 'sk-old-openai',
          'wp_deepgram_api_key': 'dg-old-deepgram',
        },
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(result.ranMigration, isTrue);
      expect(
        result.copiedApiKeys,
        containsAll(['wp_openai_api_key', 'wp_deepgram_api_key']),
      );
      expect(s.newSecure['wp_openai_api_key'], 'sk-old-openai');
      expect(s.newSecure['wp_deepgram_api_key'], 'dg-old-deepgram');
      expect(s.newPrefs[kBundleIdMigrationDoneKey], '1');
    });

    test('copies preferences when old present and new absent', () async {
      final s = makeStores(
        oldPrefsData: {
          'recent_searches': '["foo","bar"]',
          'review_prompt_last_shown': '1717766400000',
          'review_prompt_permanently_dismissed': 'true',
          'review_prompt_shown_count': '2',
          'feedback_last_submitted_ms': '1717000000000',
        },
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(result.ranMigration, isTrue);
      expect(
        result.copiedPreferences,
        containsAll([
          'recent_searches',
          'review_prompt_last_shown',
          'review_prompt_permanently_dismissed',
          'review_prompt_shown_count',
          'feedback_last_submitted_ms',
        ]),
      );
      expect(s.newPrefs['recent_searches'], '["foo","bar"]');
      expect(s.newPrefs['review_prompt_permanently_dismissed'], 'true');
      expect(s.newPrefs[kBundleIdMigrationDoneKey], '1');
    });

    test(
      'copies all three data classes: api keys, prefs, (history is no-op)',
      () async {
        final s = makeStores(
          oldSecureData: {'wp_openai_api_key': 'sk-test'},
          oldPrefsData: {'recent_searches': '["query1"]'},
        );

        final result = await runBundleIdMigration(
          oldSecureStore: s.oldSecure,
          newSecureStore: s.newSecure,
          oldPrefs: s.oldPrefs,
          newPrefs: s.newPrefs,
        );

        // API keys copied
        expect(result.copiedApiKeys, contains('wp_openai_api_key'));
        // Preferences copied
        expect(result.copiedPreferences, contains('recent_searches'));
        // History is intentionally absent from result (bundle-ID-independent path)
        expect(result.ranMigration, isTrue);
      },
    );

    // -----------------------------------------------------------------------
    // AC2: does NOT overwrite existing new data
    // -----------------------------------------------------------------------
    test('does not overwrite existing api key in new store', () async {
      final s = makeStores(
        oldSecureData: {'wp_openai_api_key': 'sk-old'},
        newSecureData: {'wp_openai_api_key': 'sk-new'},
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      // New value must be preserved.
      expect(s.newSecure['wp_openai_api_key'], 'sk-new');
      // Key must NOT appear in copied list.
      expect(result.copiedApiKeys, isNot(contains('wp_openai_api_key')));
    });

    test('does not overwrite existing preference in new store', () async {
      final s = makeStores(
        oldPrefsData: {'recent_searches': '["old"]'},
        newPrefsData: {'recent_searches': '["new"]'},
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(s.newPrefs['recent_searches'], '["new"]');
      expect(result.copiedPreferences, isNot(contains('recent_searches')));
    });

    test(
      'does not overwrite when both old and new stores have a value',
      () async {
        // All new-store values must survive unchanged even if old store also has values.
        final s = makeStores(
          oldSecureData: {
            'wp_openai_api_key': 'sk-old-openai',
            'wp_deepgram_api_key': 'dg-old-deepgram',
          },
          newSecureData: {
            'wp_openai_api_key': 'sk-new-openai',
            'wp_deepgram_api_key': 'dg-new-deepgram',
          },
          oldPrefsData: {'recent_searches': '["old"]'},
          newPrefsData: {'recent_searches': '["new"]'},
        );

        await runBundleIdMigration(
          oldSecureStore: s.oldSecure,
          newSecureStore: s.newSecure,
          oldPrefs: s.oldPrefs,
          newPrefs: s.newPrefs,
        );

        expect(s.newSecure['wp_openai_api_key'], 'sk-new-openai');
        expect(s.newSecure['wp_deepgram_api_key'], 'dg-new-deepgram');
        expect(s.newPrefs['recent_searches'], '["new"]');
      },
    );

    // -----------------------------------------------------------------------
    // AC2/AC3: runs exactly once — marker guards re-entry
    // -----------------------------------------------------------------------
    test('runs exactly once: second call is a no-op', () async {
      final s = makeStores(
        oldSecureData: {'wp_openai_api_key': 'sk-old'},
        oldPrefsData: {'recent_searches': '["x"]'},
      );

      // First run — copies data.
      final first = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );
      expect(first.ranMigration, isTrue);

      // Simulate old store being cleared after migration.
      final emptyOldSecure = FakeKeyValueStore();
      final emptyOldPrefs = FakeKeyValueStore();

      // Second run — must be a no-op because the marker is already set.
      final second = await runBundleIdMigration(
        oldSecureStore: emptyOldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: emptyOldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(second.ranMigration, isFalse);
      // Values from first run must still be present (not wiped).
      expect(s.newSecure['wp_openai_api_key'], 'sk-old');
      expect(s.newPrefs['recent_searches'], '["x"]');
    });

    // -----------------------------------------------------------------------
    // AC3: idempotent — marker written even when old data absent
    // -----------------------------------------------------------------------
    test('sets migration marker even when nothing to copy', () async {
      final s = makeStores(); // empty old stores

      await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(s.newPrefs[kBundleIdMigrationDoneKey], '1');
    });

    // -----------------------------------------------------------------------
    // AC3: idempotent — marker present from a previous (external) run
    // -----------------------------------------------------------------------
    test('is a no-op when marker already set from a previous run', () async {
      final s = makeStores(
        oldSecureData: {'wp_openai_api_key': 'sk-should-not-be-copied'},
        newPrefsData: {kBundleIdMigrationDoneKey: '1'},
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(result.ranMigration, isFalse);
      expect(result.copiedApiKeys, isEmpty);
      // New store must not have received the old key.
      expect(s.newSecure.contains('wp_openai_api_key'), isFalse);
    });

    // -----------------------------------------------------------------------
    // Edge: empty-string values in old store treated as absent
    // -----------------------------------------------------------------------
    test('treats empty-string old values as absent (no copy)', () async {
      final s = makeStores(
        oldSecureData: {'wp_openai_api_key': ''},
        oldPrefsData: {'recent_searches': ''},
      );

      final result = await runBundleIdMigration(
        oldSecureStore: s.oldSecure,
        newSecureStore: s.newSecure,
        oldPrefs: s.oldPrefs,
        newPrefs: s.newPrefs,
      );

      expect(result.copiedApiKeys, isEmpty);
      expect(result.copiedPreferences, isEmpty);
      expect(s.newSecure.contains('wp_openai_api_key'), isFalse);
    });
  });
}
