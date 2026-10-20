/// The done label names what actually happened to the transcript. It follows
/// the real target and the real paste result, not only the global setting.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/recording/recording_helpers.dart';
import 'package:whispaste/core/recording/recording_state.dart';

void main() {
  late L10n l10n;

  setUpAll(() async {
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  group('doneMessageFor copied only (GS-075)', () {
    for (final action in [
      AfterTranscriptionAction.paste,
      AfterTranscriptionAction.clipboardAndPaste,
      AfterTranscriptionAction.clipboard,
    ]) {
      test('a blocked ${action.value} reads "Only copied", never "Pasted"', () {
        expect(
          doneMessageFor(action.value, l10n, copiedOnly: true),
          l10n.overlayDoneCopiedOnly,
        );
      });
    }
  });

  group('doneMessageFor history only (maintainer 4a+c)', () {
    for (final action in [
      AfterTranscriptionAction.paste,
      AfterTranscriptionAction.clipboardAndPaste,
      AfterTranscriptionAction.clipboard,
    ]) {
      test('a blocked ${action.value} with the copy switch off reads "Not '
          'pasted", never "Only copied"', () {
        expect(
          doneMessageFor(action.value, l10n, historyOnly: true),
          l10n.overlayDoneNotPasted,
        );
      });
    }
  });

  group('doneMessageFor', () {
    test('copy-only outcome reads "Copied", never "Pasted"', () {
      expect(
        doneMessageFor(AfterTranscriptionAction.clipboard.value, l10n),
        l10n.overlayDone,
      );
    });

    test('paste outcome reads "Pasted"', () {
      expect(
        doneMessageFor(AfterTranscriptionAction.paste.value, l10n),
        l10n.overlayDonePasted,
      );
    });

    test('quick note reads as a note, even when the setting pastes', () {
      expect(
        doneMessageFor(
          AfterTranscriptionAction.paste.value,
          l10n,
          target: RecordingTarget.quickNote,
        ),
        l10n.overlayDoneQuickNote,
      );
    });

    test('selection edit reads as an edit, even when the setting pastes', () {
      expect(
        doneMessageFor(
          AfterTranscriptionAction.paste.value,
          l10n,
          target: RecordingTarget.selectionEdit,
        ),
        l10n.overlayDoneSelectionEdit,
      );
    });

    test('a failed paste never reads "Pasted"', () {
      final label = doneMessageFor(
        AfterTranscriptionAction.paste.value,
        l10n,
        pasteFailed: true,
      );
      expect(label, l10n.overlayDonePasteFailed);
      expect(label, isNot(l10n.overlayDonePasted));
    });

    test('a failed copy-and-paste never reads "Copied & pasted"', () {
      expect(
        doneMessageFor(
          AfterTranscriptionAction.clipboardAndPaste.value,
          l10n,
          pasteFailed: true,
        ),
        l10n.overlayDonePasteFailed,
      );
    });
  });
}
