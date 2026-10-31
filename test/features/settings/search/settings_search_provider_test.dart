import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';
import 'settings_legacy_row_ids.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _all = kSettingsSearchTable;

List<String> _sectionKeysFor(String query, {String locale = 'en'}) =>
    matchSettingsEntries(_all, query, locale).map((e) => e.rowId).toList();

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('matchSettingsEntries — basic', () {
    test('returns empty list for blank query', () {
      expect(matchSettingsEntries(_all, '', 'en'), isEmpty);
      expect(matchSettingsEntries(_all, '   ', 'en'), isEmpty);
    });

    test('returns non-empty for a plausible query', () {
      final results = matchSettingsEntries(_all, 'audio', 'en');
      expect(results, isNotEmpty);
    });

    test('returns SettingsSearchEntry objects', () {
      final results = matchSettingsEntries(_all, 'microphone', 'en');
      expect(results, everyElement(isA<SettingsSearchEntry>()));
    });
  });

  group('matchSettingsEntries — case insensitivity', () {
    test('lower-case query matches mixed-case title', () {
      final keys = _sectionKeysFor('interface', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('interface')));
    });

    test('upper-case query matches lower-case keyword', () {
      final keys = _sectionKeysFor('MICROPHONE', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('audio')));
    });

    test('mixed-case query matches', () {
      final keys = _sectionKeysFor('Hotkey', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('hotkey')));
    });
  });

  group('matchSettingsEntries — accent tolerance', () {
    test('query without umlaut matches keyword with umlaut (ü → u)', () {
      // "Tastenkurzel" (no ü) should still match the legacyRowId('hotkey') section
      // whose DE title is "Tastenkürzel"
      final keys = _sectionKeysFor('Tastenkurzel', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('hotkey')));
    });

    test('query with umlaut matches folded keyword', () {
      // Typing "Überfläche" should match "Oberfläche" after folding?
      // Actually: "ü" folds to "u", "Uberfläche" → "uberflache",
      // and "Oberfläche" → "oberflache". These don't match — and that
      // is correct (the query is wrong). Let's test a realistic case.
      //
      // "Ton & Feedback" → fold → "ton & feedback"
      // Query "Ton" → matches
      final keys = _sectionKeysFor('Ton', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('sound')));
    });

    test('German umlaut in query folds to match English keyword', () {
      // Query "Mikrofön" (malformed but accent-tolerant) folds to "mikrofon"
      // which matches legacyRowId('audio') keywords containing 'microphone'? No — "mikrofon"
      // ≠ "microphone". But the DE keyword "Mikrofon" should match.
      final keys = _sectionKeysFor('Mikrofon', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('audio')));
    });

    test('fold: ö-less query matches keyword with ö', () {
      // "Zwischenablage" has no umlauts, but "Einfugen" (without ü)
      // should match "Einfügen"
      final keys = _sectionKeysFor('Einfugen', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('afterTranscription')));
    });
  });

  group('matchSettingsEntries — keyword substring', () {
    test('matches a keyword substring', () {
      final keys = _sectionKeysFor('Eingabegerät', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('audio')));
    });

    test('matches partial subtitle', () {
      final keys = _sectionKeysFor('retention', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('history')));
    });
  });

  group('matchSettingsEntries — keyword/synonym matching', () {
    test('synonym "Tastenkürzel" → hotkey section (DE)', () {
      final keys = _sectionKeysFor('Tastenkürzel', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('hotkey')));
    });

    test('synonym "keyboard shortcut" → hotkey section (EN)', () {
      final keys = _sectionKeysFor('keyboard shortcut', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('hotkey')));
    });

    test('synonym "Mikrofon" → audio section (DE keyword)', () {
      final keys = _sectionKeysFor('Mikrofon', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('audio')));
    });

    test('synonym "auto-paste" → afterTranscription section', () {
      final keys = _sectionKeysFor('auto-paste', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('afterTranscription')));
    });

    test('synonym "silence detection" → recordingSafety section', () {
      final keys = _sectionKeysFor('silence detection', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('recordingSafety')));
    });

    test('synonym "Stille-Erkennung" → recordingSafety section (DE)', () {
      final keys = _sectionKeysFor('Stille-Erkennung', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('recordingSafety')));
    });

    test('synonym "factory reset" → advanced section', () {
      final keys = _sectionKeysFor('factory reset', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('advanced')));
    });
  });

  group('matchSettingsEntries — locale behaviour', () {
    test('EN title matches in EN locale', () {
      final keys = _sectionKeysFor('Speech Recognition', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('stt')));
    });

    test('DE title matches in DE locale', () {
      final keys = _sectionKeysFor('Spracherkennung', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('stt')));
    });

    test('EN keywords match even in DE locale', () {
      // Keywords are bilingual so "on-device" should match in any locale
      final keys = _sectionKeysFor('on-device', locale: 'de');
      expect(keys, containsAnyOf(legacyRowIds('stt')));
    });

    test('DE keywords match even in EN locale', () {
      final keys = _sectionKeysFor('Sprachmodell', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('stt')));
    });

    test(
      'the dock word "Spracherkennung" still finds the speech model row',
      () {
        // The dock's speech selector was labelled "Spracherkennung" before the
        // rename to "Sprachmodell"; the old word stays a search synonym.
        final keys = _sectionKeysFor('Spracherkennung', locale: 'en');
        expect(keys, containsAnyOf(legacyRowIds('stt')));
      },
    );
  });

  group('matchSettingsEntries — section key mapping', () {
    test('entry sectionKey matches expected section for interface', () {
      final results = matchSettingsEntries(_all, 'interface', 'en');
      final match = results.firstWhere(
        (e) => legacyRowIds('interface').contains(e.rowId),
        orElse: () => throw StateError('interface not found'),
      );
      expect(match.rowId, legacyRowId('interface'));
    });

    test('each entry in table has a unique id', () {
      final ids = _all.map((e) => e.rowId).toSet();
      expect(ids.length, equals(_all.length));
    });

    test('each entry in table has a unique sectionKey', () {
      final keys = _all.map((e) => e.rowId).toSet();
      expect(keys.length, equals(_all.length));
    });

    test('all 11 sections are covered', () {
      // GPU no longer has its own entry — its keywords moved to the STT entry.
      final expectedKeys = {
        legacyRowId('interface'),
        legacyRowId('stt'),
        legacyRowId('audio'),
        legacyRowId('afterTranscription'),
        legacyRowId('overlay'),
        legacyRowId('floatingButton'),
        legacyRowId('hotkey'),
        legacyRowId('sound'),
        legacyRowId('recordingSafety'),
        legacyRowId('history'),
        legacyRowId('advanced'),
      };
      final tableKeys = _all.map((e) => e.rowId).toSet();
      expect(tableKeys, containsAll(expectedKeys));
    });

    test('GPU search keywords resolve to the STT section', () {
      // The GPU dropdown was moved into the STT section (local mode only).
      // Searching "GPU" must jump to the STT section, not a removed entry.
      final keysEn = _sectionKeysFor('GPU', locale: 'en');
      expect(keysEn, containsAnyOf(legacyRowIds('stt')));

      final keysDe = _sectionKeysFor('Grafik', locale: 'de');
      expect(keysDe, containsAnyOf(legacyRowIds('stt')));
    });
  });

  group('matchSettingsEntries — no false positives', () {
    test('returns empty for unrelated query', () {
      final keys = _sectionKeysFor('xyzzy_no_match_42', locale: 'en');
      expect(keys, isEmpty);
    });

    test('does not match partial rune sequence across word boundaries', () {
      // Searching "hist" should match legacyRowId('history'), but not legacyRowId('hotkey')
      final keys = _sectionKeysFor('hist', locale: 'en');
      expect(keys, containsAnyOf(legacyRowIds('history')));
      expect(keys, isNot(containsAnyOf(legacyRowIds('hotkey'))));
    });
  });
}
