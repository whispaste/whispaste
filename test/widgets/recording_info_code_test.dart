/// An unknown recording info code shows the generic localized error, never
/// the raw code (UIA-SHL-16).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  test('an unknown info code is localised to the generic error text', () async {
    final l10n = await L10n.delegate.load(const Locale('de'));

    expect(localizeRecordingInfo(l10n, 'info_made_up_code'), l10n.errorGeneric);
    expect(
      localizeRecordingInfo(l10n, 'info_made_up_code'),
      isNot('info_made_up_code'),
    );
  });
}
