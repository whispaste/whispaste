import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';

/// XP-6-07: the button in the hotkey dialog only empties the field. In
/// German it said "Zurücksetzen", which elsewhere means "back to the
/// default"; every other language already says "clear".
void main() {
  test('the German clear button says "Leeren"', () {
    expect(
      lookupL10n(const Locale('de')).settingsHotkeyRecorderClear,
      'Leeren',
    );
  });
}
