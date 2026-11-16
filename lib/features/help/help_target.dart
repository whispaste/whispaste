/// Which Help tab a settings row jumps to (ticket).
library;

import '../../core/navigation/help_target.dart';

export '../../core/navigation/help_target.dart';

/// The Help tab that shows the settings row [rowId]. Rows that moved to Help
/// are the introduction replays, the contact rows (form, problem report,
/// ideas, email), the support rows (rating, star, sponsor chip) and the
/// diagnostics; anything else opens the handbook.
HelpTab helpTabForRow(String rowId) => switch (rowId) {
  'advanced-onboarding-again' => HelpTab.intro,
  'help-contact-form' ||
  'help-report-problem' ||
  'advanced-ideas' ||
  'help-contact-mail' => HelpTab.feedback,
  'advanced-review' ||
  'advanced-github-star' ||
  'general-sponsor-chip' => HelpTab.support,
  'help-diagnostics' ||
  'help-report-issue' ||
  'help-privacy-policy' ||
  'help-imprint' => HelpTab.diagnostics,
  _ => HelpTab.manual,
};
