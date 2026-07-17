import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';

void main() {
  final l10n = L10nEn();

  group('displayNameForModel', () {
    test('maps the parakeet model ID to its display title', () {
      expect(
        displayNameForModel('parakeet-tdt-0.6b-v3', l10n),
        l10n.parakeetModelTitle,
      );
    });

    test('maps a known whisper model ID to a tier label', () {
      expect(
        displayNameForModel('whisper-medium', l10n),
        l10n.analyticsModelDisplayName(l10n.qualityTierBalancedLabel, 'Medium'),
      );
    });

    test('falls back to the raw ID for an unknown model', () {
      expect(displayNameForModel('some-unknown-id', l10n), 'some-unknown-id');
    });
  });
}
