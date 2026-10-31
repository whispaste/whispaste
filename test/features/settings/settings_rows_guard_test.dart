/// Guard for the row table (WP-23, spec §7.1 and §3): all 84 settings rows
/// exist once, carry a stable kebab-case rowId and an area, and every label
/// key of the search coverage registry appears exactly once in the table.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';
import 'package:whispaste/features/settings/settings_areas.dart';

import 'search/settings_row_label_keys.dart';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/core/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final en = _arb('en');

  test(
    'the table holds exactly the 156 rows (the repaste hotkey row (2026-10-30), the first-steps restore row (2026-10-30), the six written-form rows of the text area (2026-10-30), the double-tap hands-free row (2026-10-30), the eight own-endpoint rows of W-M3 in speech and Smart Mode, the three hotkey gesture rows, hold-or-tap threshold, spec §3, the snippet picker trigger row of the general area (R3 UX ports), the GPU check row of the speech area, the 11 profile rows of the Profiles area (2026-10-19), the next-favorite-language hotkey row in the Dictation card, the retry list of kept recordings (UIA-FLW-01), the rating-reminder restore row (UIA-C2), the Smart Mode link row to the Keyboard shortcuts area (2026-10-19), the quick-note open-in-main-window row (UIA-SHL-08), the two automation rows, spoken punctuation, the overlay background/wave split, the About and Help rows of WP-78, the six WP-95 overlay option rows, the four floating button look rows, the WP-33a blocklist copy switch and clipboard-after-paste setting and the two keep-model-loaded rows and the permanent GitHub star row and the Linux Wayland limits row of the floating button card and the failed-recording retention row of the Privacy area (183ec9128) and the clipboard-without-receipt row of W-E1 and the two Save-recordings rows (privacy-history-save, privacy-history-delete-existing)',
    () {
      expect(kSettingsSearchTable, hasLength(156));
    },
  );

  test('every rowId is unique and kebab-case', () {
    final ids = kSettingsSearchTable.map((r) => r.rowId).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'duplicate rowId');
    final kebab = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
    for (final id in ids) {
      expect(kebab.hasMatch(id), isTrue, reason: '"$id" is not kebab-case');
    }
  });

  test('every coverage label key appears exactly once in the table', () {
    for (final key in kSettingsCoverageLabelKeys.keys) {
      final hits = kSettingsSearchTable
          .where((r) => r.labelKey == key || r.cardKey == key)
          .length;
      expect(hits, 1, reason: '"$key" appears $hits times');
    }
  });

  test('every row label key exists in app_en.arb', () {
    for (final row in kSettingsSearchTable) {
      expect(
        en.containsKey(row.labelKey),
        isTrue,
        reason: '${row.rowId} uses unknown key "${row.labelKey}"',
      );
    }
  });

  test('every row resolves to a non-empty title in English', () async {
    final l10n = await L10n.delegate.load(const Locale('en'));
    for (final row in kSettingsSearchTable) {
      expect(row.titleOf(l10n).trim(), isNotEmpty, reason: row.rowId);
    }
  });

  test('every row names an area that exists in the navigation', () {
    for (final row in kSettingsSearchTable) {
      if (row.area == SettingsRowArea.help) {
        // Help rows live on the Hilfe page, which is not a settings area.
        expect(row.hostArea, isNull, reason: row.rowId);
      } else {
        expect(row.hostArea, isA<SettingsArea>(), reason: row.rowId);
      }
    }
  });

  test('the rows moved to the Help page (UX-015, WP-78) are exactly these', () {
    expect(
      kSettingsSearchTable
          .where((row) => row.area == SettingsRowArea.help)
          .map((row) => row.rowId)
          .toSet(),
      {
        'general-sponsor-chip',
        'advanced-onboarding-again',
        'advanced-review',
        'advanced-github-star',
        'advanced-ideas',
        'help-diagnostics',
        'help-report-issue',
        'help-privacy-policy',
        'help-imprint',
      },
    );
  });

  test('the four migrated deep links resolve to their rows', () {
    expect(
      settingsRowAnchorFor('text-after-dictation-action')?.hostArea,
      SettingsArea.textInsert,
    );
    expect(
      settingsRowAnchorFor('general-hotkey-dictation')?.hostArea,
      SettingsArea.shortcuts,
    );
    expect(settingsRowAnchorFor('stt-model')?.hostArea, SettingsArea.speech);
    expect(
      settingsRowAnchorFor('advanced-automation-api')?.hostArea,
      SettingsArea.advanced,
    );
  });
}
