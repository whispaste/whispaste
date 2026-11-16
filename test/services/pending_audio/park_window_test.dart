/// The keep period of failed recordings (Settings → Privacy): one rule for all
/// paths, a 7-day default, and an additive settings migration.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/audio/retention/audio_retention.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart';

void main() {
  group('pendingAudioMaxAge', () {
    test('without retained audio the chosen keep period applies', () {
      expect(
        pendingAudioMaxAge(
          retainAudio: false,
          parkWindow: const Duration(days: 3),
        ),
        const Duration(days: 3),
      );
    });

    test('with retained audio the retention period applies instead', () {
      expect(
        pendingAudioMaxAge(
          retainAudio: true,
          parkWindow: const Duration(days: 3),
        ),
        kRetainedAudioMaxAge,
      );
    });

    test('the default keep period is 24 hours', () {
      expect(kDefaultParkWindow, const Duration(days: 1));
    });
  });

  group('PrivacySettings.failedAudioKeepDays', () {
    test('defaults to 24 hours', () {
      expect(PrivacySettings.defaults.failedAudioKeepDays, 1);
      expect(
        PrivacySettings.defaults.failedAudioKeepDuration,
        const Duration(days: 1),
      );
    });

    test('a settings file without the key reads as 24 hours (additive '
        'migration)', () {
      final settings = PrivacySettings.fromMap(const {});
      expect(settings.failedAudioKeepDays, 1);
    });

    test('a stored value is read back', () {
      final settings = PrivacySettings.fromMap(const {
        'failed_audio_keep_days': '14',
      });
      expect(settings.failedAudioKeepDays, 14);
    });

    test('a stored zero or garbage falls back to 24 hours', () {
      expect(
        PrivacySettings.fromMap(const {
          'failed_audio_keep_days': '0',
        }).failedAudioKeepDays,
        1,
      );
    });

    test('a saved choice of 7 days is kept (existing users)', () {
      final settings = PrivacySettings.fromMap(const {
        'failed_audio_keep_days': '7',
      });
      expect(settings.failedAudioKeepDays, 7);
    });

    test('the live path and the queue share one default', () {
      expect(
        kDefaultParkWindow,
        PrivacySettings.defaults.failedAudioKeepDuration,
      );
    });

    test('round-trips through toMap and copyWith', () {
      final changed = PrivacySettings.defaults.copyWith(
        failedAudioKeepDays: 30,
      );
      expect(changed.toMap()['failed_audio_keep_days'], '30');
      expect(PrivacySettings.fromMap(changed.toMap()), changed);
    });
  });
}
