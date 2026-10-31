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

    test('cloud_network_error and cloud_timeout get their own messages, not '
        'the generic one (UIA-FLW-05)', () {
      expect(
        localizeRecordingError(de, 'cloud_network_error'),
        de.errorCloudNetwork,
      );
      expect(localizeRecordingError(de, 'cloud_timeout'), de.errorCloudTimeout);
      expect(
        localizeRecordingError(de, 'cloud_network_error'),
        isNot(de.errorGeneric),
      );
      expect(
        localizeRecordingError(de, 'cloud_timeout'),
        isNot(de.errorGeneric),
      );
    });

    test('the offline hint with a local model appears only when a local model '
        'is installed; otherwise the message says to check the connection '
        '(UIA-FLW-05)', () {
      expect(
        localizeRecordingError(en, 'cloud_network_error'),
        en.errorCloudNetwork,
      );
      expect(
        localizeRecordingError(
          en,
          'cloud_network_error',
          localModelInstalled: true,
        ),
        en.errorCloudNetworkLocal,
      );
      expect(localizeRecordingError(en, 'cloud_timeout'), en.errorCloudTimeout);
      expect(
        localizeRecordingError(en, 'cloud_timeout', localModelInstalled: true),
        en.errorCloudTimeoutLocal,
      );
    });

    test('Whisper and Parakeet model errors carry stable codes with their own '
        'messages, never the generic one (UIA-FLW-04)', () {
      expect(
        localizeRecordingError(de, 'stt_model_corrupted'),
        de.errorSttModelCorrupted,
      );
      expect(
        localizeRecordingError(de, 'stt_model_file_missing'),
        de.errorSttModelFileMissing,
      );
      expect(
        localizeRecordingError(de, 'parakeet_model_not_found'),
        de.errorSttModelFileMissing,
      );
      expect(
        localizeRecordingError(de, 'whisper_model_not_found'),
        de.errorSttModelFileMissing,
      );
      expect(
        localizeRecordingError(de, 'stt_model_load_failed'),
        de.errorSttModelLoadFailed,
      );
      expect(
        localizeRecordingError(de, 'whisper_init_failed'),
        de.errorSttModelLoadFailed,
      );
      expect(
        localizeRecordingError(de, 'stt_model_unknown'),
        de.errorSttModelUnknown,
      );
    });

    test('unknown codes still fall back to errorGeneric', () {
      expect(localizeRecordingError(de, 'some_new_code'), de.errorGeneric);
    });
  });
}
