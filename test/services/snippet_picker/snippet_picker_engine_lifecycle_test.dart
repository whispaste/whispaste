/// Regression test for the live "arrow keys don't visibly navigate the
/// picker" bug (diagnosed live 2026-08-13; the tagged-instrumentation log
/// evidence is preserved in the fix commit's message).
///
/// Root cause: the snippet-picker render engine received a bogus
/// `AppLifecycleState.hidden` from the macOS embedder (stale per-engine
/// activation/occlusion flags — see `detachFromEmbedderAppLifecycle`'s doc),
/// which made `SchedulerBinding` disable frame scheduling
/// (`framesEnabled = false`). Every arrow-key `setState` then updated state
/// without ever painting: the panel stayed frozen on the single
/// per-`show()` frame the native `contentViewController` reattach forces.
///
/// Seam honesty: the full bug needs a real secondary `FlutterEngine` inside
/// an `NSPanel`, which no Dart test can boot. What CAN be locked down at a
/// correct seam is the exact mechanism link: an incoming
/// `flutter/lifecycle` platform message must no longer reach this engine's
/// `SchedulerBinding.lifecycleState` once [detachFromEmbedderAppLifecycle]
/// ran. The test drives the real channel path (`channelBuffers.push`, the
/// same route the embedder uses), not internal APIs. `framesEnabled` itself
/// is deliberately not asserted: it is the framework's own downstream of
/// `lifecycleState`, and the automated test binding pins it independently
/// of lifecycle (it pumps frames itself rather than via engine scheduling).
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/shared_render_engine_helpers.dart';

/// Delivers [state] to the engine exactly like the embedder does: as a
/// platform message on `flutter/lifecycle`.
Future<void> pushLifecycleMessage(String state) {
  final completer = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    'flutter/lifecycle',
    const StringCodec().encodeMessage(state),
    (_) => completer.complete(),
  );
  return completer.future;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('detached engine ignores embedder lifecycle messages', () async {
    // Sanity first, in the same test (detaching is process-global and
    // irreversible): prove the seam drives the real channel path, or the
    // post-detach assertion below would pass vacuously.
    await pushLifecycleMessage('AppLifecycleState.inactive');
    expect(binding.lifecycleState, AppLifecycleState.inactive);

    detachFromEmbedderAppLifecycle();

    await pushLifecycleMessage('AppLifecycleState.hidden');

    expect(
      binding.lifecycleState,
      AppLifecycleState.inactive,
      reason:
          'the picker engine must not adopt the embedder\'s bogus '
          'app-global lifecycle (its visibility is governed by the native '
          'host\'s show()/dismiss() alone) — AppLifecycleState.hidden '
          'would disable frame scheduling and freeze the panel on its '
          'first frame, which is the live bug',
    );
  });
}
