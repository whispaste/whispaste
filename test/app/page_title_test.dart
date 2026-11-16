/// Page titles for the app shell header (UIA-SHL-07): every routable page,
/// the Feedback page included, must name itself.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/app.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  test('feedback page has a header title', () {
    final l10n = lookupL10n(const Locale('de'));
    final title = wpPageTitle('feedback', const [], l10n);
    expect(title, isNotEmpty);
    expect(title, l10n.feedbackTitle);
  });
}
