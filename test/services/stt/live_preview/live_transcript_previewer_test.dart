/// Unit tests for [LiveTranscriptPreviewer] — the sliding-window buffering +
/// fixed-timer/debounce trigger driving the during-recording live-transcript
/// preview.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt/live_preview/live_transcript_previewer.dart';

Uint8List _pcmChunk(int bytes) => Uint8List(bytes);

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

        previewer.addPcmChunk(_pcmChunk(1000));
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
        previewer.addPcmChunk(_pcmChunk(1000));

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
        previewer.addPcmChunk(_pcmChunk(1000));

        await previewer.onTriggerTick();
        expect(decodeCalls, 1);

        // Advance less than minDecodeInterval -> throttled, no new decode.
        now = now.add(const Duration(milliseconds: 500));
        previewer.addPcmChunk(_pcmChunk(1000));
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
        previewer.addPcmChunk(_pcmChunk(1000));
        await previewer.onTriggerTick();
        // The broadcast stream's onData dispatch is scheduled one
        // microtask turn after `add()`, so it can still be pending when
        // `onTriggerTick()`'s own await resolves — flush it before reading
        // `events`.
        await Future<void>.delayed(Duration.zero);

        now = now.add(const Duration(milliseconds: 200));
        previewer.addPcmChunk(_pcmChunk(1000));
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
      previewer.addPcmChunk(_pcmChunk(1000));
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
        previewer.addPcmChunk(_pcmChunk(1000));
        await previewer.onTriggerTick();
        await Future<void>.delayed(Duration.zero);

        expect(events, isEmpty);

        await sub.cancel();
        previewer.dispose();
      },
    );
  });
}
