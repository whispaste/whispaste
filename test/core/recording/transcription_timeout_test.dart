/// One time budget for local engines, the old formula for cloud (#1639).
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/recording/transcription_budget.dart';
import 'package:whispaste/services/stt/transcription_deadline.dart';

void main() {
  group('cloudTranscriptionTimeout', () {
    test('keeps 60 s + 0.8 x audio', () {
      expect(
        cloudTranscriptionTimeout(const Duration(seconds: 10)),
        const Duration(seconds: 68),
      );
      expect(
        cloudTranscriptionTimeout(const Duration(seconds: 120)),
        const Duration(seconds: 156),
      );
      expect(
        cloudTranscriptionTimeout(const Duration(minutes: 60)),
        const Duration(seconds: 2940),
      );
    });
  });

  group('localTranscriptionBudget', () {
    test('unmeasured: 60 s + 3 x audio', () {
      expect(
        localTranscriptionBudget(const Duration(minutes: 10)),
        const Duration(minutes: 31),
      );
      expect(localTranscriptionBudget(Duration.zero), kLocalBudgetBase);
    });

    test('a CPU above RTF 0.8 is no longer cut off by the cloud formula', () {
      // RTF 1.2: the old 60 s + 0.8 x audio failed every 10-min recording.
      const audio = Duration(minutes: 10);
      final budget = localTranscriptionBudget(audio, measuredRtf: 1.2);
      expect(budget, greaterThan(audio * 1.2));
      expect(budget, greaterThan(cloudTranscriptionTimeout(audio)));
    });

    test('a fast machine keeps at least 1 x audio', () {
      expect(
        localTranscriptionBudget(
          const Duration(minutes: 60),
          measuredRtf: 0.03,
        ),
        const Duration(minutes: 61),
      );
    });

    test('the overrun boost doubles the factor, capped at 8 x audio', () {
      const audio = Duration(minutes: 10);
      expect(
        localTranscriptionBudget(audio, boost: 2),
        const Duration(minutes: 61),
      );
      expect(
        localTranscriptionBudget(audio, boost: 4),
        localTranscriptionHardCap(audio),
      );
      expect(localTranscriptionHardCap(audio), const Duration(minutes: 81));
    });

    test('a bad measurement falls back to the unmeasured factor', () {
      expect(localBudgetFactor(measuredRtf: 0), kLocalBudgetUnknownFactor);
      expect(
        localBudgetFactor(measuredRtf: double.nan),
        kLocalBudgetUnknownFactor,
      );
    });
  });

  group('backstops sit above the local budget', () {
    test('orchestrator and state-machine guards fire after the engine', () {
      for (final audio in const [
        Duration(seconds: 5),
        Duration(minutes: 10),
        Duration(minutes: 60),
      ]) {
        final orchestrator = localOrchestratorTimeout(audio);
        expect(
          orchestrator,
          greaterThan(localTranscriptionHardCap(audio) + kLocalAbortGrace),
        );
        expect(
          transcriptionStuckBudget(audio, floor: const Duration(minutes: 5)),
          greaterThan(orchestrator),
        );
      }
    });

    test('the stuck guard keeps its floor for short recordings', () {
      expect(
        transcriptionStuckBudget(
          const Duration(seconds: 1),
          floor: const Duration(minutes: 5),
        ),
        const Duration(minutes: 5),
      );
    });
  });

  group('TranscriptionDeadline', () {
    test('times out at the initial budget without progress', () {
      fakeAsync((async) {
        final deadline = TranscriptionDeadline(
          initial: const Duration(seconds: 10),
          stallWindow: const Duration(seconds: 5),
          hardCap: const Duration(seconds: 60),
        );
        Object? error;
        deadline
            .guard(Completer<String>().future)
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 9));
        expect(error, isNull);
        async.elapse(const Duration(seconds: 2));
        expect(error, isA<TimeoutException>());
      });
    });

    test('progress extends the deadline while it continues', () {
      fakeAsync((async) {
        final deadline = TranscriptionDeadline(
          initial: const Duration(seconds: 10),
          stallWindow: const Duration(seconds: 8),
          hardCap: const Duration(seconds: 60),
        );
        final work = Completer<String>();
        String? text;
        Object? error;
        deadline
            .guard(work.future)
            .then<void>((t) => text = t, onError: (Object e) => error = e);
        // Progress every 6 s: each report pushes the deadline to now + 8 s.
        for (var i = 1; i <= 5; i++) {
          async.elapse(const Duration(seconds: 6));
          deadline.reportProgress(i / 10);
        }
        expect(error, isNull, reason: '30 s in, past the 10 s budget');
        // The same fraction again is no progress.
        async.elapse(const Duration(seconds: 6));
        deadline.reportProgress(0.5);
        async.elapse(const Duration(seconds: 3));
        expect(error, isA<TimeoutException>());
        expect(text, isNull);
      });
    });

    test('progress never extends past the hard cap', () {
      fakeAsync((async) {
        final deadline = TranscriptionDeadline(
          initial: const Duration(seconds: 10),
          stallWindow: const Duration(seconds: 30),
          hardCap: const Duration(seconds: 20),
        );
        Object? error;
        deadline
            .guard(Completer<String>().future)
            .then<void>((_) {}, onError: (Object e) => error = e);
        async.elapse(const Duration(seconds: 5));
        deadline.reportProgress(0.1);
        expect(deadline.current, const Duration(seconds: 20));
        async.elapse(const Duration(seconds: 16));
        expect(error, isA<TimeoutException>());
      });
    });

    test('a finished decode completes with its text', () async {
      final deadline = TranscriptionDeadline(
        initial: const Duration(seconds: 10),
        stallWindow: Duration.zero,
        hardCap: const Duration(seconds: 10),
      );
      expect(await deadline.guard(Future.value('ok')), 'ok');
    });
  });
}
