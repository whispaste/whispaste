/// Unit tests for [LiveTranscriptPreviewer] — the sliding-window buffering +
/// fixed-timer/debounce trigger driving the during-recording live-transcript
/// preview.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/live_preview/live_transcript_previewer.dart';

/// 400 ms at 16 kHz: longer than the shortest run that counts as speech.
const _speechBytes = 12800;

/// A chunk of 16-bit mono PCM as a square wave of [amplitude] (default: a
/// clear speech level). Silence is `Uint8List(bytes)`.
Uint8List _pcmChunk(int bytes, {int amplitude = 8000}) {
  final out = Uint8List(bytes);
  final view = ByteData.sublistView(out);
  for (var i = 0; i + 1 < bytes; i += 2) {
    view.setInt16(i, (i ~/ 2).isEven ? amplitude : -amplitude, Endian.little);
  }
  return out;
}

void main() {
  group('LiveTranscriptPreviewer', () {
    test(
      'inactive by default; addPcmChunk and onTriggerTick are no-ops until start()',
      () async {
        var decodeCalls = 0;
        final previewer = LiveTranscriptPreviewer(
          decode: (samples) async {
            decodeCalls++;
            return 'text';
          },
        );

        expect(previewer.isActive, isFalse);

        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await previewer.onTriggerTick();

        expect(decodeCalls, 0);
        previewer.dispose();
      },
    );

    test(
      'start() then a fed chunk triggers exactly one decode on tick',
      () async {
        var decodeCalls = 0;
        final previewer = LiveTranscriptPreviewer(
          decode: (samples) async {
            decodeCalls++;
            return 'hello';
          },
        );

        previewer.start();
        expect(previewer.isActive, isTrue);
        previewer.addPcmChunk(_pcmChunk(_speechBytes));

        final events = <String>[];
        final sub = previewer.preview.listen(events.add);

        await previewer.onTriggerTick();
        await Future<void>.delayed(Duration.zero);

        expect(decodeCalls, 1);
        expect(events, ['hello']);

        await sub.cancel();
        previewer.dispose();
      },
    );

    test(
      'debounce: a second tick within minDecodeInterval is throttled',
      () async {
        var decodeCalls = 0;
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final previewer = LiveTranscriptPreviewer(
          decode: (samples) async {
            decodeCalls++;
            return 'text-$decodeCalls';
          },
          minDecodeInterval: const Duration(milliseconds: 1500),
          now: () => now,
        );

        previewer.start();
        previewer.addPcmChunk(_pcmChunk(_speechBytes));

        await previewer.onTriggerTick();
        expect(decodeCalls, 1);

        // Advance less than minDecodeInterval -> throttled, no new decode.
        now = now.add(const Duration(milliseconds: 500));
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await previewer.onTriggerTick();
        expect(
          decodeCalls,
          1,
          reason: 'tick within debounce window must be throttled',
        );

        // Advance past minDecodeInterval -> decode allowed again.
        now = now.add(
          const Duration(milliseconds: 1200),
        ); // total 1700ms since last decode
        await previewer.onTriggerTick();
        expect(decodeCalls, 2);

        previewer.dispose();
      },
    );

    test(
      'each preview event replaces the previous one (no accumulation)',
      () async {
        var call = 0;
        var now = DateTime(2026, 1, 1, 12, 0, 0);
        final previewer = LiveTranscriptPreviewer(
          decode: (samples) async {
            call++;
            return 'chunk-$call';
          },
          minDecodeInterval: const Duration(milliseconds: 100),
          now: () => now,
        );

        final events = <String>[];
        final sub = previewer.preview.listen(events.add);

        previewer.start();
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await previewer.onTriggerTick();
        // The broadcast stream's onData dispatch is scheduled one
        // microtask turn after `add()`, so it can still be pending when
        // `onTriggerTick()`'s own await resolves — flush it before reading
        // `events`.
        await Future<void>.delayed(Duration.zero);

        now = now.add(const Duration(milliseconds: 200));
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await previewer.onTriggerTick();
        await Future<void>.delayed(Duration.zero);

        expect(events, ['chunk-1', 'chunk-2']);

        await sub.cancel();
        previewer.dispose();
      },
    );

    test('stop() clears buffer and prevents further decodes', () async {
      var decodeCalls = 0;
      final previewer = LiveTranscriptPreviewer(
        decode: (samples) async {
          decodeCalls++;
          return 'text';
        },
      );

      previewer.start();
      previewer.addPcmChunk(_pcmChunk(_speechBytes));
      previewer.stop();

      expect(previewer.isActive, isFalse);
      await previewer.onTriggerTick();
      expect(decodeCalls, 0);

      previewer.dispose();
    });

    test(
      'a decode error does not crash and does not emit a preview event',
      () async {
        final previewer = LiveTranscriptPreviewer(
          decode: (samples) async => throw StateError('boom'),
        );

        final events = <String>[];
        final sub = previewer.preview.listen(events.add);

        previewer.start();
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await previewer.onTriggerTick();
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);

        await sub.cancel();
        previewer.dispose();
      },
    );
    group('LiveTranscriptPreviewer speech gate', () {
      late DateTime clock;
      late int decodeCalls;
      late LiveTranscriptPreviewer previewer;

      setUp(() {
        clock = DateTime(2026, 10, 30);
        decodeCalls = 0;
        previewer = LiveTranscriptPreviewer(
          decode: (samples) async {
            decodeCalls++;
            return 'text';
          },
          now: () => clock,
        )..start(armTimer: false);
      });

      tearDown(() => previewer.dispose());

      Future<void> tickLater() async {
        clock = clock.add(const Duration(seconds: 2));
        await previewer.onTriggerTick();
      }

      test('a tick over silence only does not decode', () async {
        previewer.addPcmChunk(Uint8List(1280));
        await tickLater();
        expect(decodeCalls, 0);
      });

      test('speech since the last decode lets the next tick decode', () async {
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await tickLater();
        expect(decodeCalls, 1);
      });

      test(
        'a decode consumes the speech; silence after it skips the tick',
        () async {
          previewer.addPcmChunk(_pcmChunk(_speechBytes));
          await tickLater();
          previewer.addPcmChunk(Uint8List(1280));
          await tickLater();
          expect(decodeCalls, 1);
        },
      );

      test('speech after a silent stretch decodes again', () async {
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await tickLater();
        previewer.addPcmChunk(Uint8List(12800));
        await tickLater();
        previewer.addPcmChunk(_pcmChunk(_speechBytes));
        await tickLater();
        expect(decodeCalls, 2);
      });

      test('a quiet microphone (-45 dBFS peak) gets a preview', () async {
        previewer.addPcmChunk(_pcmChunk(_speechBytes, amplitude: 184));
        await tickLater();
        expect(decodeCalls, 1);
      });

      test('room tone (-52 dBFS peak) starts no decode', () async {
        previewer.addPcmChunk(_pcmChunk(32000, amplitude: 82));
        await tickLater();
        expect(decodeCalls, 0);
      });

      test('a click shorter than the speech run starts no decode', () async {
        previewer.addPcmChunk(_pcmChunk(1280));
        previewer.addPcmChunk(Uint8List(12800));
        await tickLater();
        expect(decodeCalls, 0);
      });

      test('speech split into uneven chunks still counts', () async {
        final speech = _pcmChunk(_speechBytes);
        for (var i = 0; i < speech.length; i += 1000) {
          previewer.addPcmChunk(
            Uint8List.sublistView(
              speech,
              i,
              (i + 1000).clamp(0, speech.length),
            ),
          );
        }
        await tickLater();
        expect(decodeCalls, 1);
      });

      test(
        'stop() clears the gate, so a restarted session starts closed',
        () async {
          previewer.addPcmChunk(_pcmChunk(_speechBytes));
          previewer.stop();
          previewer.start(armTimer: false);
          await tickLater();
          expect(decodeCalls, 0);
        },
      );
    });
  });
}
