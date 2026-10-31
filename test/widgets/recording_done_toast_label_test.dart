/// Tests the success-toast label chosen in `recording_behavior.dart`.
///
/// An edit-selection run must not announce "Transcription complete" — it
/// replaces the selected text instead. The label choice is a pure function
/// ([doneToastLabel]), so it is checked against the generated localizations
/// for every shipped UI language without mounting the recording wrapper.
library;

import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_state.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

void main() {
  for (final locale in L10n.supportedLocales) {
    group('doneToastLabel (${locale.toLanguageTag()})', () {
      late L10n l10n;

      setUpAll(() async {
        l10n = await L10n.delegate.load(locale);
      });

      test('selection edit does not say "transcription complete"', () {
        final label = doneToastLabel(l10n, RecordingTarget.selectionEdit);

        expect(label, l10n.statusSelectionEdited);
        expect(label, isNot(l10n.statusTranscriptionDone));
        expect(label.trim(), isNotEmpty);
      });

      test('normal dictation keeps the transcription label', () {
        expect(
          doneToastLabel(l10n, RecordingTarget.clipboard),
          l10n.statusTranscriptionDone,
        );
      });
    });
  }

  test('copy for each locale', () async {
    expect(
      (await L10n.delegate.load(const Locale('en'))).statusSelectionEdited,
      'Selection edited',
    );
    expect(
      (await L10n.delegate.load(const Locale('de'))).statusSelectionEdited,
      'Auswahl bearbeitet',
    );
    expect(
      (await L10n.delegate.load(const Locale('he'))).statusSelectionEdited,
      'הבחירה נערכה',
    );
    expect(
      (await L10n.delegate.load(const Locale('ru'))).statusSelectionEdited,
      'Выделение отредактировано',
    );
  });
}
