/// Lifecycle tests for [SmartModeFfiEngine]'s worker isolate (ticket 04 of
/// `.scratch/handy-catchup/`): load / reuse / idle-unload / abort, driven by
/// a fake [SmartModeNative] instead of the real `libsmartmode_shim`, so they
/// run on every host (no native library or 2.9 GB GGUF required).
///
/// The fake runs inside the worker isolate exactly where the real FFI calls
/// would — its blocking `sleep`s stand in for llama.cpp's synchronous model
/// load and decode loop.
library;

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart';

/// Simulated cold model load — long enough that a reload is clearly
/// distinguishable from a warm reuse in latency assertions.
const _fakeLoadTime = Duration(milliseconds: 300);

/// Fake native surface. Lives in the worker isolate, so its state is never
/// visible to the test directly — the engine's worker-reported stats are.
class _FakeNative implements SmartModeNative {
  bool _loaded = false;

  @override
  void load({required String modelPath}) {
    if (modelPath.endsWith('broken.gguf')) {
      throw StateError('smart_mode_load_failed');
    }
    sleep(_fakeLoadTime);
    _loaded = true;
  }

  @override
  String generate({
    required String systemPrompt,
    required String userText,
    required ffi.Pointer<ffi.Int32> abortFlag,
  }) {
    if (!_loaded) throw StateError('fake: generate before load');
    if (userText.startsWith('block:')) {
      // Blocking, like a real decode loop, for the given milliseconds.
      sleep(Duration(milliseconds: int.parse(userText.substring(6))));
      return 'done';
    }
    if (userText == 'hang') {
      // Never finishes on its own — only the abort flag gets it out, just
      // like the shim's per-token abort check.
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        if (abortFlag.value != 0) throw StateError('smart_mode_run_failed');
        sleep(const Duration(milliseconds: 5));
      }
      return 'never aborted';
    }
    return '[$systemPrompt] $userText';
  }

  @override
  void unload() {
    _loaded = false;
  }
}

SmartModeNative _fakeNativeFactory() => _FakeNative();

