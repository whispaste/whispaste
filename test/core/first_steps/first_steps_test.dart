/// Rules of the "Erste Schritte" card: which events confirm which item, when
/// the card is visible, and that an existing install never gets it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/first_steps/first_steps.dart';

const _all = {
  FirstStepsItem.firstPaste,
  FirstStepsItem.findAndCopy,
  FirstStepsItem.personalize,
  FirstStepsItem.noteDictation,
};

void main() {
  group('storage format', () {
    test('round-trips the done set in a stable order', () {
      const done = {FirstStepsItem.personalize, FirstStepsItem.firstPaste};
      final raw = serializeFirstStepsDone(done);
      expect(raw, 'first_paste,personalize');
      expect(parseFirstStepsDone(raw), done);
    });

    test('drops unknown and blank ids', () {
      expect(parseFirstStepsDone(' copy_recording , removed_item,, '), {
        FirstStepsItem.findAndCopy,
      });
    });

    test('an empty string is an empty set', () {
      expect(parseFirstStepsDone(''), isEmpty);
    });

    test('a card finished with the retired steps stays finished', () {
      final done = parseFirstStepsDone(
        'first_paste,long_dictation,personalize,overlay_look',
      );
      expect(firstStepsAllDone(done), isTrue);
    });

    test('a partly done old card keeps only the steps that remain', () {
      expect(parseFirstStepsDone('first_paste,long_dictation'), {
        FirstStepsItem.firstPaste,
      });
    });
  });

  group('dictation events', () {
    test('a paste that landed confirms the first paste', () {
      final done = firstStepsAfterDictation(
        done: const {},
        pasted: true,
        toNote: false,
        transcript: 'Hallo',
      );
      expect(done, {FirstStepsItem.firstPaste});
    });

    test('a dictation into a note confirms the note step', () {
      final done = firstStepsAfterDictation(
        done: const {},
        pasted: false,
        toNote: true,
        transcript: 'Einkauf',
      );
      expect(done, {FirstStepsItem.noteDictation});
    });

    test('an empty or blank transcript confirms nothing', () {
      for (final transcript in ['', '   ']) {
        final done = firstStepsAfterDictation(
          done: const {},
          pasted: true,
          toNote: true,
          transcript: transcript,
        );
        expect(done, isEmpty, reason: 'transcript "$transcript"');
      }
    });

    test('confirmed items are kept', () {
      final done = firstStepsAfterDictation(
        done: const {FirstStepsItem.personalize},
        pasted: false,
        toNote: false,
        transcript: 'x',
      );
      expect(done, {FirstStepsItem.personalize});
    });
  });

  group('history target apps', () {
    test('another app confirms the first step in copy-only mode', () {
      expect(
        firstStepsAfterHistory(done: const {}, targetApps: ['Warp-Stable']),
        {FirstStepsItem.firstPaste},
      );
    });

    test('WhisPaste itself or no target confirms nothing', () {
      for (final app in [
        'de.whispaste.app',
        'de.whispaste.app.preview',
        'WhisPaste.exe',
        'whispaste',
        '',
        null,
      ]) {
        expect(
          firstStepsAfterHistory(done: const {}, targetApps: [app]),
          isEmpty,
          reason: 'target "$app"',
        );
      }
    });

    test('an earlier dictation into another app confirms it', () {
      expect(
        firstStepsAfterHistory(
          done: const {FirstStepsItem.personalize},
          targetApps: [null, 'de.whispaste.app', 'com.microsoft.VSCode'],
        ),
        {FirstStepsItem.personalize, FirstStepsItem.firstPaste},
      );
    });
  });

  group('copy', () {
    test('a copied recording confirms its step and keeps the rest', () {
      expect(firstStepsAfterCopy(const {FirstStepsItem.firstPaste}), {
        FirstStepsItem.firstPaste,
        FirstStepsItem.findAndCopy,
      });
    });
  });

  group('vocabulary', () {
    test('a non-blank custom vocabulary confirms personalisation', () {
      expect(
        firstStepsAfterVocabulary(
          done: const {},
          customVocabulary: 'Supabase, Kubernetes',
        ),
        {FirstStepsItem.personalize},
      );
    });

    test('a blank vocabulary confirms nothing', () {
      expect(
        firstStepsAfterVocabulary(done: const {}, customVocabulary: '  '),
        isEmpty,
      );
    });
  });

  group('visibility', () {
    bool visible({
      bool armed = true,
      bool dismissed = false,
      bool busy = false,
      Set<FirstStepsItem> done = const {},
      bool celebrating = false,
    }) => firstStepsVisible(
      armed: armed,
      dismissed: dismissed,
      busy: busy,
      done: done,
      celebrating: celebrating,
    );

    test('shown for an armed card with open items', () {
      expect(visible(done: const {FirstStepsItem.firstPaste}), isTrue);
    });

    test('never shown when not armed', () {
      expect(visible(armed: false), isFalse);
    });

    test('never shown after it was closed', () {
      expect(visible(dismissed: true), isFalse);
    });

    test('never shown while a dictation runs', () {
      expect(visible(busy: true), isFalse);
      expect(visible(busy: true, celebrating: true), isFalse);
    });

    test('once every item is done only the success state shows', () {
      expect(visible(done: _all), isFalse);
      expect(visible(done: _all, celebrating: true), isTrue);
    });

    test('"Neu anzeigen" has something to bring back only while open', () {
      expect(firstStepsCanShowAgain(armed: true, done: const {}), isTrue);
      expect(firstStepsCanShowAgain(armed: true, done: _all), isFalse);
      expect(firstStepsCanShowAgain(armed: false, done: const {}), isFalse);
    });
  });

  group('existing installs', () {
    test('a default settings record is not armed', () {
      expect(OnboardingSettings.defaults.firstStepsArmed, isFalse);
      expect(OnboardingSettings.fromMap(const {}).firstStepsArmed, isFalse);
    });

    test('a completed install from before the card never gets it', () {
      final onboarding = OnboardingSettings.fromMap(const {
        'onboarding_completed': 'true',
        'onboarding_flow_version': '4',
      });
      expect(
        firstStepsVisible(
          armed: onboarding.firstStepsArmed,
          dismissed: onboarding.firstStepsDismissed,
          busy: false,
          done: parseFirstStepsDone(onboarding.firstStepsDone),
          celebrating: false,
        ),
        isFalse,
      );
    });
  });

  group('persistence keys', () {
    test('survive a storage round trip', () {
      const onboarding = OnboardingSettings(
        firstStepsArmed: true,
        firstStepsDismissed: true,
        firstStepsDone: 'first_paste,personalize',
      );
      final restored = OnboardingSettings.fromMap(onboarding.toMap());
      expect(restored, onboarding);
    });
  });
}
