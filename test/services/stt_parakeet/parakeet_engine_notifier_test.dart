/// Unit test for [ParakeetEngineNotifier.ensureRunning]'s concurrent-caller
/// coalescing (FLUTTER_WHISPASTE-B7/BH/B8 root cause).
///
/// Two concurrent `ensureRunning()` calls used to each create their own
/// `_initCompleter` and send their own `_InitRequest`, sharing one mutable
/// field — the first request's ack completed whichever completer the field
/// happened to point to by then (the *second* call's), leaving the first
/// call hanging until its own 60s timeout, and the second call's actual ack
/// later threw "Future already completed" on the already-completed
/// completer. This only checks the coalescing guard itself (both calls
/// must resolve to the exact same in-flight [Future]) rather than driving a
/// real sherpa_onnx init — the model files aren't a repo fixture
/// (multi-hundred-MB ONNX weights) and spawning the real isolate against
/// garbage paths would make this test's stability depend on how
/// sherpa_onnx's native binding fails, which is outside this seam's
/// control.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/stt_parakeet/parakeet_engine_notifier.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_model_registry.dart';

void main() {
  tearDown(() {
    parakeetFileExistsOverride = null;
  });

  test(
    'ensureRunning() called twice without awaiting coalesces onto one '
    'in-flight start instead of sending two _InitRequests',
    () async {
      // Model files "missing" is enough here: ensureRunning()'s coalescing
      // guard runs before the file-existence check, so both calls must
      // already share the same Future by the time either has had a chance
      // to run further — no isolate spawn or native call is reached.
      parakeetFileExistsOverride = (_) => false;

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(parakeetEngineProvider.notifier);

      final first = notifier.ensureRunning();
      final second = notifier.ensureRunning();

      expect(
        identical(first, second),
        isTrue,
        reason:
            'a second ensureRunning() call while one is already in flight '
            'must reuse the same Future — a distinct Future per call is '
            'exactly what let two _InitRequests race the shared '
            '_initCompleter field in production',
      );

      await expectLater(
        first,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'parakeet_model_not_found',
          ),
        ),
      );
    },
  );
}
