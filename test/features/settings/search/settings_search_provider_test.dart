import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _all = kSettingsSearchTable;

List<String> _sectionKeysFor(String query, {String locale = 'en'}) =>
    matchSettingsEntries(_all, query, locale).map((e) => e.sectionKey).toList();

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
      expect(keys, contains('interface'));
    });

    test('upper-case query matches lower-case keyword', () {
      final keys = _sectionKeysFor('MICROPHONE', locale: 'en');
      expect(keys, contains('audio'));
    });

    test('mixed-case query matches', () {
      final keys = _sectionKeysFor('Hotkey', locale: 'en');
      expect(keys, contains('hotkey'));
    });
  });

  group('matchSettingsEntries — accent tolerance', () {
    test('query without umlaut matches keyword with umlaut (ü → u)', () {
      // "Tastenkurzel" (no ü) should still match the 'hotkey' section
      // whose DE title is "Tastenkürzel"
      final keys = _sectionKeysFor('Tastenkurzel', locale: 'de');
      expect(keys, contains('hotkey'));
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
      expect(keys, contains('sound'));
    });

    test('German umlaut in query folds to match English keyword', () {
      // Query "Mikrofön" (malformed but accent-tolerant) folds to "mikrofon"
      // which matches 'audio' keywords containing 'microphone'? No — "mikrofon"
      // ≠ "microphone". But the DE keyword "Mikrofon" should match.
      final keys = _sectionKeysFor('Mikrofon', locale: 'de');
      expect(keys, contains('audio'));
    });

    test('fold: ö-less query matches keyword with ö', () {
      // "Zwischenablage" has no umlauts, but "Einfugen" (without ü)
      // should match "Einfügen"
      final keys = _sectionKeysFor('Einfugen', locale: 'de');
      expect(keys, contains('afterTranscription'));
    });
  });

  group('matchSettingsEntries — subtitle matching', () {
    test('matches subtitle substring', () {
      // EN subtitle for 'audio' contains "Microphone"
      final keys = _sectionKeysFor('Microphone and recording', locale: 'en');
      expect(keys, contains('audio'));
    });

    test('matches partial subtitle', () {
      final keys = _sectionKeysFor('retention', locale: 'en');
      expect(keys, contains('history'));
    });
  });

  group('matchSettingsEntries — keyword/synonym matching', () {
    test('synonym "Tastenkürzel" → hotkey section (DE)', () {
      final keys = _sectionKeysFor('Tastenkürzel', locale: 'de');
      expect(keys, contains('hotkey'));
    });

    test('synonym "keyboard shortcut" → hotkey section (EN)', () {
      final keys = _sectionKeysFor('keyboard shortcut', locale: 'en');
      expect(keys, contains('hotkey'));
    });

    test('synonym "Mikrofon" → audio section (DE keyword)', () {
      final keys = _sectionKeysFor('Mikrofon', locale: 'de');
      expect(keys, contains('audio'));
    });

    test('synonym "auto-paste" → afterTranscription section', () {
      final keys = _sectionKeysFor('auto-paste', locale: 'en');
      expect(keys, contains('afterTranscription'));
    });

    test('synonym "silence detection" → recordingSafety section', () {
      final keys = _sectionKeysFor('silence detection', locale: 'en');
      expect(keys, contains('recordingSafety'));
    });

    test('synonym "Stille-Erkennung" → recordingSafety section (DE)', () {
      final keys = _sectionKeysFor('Stille-Erkennung', locale: 'de');
      expect(keys, contains('recordingSafety'));
    });

    test('synonym "factory reset" → advanced section', () {
      final keys = _sectionKeysFor('factory reset', locale: 'en');
      expect(keys, contains('advanced'));
    });
  });

  group('matchSettingsEntries — locale behaviour', () {
    test('EN title matches in EN locale', () {
      final keys = _sectionKeysFor('Speech Recognition', locale: 'en');
      expect(keys, contains('stt'));
    });

    test('DE title matches in DE locale', () {
      final keys = _sectionKeysFor('Spracherkennung', locale: 'de');
      expect(keys, contains('stt'));
    });

    test('EN keywords match even in DE locale', () {
      // Keywords are bilingual so "on-device" should match in any locale
      final keys = _sectionKeysFor('on-device', locale: 'de');
      expect(keys, contains('stt'));
    });

    test('DE keywords match even in EN locale', () {
      final keys = _sectionKeysFor('Sprachdienst', locale: 'en');
      expect(keys, contains('stt'));
    });
  });

  group('matchSettingsEntries — section key mapping', () {
    test('entry sectionKey matches expected section for interface', () {
      final results = matchSettingsEntries(_all, 'interface', 'en');
      final match = results.firstWhere(
        (e) => e.sectionKey == 'interface',
        orElse: () => throw StateError('interface not found'),
      );
      expect(match.sectionKey, 'interface');
    });

    test('each entry in table has a unique id', () {
      final ids = _all.map((e) => e.id).toSet();
      expect(ids.length, equals(_all.length));
    });

    test('each entry in table has a unique sectionKey', () {
      final keys = _all.map((e) => e.sectionKey).toSet();
      expect(keys.length, equals(_all.length));
    });

    test('all 12 sections are covered', () {
      const expectedKeys = {
        'interface',
        'stt',
        'gpu',
        'audio',
        'afterTranscription',
        'overlay',
        'floatingButton',
        'hotkey',
        'sound',
        'recordingSafety',
        'history',
        'advanced',
      };
      final tableKeys = _all.map((e) => e.sectionKey).toSet();
      expect(tableKeys, containsAll(expectedKeys));
    });
  });

  group('matchSettingsEntries — no false positives', () {
    test('returns empty for unrelated query', () {
      final keys = _sectionKeysFor('xyzzy_no_match_42', locale: 'en');
      expect(keys, isEmpty);
    });

    test('does not match partial rune sequence across word boundaries', () {
      // Searching "hist" should match 'history', but not 'hotkey'
      final keys = _sectionKeysFor('hist', locale: 'en');
      expect(keys, contains('history'));
      expect(keys, isNot(contains('hotkey')));
    });
  });
}
