import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:whispaste/services/audio_service.dart';

void main() {
  group('AudioServiceNotifier.cleanupStaleFiles', () {
    late Directory dir;
    final launchedAt = DateTime(2026, 10, 18, 12);

    setUp(() => dir = Directory.systemTemp.createTempSync('wp_stale_wav_'));
    tearDown(() => dir.deleteSync(recursive: true));

    File wav(String name, DateTime modified) => File(p.join(dir.path, name))
      ..writeAsBytesSync([0])
      ..setLastModifiedSync(modified);

    test('a crash WAV younger than maxAge at launch goes on the second '
        'sweep', () async {
      // Crashed one minute before the restart: too young for the first sweep.
      final crashed = wav(
        'whispaste_1.wav',
        launchedAt.subtract(const Duration(minutes: 1)),
      );

      await AudioServiceNotifier.cleanupStaleFiles(
        directory: dir,
        now: () => launchedAt,
      );
      expect(crashed.existsSync(), isTrue);

      await AudioServiceNotifier.cleanupStaleFiles(
        directory: dir,
        modifiedBefore: launchedAt,
        now: () => launchedAt.add(const Duration(minutes: 6)),
      );
      expect(crashed.existsSync(), isFalse);
    });

    test('never touches a WAV of this session, even one older than '
        'maxAge', () async {
      // A dictation recorded right after launch whose transcription is still
      // running when the second sweep comes.
      final current = wav(
        'whispaste_2.wav',
        launchedAt.add(const Duration(seconds: 30)),
      );

      await AudioServiceNotifier.cleanupStaleFiles(
        directory: dir,
        modifiedBefore: launchedAt,
        now: () => launchedAt.add(const Duration(minutes: 30)),
      );
      expect(current.existsSync(), isTrue);
    });

    test('leaves files that are not WhisPaste temp WAVs alone', () async {
      final old = launchedAt.subtract(const Duration(days: 1));
      final others = [
        wav('other_1.wav', old),
        wav('whispaste_1.wav.bak', old),
        wav('whispaste_model.bin', old),
      ];

      await AudioServiceNotifier.cleanupStaleFiles(
        directory: dir,
        modifiedBefore: launchedAt,
        now: () => launchedAt,
      );
      for (final f in others) {
        expect(f.existsSync(), isTrue, reason: f.path);
      }
    });
  });

  group('AudioServiceNotifier.scheduleStaleFileCleanup', () {
    test('sweeps at launch and once more after maxAge, both limited to files '
        'from before the launch', () {
      fakeAsync((async) {
        final launchedAt = DateTime(2026, 10, 18, 12);
        final calls = <DateTime?>[];

        AudioServiceNotifier.scheduleStaleFileCleanup(
          launchedAt: launchedAt,
          maxAge: const Duration(minutes: 5),
          sweep: ({DateTime? modifiedBefore}) async =>
              calls.add(modifiedBefore),
          legacySweep: ({required DateTime modifiedBefore}) async {},
        );
        async.flushMicrotasks();
        expect(calls, hasLength(1));

        async.elapse(const Duration(minutes: 5));
        expect(calls, hasLength(1));

        async.elapse(const Duration(minutes: 1));
        expect(calls, hasLength(2));
        expect(calls.every((c) => c != null && !c.isAfter(launchedAt)), isTrue);

        async.elapse(const Duration(hours: 1));
        expect(calls, hasLength(2));
      });
    });

    test('runs the legacy temp sweep once at launch, cut off at launch', () {
      fakeAsync((async) {
        final launchedAt = DateTime(2026, 10, 19, 9);
        final legacyCutoffs = <DateTime>[];

        AudioServiceNotifier.scheduleStaleFileCleanup(
          launchedAt: launchedAt,
          sweep: ({DateTime? modifiedBefore}) async {},
          legacySweep: ({required DateTime modifiedBefore}) async =>
              legacyCutoffs.add(modifiedBefore),
        );
        async.flushMicrotasks();

        expect(legacyCutoffs, hasLength(1));
        expect(legacyCutoffs.single.isAfter(launchedAt), isFalse);
      });
    });
  });
}
