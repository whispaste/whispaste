import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  group('localizeRecordingError cloud codes', () {
    final de = L10nDe();
    final en = L10nEn();

    test('cloud_auth_error maps to a specific, actionable message', () {
      // Regression: cloud auth failures used to surface the raw English
      // exception prose as the error code and fell through to errorGeneric.
      expect(localizeRecordingError(de, 'cloud_auth_error'), de.errorCloudAuth);
      expect(localizeRecordingError(en, 'cloud_auth_error'), en.errorCloudAuth);
      expect(
        localizeRecordingError(de, 'cloud_auth_error'),
        isNot(de.errorGeneric),
      );
    });

    test('cloud_quota_exceeded maps to the rate-limit message', () {
      expect(
        localizeRecordingError(de, 'cloud_quota_exceeded'),
        de.errorCloudQuota,
      );
    });

    test('unknown codes still fall back to errorGeneric', () {
      expect(localizeRecordingError(de, 'some_new_code'), de.errorGeneric);
    });
  });
}
