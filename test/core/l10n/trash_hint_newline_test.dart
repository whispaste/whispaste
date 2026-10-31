/// The empty-trash hint is one message with a line break between its two
/// sentences. In the ARB files that break must be a real `\n`; a doubled
/// backslash would reach the screen as the literal characters `\n`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

void main() {
  for (final code in const ['de', 'en', 'es', 'pt', 'ru', 'he']) {
    test(
      'trash hint in $code renders a real line break, no literal \\n',
      () async {
        final l10n = await L10n.delegate.load(Locale(code));

        for (final days in const [0, 1, 30]) {
          final text = l10n.historyTrashEmptyHint(days);

          expect(text, contains('\n'), reason: 'days=$days');
          expect(text, isNot(contains(r'\')), reason: 'days=$days: $text');
        }
      },
    );
  }
}
