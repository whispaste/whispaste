/// Which Help tab a settings row jumps to (WP-78).
library;

import '../../core/navigation/help_target.dart';

export '../../core/navigation/help_target.dart';

/// The Help tab that shows the settings row [rowId]. Rows that moved to Help
/// are the introduction replays, the rating, ideas and sponsor rows, and the
/// diagnostics; anything else opens the handbook.
HelpTab helpTabForRow(String rowId) => switch (rowId) {
  'advanced-onboarding-again' || 'advanced-feature-spotlights' => HelpTab.intro,
  'advanced-review' ||
  'advanced-github-star' ||
  'advanced-ideas' ||
  'general-sponsor-chip' => HelpTab.support,
  'help-diagnostics' ||
  'help-report-issue' ||
  'help-privacy-policy' ||
  'help-imprint' => HelpTab.diagnostics,
  _ => HelpTab.manual,
};
