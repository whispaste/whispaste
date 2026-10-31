/// Regression test for the live "the recording overlay simply doesn't show
/// up" bug (diagnosed 2026-09-01 from a full debug run of six consecutive
/// dictations).
///
/// Root cause: the floating-overlay render engine still adopted the macOS
/// embedder's app-global lifecycle. That engine boots lazily on the FIRST
/// recording, long after launch, and the embedder never replays the current
/// activation/occlusion state to a late registrant — so it carried a stale
/// `_visible = NO`, and the next `applicationWillResignActive` (the user
/// clicking back into the app they dictate into) mapped straight onto
/// `AppLifecycleState.hidden`. `SchedulerBinding` answers that with
/// `framesEnabled = false`, after which the engine never produces another
/// frame: the native panel is ordered front over the fully transparent
/// surface its previous hide snapshot left behind, and the appear animation
/// that would fade the capsule back in can no longer advance. Log signature
/// of the failing run: `[overlay] panel operation 'orderFront' ...
/// panel.isVisible=true, frame=(941.0, 1056.0, 166.0, 50.0)` plus
/// `[overlay-engine] onSnapshot: visible=true state=recording` for every one
/// of the invisible recordings — shell healthy, relay healthy, no pixels.
///
/// Seam honesty: the full bug needs a real secondary `FlutterEngine` inside
/// an `NSPanel`, which no Dart test can boot. What CAN be locked down is the
/// exact mechanism link, at the real channel seam the embedder uses: after
/// this engine's own boot path ran, an incoming `flutter/lifecycle` platform
/// message must no longer reach its `SchedulerBinding.lifecycleState`.
/// `framesEnabled` itself is deliberately not asserted — it is the
/// framework's own downstream of `lifecycleState`, and the automated test
/// binding pins it independently of lifecycle (it pumps frames itself rather
/// than via engine scheduling).
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/floating_overlay_render_entrypoint.dart';

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

  test(
    'booting the overlay engine detaches it from embedder lifecycle',
    () async {
      // Sanity first, in the same test (detaching is process-global and
      // irreversible): prove the seam drives the real channel path, or the
      // post-boot assertion below would pass vacuously.
      await pushLifecycleMessage('AppLifecycleState.inactive');
      expect(binding.lifecycleState, AppLifecycleState.inactive);

      bootstrapFloatingOverlayEngine();

      await pushLifecycleMessage('AppLifecycleState.hidden');

      expect(
        binding.lifecycleState,
        AppLifecycleState.inactive,
        reason:
            'the overlay render engine must not adopt the embedder\'s bogus '
            'app-global lifecycle (its visibility is governed by the native '
            'shell\'s relayed snapshot alone) — AppLifecycleState.hidden sets '
            'framesEnabled = false, and a frame-starved engine paints nothing '
            'while the shell happily orders the panel front, which is the live '
            'bug',
      );
    },
  );
}
