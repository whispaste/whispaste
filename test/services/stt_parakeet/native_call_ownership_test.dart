/// A native Parakeet decode counts as running until the worker actually
/// answers, not until a Dart-side timeout gives up on it (ledger Lauf 15,
/// Befund 19). The quit guard relies on this: a decode still inside the
/// worker must end the process without static destructors (GS-117).
///
/// Both engines are driven against a stand-in worker port that never
/// replies, so the decode outlives the Dart timeout exactly like a hung
/// Metal/CUDA call does.
library;

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt/stt_benchmark.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_engine_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_engine.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_speech_gate.dart';

void main() {
  test('sherpa: a decode the Dart timeout gave up on still counts as running '
      'until the worker answers, also for the quit path', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final notifier = container.read(parakeetEngineProvider.notifier);
      // Stand-in worker: receives requests, never replies.
      final worker = ReceivePort();
      notifier
        ..debugSpeechGate = ParakeetSpeechGate(
          libraryPath: '/nonexistent/libwhisper',
          modelPath: '/nonexistent/vad',
        )
        ..debugAttachWorkerForTest(worker.sendPort);

      Object? failure;
      notifier
          .transcribeWavBytes(SttBenchmark.generateBenchmarkWav())
          .then<void>((_) {}, onError: (Object e) => failure = e);
      // The Dart timeout for a 3 s clip is the 30 s floor.
      async.elapse(const Duration(seconds: 31));

      expect(
        failure,
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'parakeet_transcribe_timeout',
        ),
      );
      expect(
        notifier.hasNativeCallRunning,
        isTrue,
        reason: 'the worker has not answered, so the native call still runs',
      );

      unawaited(notifier.stopForQuit());
      expect(
        notifier.hasNativeCallRunning,
        isTrue,
        reason: 'the quit guard must still see the unanswered decode',
      );

      worker.close();
      container.dispose();
    });
  });

  test('gpu: a decode the Dart timeout gave up on still counts as running '
      'until the worker answers', () async {
    final worker = ReceivePort();
    addTearDown(worker.close);
    final engine = ParakeetGpuEngine.forTesting(worker.sendPort);

    await expectLater(
      engine.transcribe(
        Float32List(16000),
        timeout: const Duration(milliseconds: 5),
        abortGrace: const Duration(milliseconds: 5),
      ),
      throwsA(isA<ParakeetGpuException>()),
    );
    expect(
      engine.hasNativeCallRunning,
      isTrue,
      reason: 'the worker has not answered, so the native call still runs',
    );
  });
}
