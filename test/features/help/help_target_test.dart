/// Which Help tab a settings row jumps to (WP-78). Every row that moved to the
/// Help page maps to exactly one tab, and the handbook has a tab of its own.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/help/help_target.dart';
import 'package:whispaste/features/settings/search/settings_search_entry.dart';

void main() {
  test('the replay rows open the introduction tab', () {
    expect(helpTabForRow('advanced-onboarding-again'), HelpTab.intro);
  });

  test('the rating, ideas and sponsor rows open the support tab', () {
    expect(helpTabForRow('advanced-review'), HelpTab.support);
    expect(helpTabForRow('advanced-github-star'), HelpTab.support);
    expect(helpTabForRow('advanced-ideas'), HelpTab.support);
    expect(helpTabForRow('general-sponsor-chip'), HelpTab.support);
  });

  test('the diagnostics and issue rows open the diagnostics tab', () {
    expect(helpTabForRow('help-diagnostics'), HelpTab.diagnostics);
    expect(helpTabForRow('help-report-issue'), HelpTab.diagnostics);
  });

  test('no help row of the search table falls back to the handbook', () {
    final helpRows = kSettingsSearchTable.where(
      (row) => row.area == SettingsRowArea.help,
    );
    expect(helpRows, isNotEmpty);
    for (final row in helpRows) {
      expect(
        helpTabForRow(row.rowId),
        isNot(HelpTab.manual),
        reason: row.rowId,
      );
    }
  });

  test('an unknown row opens the handbook', () {
    expect(helpTabForRow('no-such-row'), HelpTab.manual);
  });
}
