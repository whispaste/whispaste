/// Coverage guard for the settings search registry (issue #150 follow-up).
///
/// `kSettingsSearchTable` is a hand-maintained per-section keyword list, not
/// a full-text index over the actual row labels — see `settings_search_entry
/// .dart`'s file comment. That structure previously let a real, user-visible
/// row (e.g. "Panel Position") go completely unfindable via search, because
/// nobody had added a matching keyword after the row was introduced.
///
/// Rather than rewrite the whole search model to be text-derived (a much
/// larger, riskier change), this test closes the gap the cheap way: for a
/// curated set of primary settings-row labels (one per visible row, taken
/// verbatim from `app_en.arb`), it asserts that searching for at least one
/// significant word from that label surfaces the row's own section. Run this
/// after adding any new settings row and add the row's arb key to
/// [kSettingsCoverageLabelKeys] below — a failure here means the row would be
/// invisible to the in-app settings search.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/settings/search/settings_search_provider.dart';

import 'settings_legacy_row_ids.dart';
import 'settings_row_label_keys.dart';

/// Maps an `app_en.arb` key (a primary row/section label, not a subtitle,
/// hint, placeholder or enum-value string) to the `sectionKey` it must be
/// findable under in `kSettingsSearchTable`.

const Set<String> _stopwords = {
  'the',
  'and',
  'for',
  'to',
  'of',
  'a',
  'in',
  'on',
  'at',
  'is',
  'are',
  'your',
  'this',
  'that',
  'you',
  'can',
  'will',
  'now',
  'had',
  'after',
};

/// Splits a row label into words worth searching for on their own (drops
/// punctuation, short filler words and stopwords) — mirrors how a real user
/// searches: one or two meaningful words, not the whole label verbatim.
List<String> _significantWords(String label) {
  return label
      .split(RegExp(r'[^A-Za-z]+'))
      .where((w) => w.length >= 4 && !_stopwords.contains(w.toLowerCase()))
      .toList();
}

void main() {
  final arb =
      jsonDecode(File('lib/core/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

  group('SettingsSearch row-label coverage (issue #150 regression)', () {
    for (final entry in kSettingsCoverageLabelKeys.entries) {
      final key = entry.key;
      final expectedSectionId = entry.value;
      final label = arb[key] as String?;

      test(
        '"$key" ("$label") is findable under section "$expectedSectionId"',
        () {
          expect(label, isNotNull, reason: '$key missing from app_en.arb');
          final words = _significantWords(label!);
          expect(
            words,
            isNotEmpty,
            reason:
                'No significant (length >= 4, non-stopword) word in "$label" — '
                'add a manual keyword for it instead of relying on this test.',
          );

          final matchedSections = <String>{};
          for (final word in words) {
            final matches = matchSettingsEntries(
              kSettingsSearchTable,
              word,
              'en',
            );
            matchedSections.addAll(matches.map((m) => m.rowId));
          }

          expect(
            matchedSections,
            containsAnyOf(legacyRowIds(expectedSectionId)),
            reason:
                'None of $words (from "$label") match section '
                '"$expectedSectionId" in kSettingsSearchTable — this row would '
                'be unfindable via settings search. Add a keyword.',
          );
        },
      );
    }
  });
}
