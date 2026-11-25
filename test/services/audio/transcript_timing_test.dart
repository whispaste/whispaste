import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/transcript_timing.dart';

/// A 16-bit mono WAV at [rate] whose [segments] alternate silence and tone:
/// each entry is a length in milliseconds, the first one silent.
Uint8List _wav(
  List<int> segments, {
  int rate = 16000,
  int channels = 1,
  bool unpatched = false,
}) {
  final samples = <int>[];
  var loud = false;
  for (final ms in segments) {
    final n = rate * ms ~/ 1000;
    for (var i = 0; i < n; i++) {
      samples.add(loud ? (i.isEven ? 8000 : -8000) : 0);
    }
    loud = !loud;
  }
  final dataBytes = samples.length * 2 * channels;
  final bytes = ByteData(44 + dataBytes);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2 * channels, Endian.little);
  bytes.setUint16(32, 2 * channels, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, unpatched ? 0 : dataBytes, Endian.little);
  var at = 44;
  for (final v in samples) {
    for (var c = 0; c < channels; c++) {
      bytes.setInt16(at, v, Endian.little);
      at += 2;
    }
  }
  return bytes.buffer.asUint8List();
}

List<String> _texts(String s) => [
  for (final x in splitTranscriptSentences(s)) x.text,
];

void main() {
  group('splitTranscriptSentences', () {
    test('ends sentences at punctuation and line breaks', () {
      expect(_texts('Hallo Welt. Wie geht es dir?! Gut…\nNeue Zeile'), [
        'Hallo Welt.',
        'Wie geht es dir?!',
        'Gut…',
        'Neue Zeile',
      ]);
    });

    test('keeps decimals and list numbers inside their sentence', () {
      expect(_texts('Es kostet 3.50 Euro. Fertig.'), [
        'Es kostet 3.50 Euro.',
        'Fertig.',
      ]);
      expect(_texts('1. Erster Punkt\n2. Zweiter Punkt'), [
        'Erster Punkt',
        'Zweiter Punkt',
      ]);
    });

    test('strips Markdown marks and drops pieces without words', () {
      expect(_texts('## Titel\n- **fett** und _kursiv_\n---\n> Zitat'), [
        'Titel',
        'fett und kursiv',
        'Zitat',
      ]);
    });

    test('offsets point at the visible sentence in the source', () {
      const text = 'Eins.   Zwei.';
      final s = splitTranscriptSentences(text);
      expect(text.substring(s[0].start, s[0].end), 'Eins.');
      expect(text.substring(s[1].start, s[1].end), 'Zwei.');
    });

    test('sentenceIndexAt finds the sentence of a caret', () {
      final s = splitTranscriptSentences('Eins. Zwei. Drei.');
      expect(sentenceIndexAt(s, 0), 0);
      expect(sentenceIndexAt(s, 5), 0);
      expect(sentenceIndexAt(s, 6), 1);
      expect(sentenceIndexAt(s, 99), 2);
      expect(sentenceIndexAt(const [], 0), isNull);
    });
  });

  group('analyzeSpeechActivity', () {
    test('marks sounding frames and measures the length', () {
      final a = analyzeSpeechActivity(_wav([100, 200, 100]));
      expect(a.length, const Duration(milliseconds: 400));
      expect(a.frames.length, 20);
      expect(a.frames.sublist(0, 5), everyElement(0));
      expect(a.frames.sublist(5, 15), everyElement(1));
      expect(a.frames.sublist(15), everyElement(0));
    });

    test('reads other rates, stereo and an unpatched data size', () {
      final a = analyzeSpeechActivity(
        _wav([0, 200], rate: 48000, channels: 2, unpatched: true),
      );
      expect(a.length, const Duration(milliseconds: 200));
      expect(a.frames, everyElement(1));
    });

    test('anything but 16-bit PCM WAV yields no activity', () {
      expect(analyzeSpeechActivity(Uint8List(0)).frames, isEmpty);
      expect(
        analyzeSpeechActivity(
          Uint8List.fromList('not a wav file'.codeUnits),
        ).frames,
        isEmpty,
      );
    });
  });

  group('estimateSentenceStarts', () {
    test('starts snap to the pauses between the spoken parts', () {
      // Three equally long sentences, spoken 1 s each with 0.5 s pauses.
      final activity = analyzeSpeechActivity(
        _wav([300, 1000, 500, 1000, 500, 1000, 300]),
      );
      final sentences = splitTranscriptSentences(
        'Eins zwei drei. Vier fünf sechs. Sieben acht neun.',
      );
      final starts = estimateSentenceStarts(sentences, activity);
      // Sound starts at 0.3 s, 1.8 s and 3.3 s, each minus the 160 ms lead.
      expect(starts, const [
        Duration(milliseconds: 140),
        Duration(milliseconds: 1640),
        Duration(milliseconds: 3140),
      ]);
    });

    test('a silent recording gives no marks', () {
      final activity = analyzeSpeechActivity(_wav([1000]));
      expect(
        estimateSentenceStarts(splitTranscriptSentences('Eins.'), activity),
        isEmpty,
      );
    });
  });

  group('alignTranscriptToBasis', () {
    final basis = splitTranscriptSentences(
      'Heute ist ein schöner Tag. Wir gehen in den Park. Danach essen wir Eis.',
    );

    test('small edits keep the mapping, new sentences get none', () {
      final current = splitTranscriptSentences(
        'Heute ist ein wirklich schöner Tag. Ganz neuer Gedanke hier. '
        'Danach essen wir Eis.',
      );
      expect(alignTranscriptToBasis(current, basis), [0, null, 2]);
    });

    test('a swapped order maps only one of the two', () {
      final current = splitTranscriptSentences(
        'Danach essen wir Eis. Heute ist ein schöner Tag.',
      );
      final map = alignTranscriptToBasis(current, basis);
      expect(map.whereType<int>().length, 1);
    });

    test('text without spaces compares by characters', () {
      final b = splitTranscriptSentences('今天天气很好。我们去公园散步吧。');
      final c = splitTranscriptSentences('今天天气非常好。我们去公园散步吧。');
      expect(b.length, 2);
      expect(alignTranscriptToBasis(c, b), [0, 1]);
    });
  });

  group('timeTranscript', () {
    final activity = analyzeSpeechActivity(
      _wav([300, 1000, 500, 1000, 500, 1000, 300]),
    );
    const basis = 'Eins zwei drei. Vier fünf sechs. Sieben acht neun.';

    test('an edited text keeps the marks it can and counts the rest', () {
      final t = timeTranscript(
        current: 'Eins zwei drei. Etwas ganz anderes. Sieben acht neun.',
        basis: basis,
        activity: activity,
      );
      expect(t.sentences.map((s) => s.start), const [
        Duration(milliseconds: 140),
        null,
        Duration(milliseconds: 3140),
      ]);
      expect(t.unmatchedCount, 1);
      expect(t.length, const Duration(milliseconds: 4600));
    });

    test('indexAt follows the playback position', () {
      final t = timeTranscript(
        current: basis,
        basis: basis,
        activity: activity,
      );
      expect(t.indexAt(Duration.zero), isNull);
      expect(t.indexAt(const Duration(milliseconds: 500)), 0);
      expect(t.indexAt(const Duration(seconds: 2)), 1);
      expect(t.indexAt(const Duration(seconds: 9)), 2);
    });

    test('without sound no sentence has a mark', () {
      final t = timeTranscript(
        current: basis,
        basis: basis,
        activity: SpeechActivity.empty,
      );
      expect(t.unmatchedCount, 3);
    });
  });
}
