import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/transcript_hallucination_filter.dart';

void main() {
  group('isKnownHallucinationPhrase', () {
    test(
      'matches a known closing phrase regardless of case and punctuation',
      () {
        expect(isKnownHallucinationPhrase('Thanks for watching!'), isTrue);
        expect(
          isKnownHallucinationPhrase('  thank you for watching. '),
          isTrue,
        );
        expect(isKnownHallucinationPhrase('Danke fürs Zuschauen!'), isTrue);
        expect(
          isKnownHallucinationPhrase('Untertitel der Amara.org-Community'),
          isTrue,
        );
      },
    );

    test('does not match when the phrase is only part of the transcript', () {
      expect(
        isKnownHallucinationPhrase('Ich sage gerade thanks for watching.'),
        isFalse,
      );
    });

    test('does not match ordinary short dictation', () {
      expect(isKnownHallucinationPhrase('Vielen Dank.'), isFalse);
      expect(isKnownHallucinationPhrase('Thank you.'), isFalse);
    });

    test('does not match an empty transcript', () {
      expect(isKnownHallucinationPhrase(''), isFalse);
      expect(isKnownHallucinationPhrase('   '), isFalse);
    });
  });

  group('isNonSpeechTranscript', () {
    test('a lone sound annotation in round brackets is not speech', () {
      for (final text in [
        '(Musik)',
        '(music)',
        '( Applaus )',
        '(Applause).',
        '(музыка)',
        '(מוזיקה)',
        '[Musik]',
      ]) {
        expect(isNonSpeechTranscript(text), isTrue, reason: text);
      }
    });

    test('a phrase alone is not evidence of non-speech', () {
      expect(isNonSpeechTranscript('Thank you for watching.'), isFalse);
    });

    test('dictated brackets and other bracketed text are kept', () {
      expect(isNonSpeechTranscript('Ich sage (Musik) laut.'), isFalse);
      expect(isNonSpeechTranscript('(siehe oben)'), isFalse);
      expect(isNonSpeechTranscript('(Musik) (Applaus)'), isFalse);
      expect(isNonSpeechTranscript('Musik'), isFalse);
      expect(isNonSpeechTranscript(''), isFalse);
    });
  });

  corpus();
}

/// Signals of the corpus below, from no evidence to the strongest.
const _noSignal = SilenceSignal.none;
const _lowTailConfidence = SilenceSignal(tailMinP: 0.12);
const _engineNoSpeech = SilenceSignal(noSpeechProb: 0.85);
const _silentTail = SilenceSignal(trailingSilenceMs: 2400);
const _silentAudio = SilenceSignal(silentAudio: true, trailingSilenceMs: 6000);
const _allSignals = [
  _noSignal,
  _lowTailConfidence,
  _engineNoSpeech,
  _silentTail,
  _silentAudio,
];

/// Dictations people really say (#2013 acceptance corpus). None of them may
/// lose a character under any signal: they are not stock phrases, or only
/// contain one inside a longer sentence.
const _realDictations = [
  'Hallo Maria, ich schicke dir morgen die Unterlagen.',
  'Bitte ruf mich zurück, sobald du Zeit hast.',
  'Das Video hat drei Teile. Im letzten erkläre ich die Einstellungen.',
  'Am Ende des Videos sage ich immer: Danke fürs Zuschauen und bis bald.',
  'Ich sage gerade thanks for watching.',
  'Die Untertitel kommen von Anna, sie hat das gestern fertig gemacht.',
  'Thank you for the quick reply, I will check the numbers tomorrow.',
  'Please send me the subtitles by Friday.',
  'Gracias por ver el informe tan rápido.',
  'Merci pour ton message, je te rappelle demain.',
  'Grazie per la visione del documento, ci sentiamo domani.',
  'Obrigado pela ajuda com o relatório.',
  'Спасибо за помощь, увидимся завтра.',
  '我们明天下午三点开会。谢谢大家的支持。',
  'Wir treffen uns um 14 Uhr. Ähm, eigentlich lieber um 15 Uhr.',
  'Hmm, das muss ich mir noch überlegen.',
  'Er sagte: So nicht!',
  'Okay, dann machen wir das so.',
  'Die Domain ist amara.org, bitte notieren.',
  'Vielen Dank für die schnelle Antwort. Bis morgen.',
];

/// Dictations a speaker ends with a real closing word. Kept with every
/// signal except the strong whole-recording one, which a spoken word cannot
/// produce (the audio would reach voice level).
const _realClosings = [
  'Ich melde mich nächste Woche. Vielen Dank.',
  'Das passt so. Danke.',
  'Alles klar, so machen wir es. Okay.',
  'See you at the meeting. Thank you.',
];

