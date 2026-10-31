import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/search/settings_search_keywords.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';

List<String> _rowIdsFor(String query, String locale) => matchSettingsEntries(
  kSettingsSearchTable,
  query,
  locale,
).map((e) => e.rowId).toList();

void main() {
  group('English overlay colour rows find both spellings', () {
    for (final query in const ['color', 'colour']) {
      test('"$query" finds both overlay colour rows', () {
        final ids = _rowIdsFor(query, 'en');
        expect(ids, contains('appearance-overlay-background'));
        expect(ids, contains('appearance-overlay-wave'));
      });
    }
  });

  group('synonyms in the UI language', () {
    const gain = {
      'es': 'ganancia',
      'pt': 'ganho',
      'ru': 'усиление',
      'he': 'הגברה',
    };
    const automation = {
      'es': 'automatización',
      'pt': 'automação',
      'ru': 'автоматизация',
      'he': 'אוטומציה',
    };

    for (final locale in gain.keys) {
      test('$locale finds the microphone row by its own word for gain', () {
        expect(
          _rowIdsFor(gain[locale]!, locale),
          contains('recording-microphone'),
        );
      });

      test('$locale finds the automation API row', () {
        expect(
          _rowIdsFor(automation[locale]!, locale),
          contains('advanced-automation-api'),
        );
      });

      test('$locale words do not match while the UI is English', () {
        expect(
          _rowIdsFor(gain[locale]!, 'en'),
          isNot(contains('recording-microphone')),
        );
      });
    }

    test('matching ignores accents in the query', () {
      expect(
        _rowIdsFor('automatizacion', 'es'),
        contains('advanced-automation-api'),
      );
    });

    test('DE and EN rely on the curated table synonyms only', () {
      expect(localizedSettingsKeywords('recording-microphone', 'en'), isEmpty);
      expect(localizedSettingsKeywords('recording-microphone', 'de'), isEmpty);
      expect(
        localizedSettingsKeywords('recording-microphone', 'pt-BR'),
        isNotEmpty,
      );
    });

    test('rows without a synonym list yield none', () {
      expect(localizedSettingsKeywords('appearance-mode', 'es'), isEmpty);
    });

    const blocklist = {
      'es': 'lista de bloqueo',
      'pt': 'lista de bloqueio',
      'ru': 'список блокировки',
      'he': 'רשימת חסימה',
    };
    for (final locale in blocklist.keys) {
      test('$locale blocklist word finds the auto-paste blocklist row, '
          'not reset to defaults', () {
        final rowIds = _rowIdsFor(blocklist[locale]!, locale);
        expect(rowIds, contains('text-auto-paste-blocklist'));
        expect(rowIds, isNot(contains('advanced-reset-defaults')));
      });
    }
  });

  group('the nav label finds the history row', () {
    for (final locale in ['de', 'en', 'es', 'pt', 'ru', 'he']) {
      test('$locale: searching the nav label finds the history row', () async {
        final l10n = await L10n.delegate.load(Locale(locale));
        expect(
          _rowIdsFor(l10n.navHistory, locale),
          contains(kLegacySettingsDeepLinkRowIds['history']),
          reason: 'navHistory "${l10n.navHistory}" must be a search synonym',
        );
      });
    }
  });

  test('shared section rows are rows of the settings table', () {
    for (final rowId in kSharedSectionRowIds.values.expand((ids) => ids)) {
      expect(
        kSettingsSearchTable.where((r) => r.rowId == rowId),
        hasLength(1),
        reason: '$rowId must be a row of the settings table',
      );
    }
  });

  test('every settingsSearchKeywords* ARB key feeds the search', () {
    final arb =
        (jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync()) as Map)
            .keys
            .cast<String>()
            .where((k) => k.startsWith('settingsSearchKeywords'))
            .toSet();
    final source = File(
      'lib/features/settings/search/settings_search_keywords.dart',
    ).readAsStringSync();
    final wired = RegExp(
      r'l\.(settingsSearchKeywords\w+)',
    ).allMatches(source).map((m) => m.group(1)!).toSet();
    expect(wired, arb);
    expect(
      kLocalizedSettingsKeywords.length + kLocalizedRowKeywords.length,
      arb.length,
    );
    for (final rowId in [
      ...kLocalizedSettingsKeywords.keys,
      ...kLocalizedRowKeywords.keys,
    ]) {
      expect(
        kSettingsSearchTable.where((r) => r.rowId == rowId),
        hasLength(1),
        reason: '$rowId must be a row of the settings table',
      );
    }
  });

  group('overlay background and wave rows in the UI language', () {
    test('ru finds the wave row by "волна"', () {
      expect(_rowIdsFor('волна', 'ru'), contains('appearance-overlay-wave'));
    });

    test('ru finds the background row by "фон"', () {
      expect(
        _rowIdsFor('фон', 'ru'),
        contains('appearance-overlay-background'),
      );
    });
  });
}
