import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_de.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';

void main() {
  final l10n = L10nEn();

  group('displayNameForModel (NAM-01, NAM-07)', () {
    test('Parakeet is named by its family only, without a tier', () {
      expect(displayNameForModel('parakeet-tdt-0.6b-v3', l10n), 'Parakeet');
      expect(displayNameForModel('parakeet-tdt-0.6b-v3', L10nDe()), 'Parakeet');
    });

    test('a Whisper model reads as family · tier', () {
      expect(displayNameForModel('whisper-small', l10n), 'Whisper · Fast');
      expect(displayNameForModel('whisper-medium', l10n), 'Whisper · Balanced');
      expect(
        displayNameForModel('whisper-large-v3-turbo', l10n),
        'Whisper · Accurate',
      );
    });

    test('German uses the German tier words', () {
      expect(
        displayNameForModel('whisper-medium', L10nDe()),
        'Whisper · Ausgewogen',
      );
      expect(
        displayNameForModel('whisper-small', L10nDe()),
        'Whisper · Schnell',
      );
      expect(
        displayNameForModel('whisper-large-v3-turbo', L10nDe()),
        'Whisper · Genau',
      );
    });

    test('the main name carries no technical detail', () {
      for (final id in [
        'whisper-small',
        'whisper-medium',
        'whisper-large-v3-turbo',
        'parakeet-tdt-0.6b-v3',
      ]) {
        final name = displayNameForModel(id, l10n);
        expect(name, isNot(contains('MB')), reason: id);
        expect(name, isNot(contains('GB')), reason: id);
        expect(name, isNot(contains('small')), reason: id);
        expect(name, isNot(contains('turbo')), reason: id);
        expect(name, isNot(contains('q5')), reason: id);
      }
    });

    test('falls back to the raw ID for an unknown model', () {
      expect(displayNameForModel('some-unknown-id', l10n), 'some-unknown-id');
    });
  });
}