/// (transcript, signal, expected result): text invented on a silent end.
const _inventedEndings = [
  // Whole transcripts on silence.
  ('Untertitel im Auftrag des ZDF für funk, 2017', _lowTailConfidence, ''),
  ('Untertitel von Stephanie Geiges', _lowTailConfidence, ''),
  ('Vielen Dank.', _silentAudio, ''),
  ('Amen.', _silentAudio, ''),
  ('So.', _engineNoSpeech, ''),
  ('...', _silentAudio, ''),
  ('Mhm.', _silentTail, ''),
  ('Ähm.', _silentTail, ''),
  ('Yeah.', _silentAudio, ''),
  ('Sous-titrage ST\' 501', _lowTailConfidence, ''),
  ('Продолжение следует...', _lowTailConfidence, ''),
  ('字幕由Amara.org社区提供', _lowTailConfidence, ''),
  ('Gracias por ver el video.', _engineNoSpeech, ''),
  // A silent end after real dictation.
  (
    'Ich schreibe dir später. Untertitel im Auftrag des ZDF, 2021.',
    _lowTailConfidence,
    'Ich schreibe dir später.',
  ),
  (
    'Wir sehen uns morgen. Vielen Dank fürs Zuschauen!',
    _engineNoSpeech,
    'Wir sehen uns morgen.',
  ),
  (
    'Send me the file. Thank you for watching. Please subscribe.',
    _lowTailConfidence,
    'Send me the file.',
  ),
  (
    'Das Meeting ist um zehn. Ähm. Mhm.',
    _silentTail,
    'Das Meeting ist um zehn.',
  ),
  ('Call me back. Uh.', _silentTail, 'Call me back.'),
  ('明天见。谢谢观看。', _lowTailConfidence, '明天见。'),
  (
    'Je te rappelle demain. Merci d\'avoir regardé !',
    _lowTailConfidence,
    'Je te rappelle demain.',
  ),
];

void corpus() {
  group('dropInventedText corpus (#2013)', () {
    test('no real dictation in the corpus loses text under any signal', () {
      for (final text in _realDictations) {
        for (final signal in _allSignals) {
          expect(
            dropInventedText(text, signal),
            text,
            reason: '$text with $signal',
          );
        }
      }
    });

    test('a real closing word survives without strong evidence', () {
      for (final text in _realClosings) {
        for (final signal in [
          _noSignal,
          _lowTailConfidence,
          _engineNoSpeech,
          _silentTail,
        ]) {
          expect(
            dropInventedText(text, signal),
            text,
            reason: '$text with $signal',
          );
        }
      }
    });

    test('text invented on a silent end is removed', () {
      for (final (text, signal, expected) in _inventedEndings) {
        expect(
          dropInventedText(text, signal),
          expected,
          reason: '$text with $signal',
        );
      }
    });

    test('without a silence signal the same endings stay', () {
      for (final (text, _, _) in _inventedEndings) {
        final kept = dropInventedText(text, _noSignal);
        expect(kept, text.trim(), reason: text);
      }
    });

    test('stock phrases need the engine or audio, a silent tail alone only '
        'removes fillers', () {
      expect(
        dropInventedText('Bis morgen. Bis zum nächsten Mal.', _silentTail),
        'Bis morgen. Bis zum nächsten Mal.',
      );
      expect(
        dropInventedText(
          'Bis morgen. Bis zum nächsten Mal.',
          _lowTailConfidence,
        ),
        'Bis morgen.',
      );
    });

    test('a tail silence below the threshold keeps fillers', () {
      expect(
        dropInventedText(
          'Gut. Ähm.',
          const SilenceSignal(trailingSilenceMs: kSilentTailMs - 20),
        ),
        'Gut. Ähm.',
      );
    });

    test('a dot inside a word is no sentence end', () {
      expect(
        dropInventedText('Untertitel der Amara.org-Community', _noSignal),
        'Untertitel der Amara.org-Community',
      );
      expect(
        dropInventedText(
          'Notiz dazu. Subtitles by the Amara.org community',
          _lowTailConfidence,
        ),
        'Notiz dazu.',
      );
    });

    test('core phrases require silence, sound annotations do not', () {
      for (final text in [
        'Thanks for watching!',
        'Vielen Dank fürs Zuschauen.',
        'Untertitel im Auftrag des ZDF.',
      ]) {
        expect(dropInventedText(text, _noSignal), text);
        expect(dropInventedText(text, _lowTailConfidence), '');
        expect(dropInventedText(text, _engineNoSpeech), '');
      }
      expect(dropInventedText('(Musik)', _noSignal), '');
    });
  });

  group('SilenceSignal', () {
    test('noSpeechProb from 0.6 is strong evidence', () {
      expect(const SilenceSignal(noSpeechProb: 0.6).strong, isTrue);
      expect(const SilenceSignal(noSpeechProb: 0.59).strong, isFalse);
      // whisper.cpp v1.9.5 reports ~0 (#1742): no evidence.
      expect(const SilenceSignal(noSpeechProb: 0).tailNotSpoken, isFalse);
    });

    test('low end confidence is evidence for the tail, not strong', () {
      const s = SilenceSignal(tailMinP: 0.39);
      expect(s.tailNotSpoken, isTrue);
      expect(s.strong, isFalse);
      expect(const SilenceSignal(tailMinP: 0.4).tailNotSpoken, isFalse);
    });

    test('merge keeps the stronger value of each field', () {
      final m = const SilenceSignal(
        noSpeechProb: 0.1,
        tailMinP: 0.8,
      ).merge(const SilenceSignal(tailMinP: 0.3, trailingSilenceMs: 1500));
      expect(m.noSpeechProb, 0.1);
      expect(m.tailMinP, 0.3);
      expect(m.trailingSilenceMs, 1500);
      expect(m.silentAudio, isFalse);
    });
  });
}