void main() {
  late Directory tmp;
  late String modelPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('smart_mode_lifecycle_');
    modelPath = p.join(tmp.path, 'model.gguf');
    File(modelPath).writeAsStringSync('fake gguf');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  SmartModeFfiEngine buildEngine({
    Duration idleTimeout = const Duration(minutes: 5),
    int? ramMB = 32768,
    String? overrideModelPath,
  }) {
    final engine = SmartModeFfiEngine(
      libraryPath: 'unused-by-fake',
      modelPath: overrideModelPath ?? modelPath,
      nativeFactory: _fakeNativeFactory,
      idleTimeout: () => idleTimeout,
      detectRamMB: () async => ramMB,
    );
    addTearDown(engine.shutdown);
    return engine;
  }

  group('SmartModeFfiEngine lifecycle (fake native, worker isolate)', () {
    test('first run loads the model once and returns the result', () async {
      final engine = buildEngine();
      expect(engine.isModelResident, isFalse);

      final out = await engine.run(systemPrompt: 'sys', userText: 'hello');

      expect(out, '[sys] hello');
      expect(engine.modelLoadCount, 1);
      expect(engine.isModelResident, isTrue);
      expect(engine.lastRunStats!.loadedModel, isTrue);
    });

    test('a second run within the idle window reuses the loaded model and '
        'is clearly faster than the first', () async {
      final engine = buildEngine();

      final first = Stopwatch()..start();
      await engine.run(systemPrompt: 's', userText: 'one');
      first.stop();
      final second = Stopwatch()..start();
      final out = await engine.run(systemPrompt: 's', userText: 'two');
      second.stop();

      expect(out, '[s] two');
      expect(engine.modelLoadCount, 1, reason: 'no reload on the 2nd call');
      expect(engine.lastRunStats!.loadedModel, isFalse);
      expect(
        second.elapsed,
        lessThan(first.elapsed - _fakeLoadTime ~/ 2),
        reason: '2nd call must skip the (simulated) cold model load',
      );
    });

    test(
      'idle timeout unloads the model; the next run loads it again',
      () async {
        final engine = buildEngine(
          idleTimeout: const Duration(milliseconds: 100),
        );

        await engine.run(systemPrompt: 's', userText: 'one');
        expect(engine.isModelResident, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(engine.isModelResident, isFalse, reason: 'idle unload ran');

        await engine.run(systemPrompt: 's', userText: 'two');
        expect(engine.modelLoadCount, 2);
        expect(engine.lastRunStats!.loadedModel, isTrue);
      },
    );

    test('a zero idle timeout keeps the model resident (matches the STT '
        '"never unload" semantics of idleTimeoutMinutes <= 0)', () async {
      final engine = buildEngine(idleTimeout: Duration.zero);
      await engine.run(systemPrompt: 's', userText: 'one');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.isModelResident, isTrue);
    });

    test('cancel() really aborts an in-flight generation; the model stays '
        'resident for the next call', () async {
      final engine = buildEngine();
      await engine.run(systemPrompt: 's', userText: 'warm-up');

      final sw = Stopwatch()..start();
      final pending = engine.run(systemPrompt: 's', userText: 'hang');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.cancel();

      await expectLater(pending, throwsA(isA<SmartModeAbortedException>()));
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));

      final out = await engine.run(systemPrompt: 's', userText: 'after');
      expect(out, '[s] after');
      expect(engine.modelLoadCount, 1, reason: 'abort must not unload');
    });

    test('cancel() issued synchronously right after run() still aborts it '
        '(the run is registered before its first await)', () async {
      final engine = buildEngine();
      await engine.run(systemPrompt: 's', userText: 'warm-up');

      final pending = engine.run(systemPrompt: 's', userText: 'hang');
      await engine.cancel();

      await expectLater(pending, throwsA(isA<SmartModeAbortedException>()));
    });

    test('cancel() with nothing in flight is a no-op', () async {
      final engine = buildEngine();
      await engine.cancel();
      expect(await engine.run(systemPrompt: 's', userText: 'x'), '[s] x');
    });

    test('low-RAM systems (memory pressure) unload Smart Mode right after '
        'each run so the Whisper model keeps priority', () async {
      final engine = buildEngine(ramMB: 8192);

      await engine.run(systemPrompt: 's', userText: 'one');
      expect(engine.isModelResident, isFalse);
      await engine.run(systemPrompt: 's', userText: 'two');
      expect(engine.modelLoadCount, 2);
    });

    test('explicit unload() frees the model', () async {
      final engine = buildEngine();
      await engine.run(systemPrompt: 's', userText: 'one');
      await engine.unload();
      expect(engine.isModelResident, isFalse);
    });

    test('a native load failure surfaces as StateError and nothing stays '
        'resident', () async {
      final broken = p.join(tmp.path, 'broken.gguf');
      File(broken).writeAsStringSync('x');
      final engine = buildEngine(overrideModelPath: broken);

      await expectLater(
        engine.run(systemPrompt: 's', userText: 'x'),
        throwsA(isA<StateError>()),
      );
      expect(engine.isModelResident, isFalse);
    });

    test('a missing model file fails fast without spawning work', () async {
      final engine = buildEngine(
        overrideModelPath: p.join(tmp.path, 'missing.gguf'),
      );
      await expectLater(
        engine.run(systemPrompt: 's', userText: 'x'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('smart_mode_model_not_found'),
          ),
        ),
      );
    });

    test('blocking native work runs off the calling isolate — its event '
        'loop never stalls > 100 ms (UI-smoothness proxy)', () async {
      final engine = buildEngine();
      await engine.run(systemPrompt: 's', userText: 'warm-up');

      var maxGap = Duration.zero;
      var last = DateTime.now();
      final ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
        final now = DateTime.now();
        final gap = now.difference(last);
        if (gap > maxGap) maxGap = gap;
        last = now;
      });
      await engine.run(systemPrompt: 's', userText: 'block:600');
      ticker.cancel();

      expect(maxGap, lessThan(const Duration(milliseconds: 100)));
    });
  });

  group('smartModeKeepsModelResident', () {
    test('keeps the model resident on >= 12 GB and when RAM is unknown', () {
      expect(smartModeKeepsModelResident(null), isTrue);
      expect(smartModeKeepsModelResident(16384), isTrue);
      expect(smartModeKeepsModelResident(12288), isTrue);
    });

    test('unloads after each run on the 8 GB class', () {
      expect(smartModeKeepsModelResident(8192), isFalse);
      expect(smartModeKeepsModelResident(7600), isFalse);
    });
  });
}
