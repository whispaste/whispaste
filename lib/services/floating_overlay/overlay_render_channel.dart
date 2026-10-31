import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../shared_render_engine_helpers.dart' show RenderChannel;
import 'floating_overlay_controller_interface.dart';
import 'overlay_waveform_payload.dart';

/// Acknowledges the first painted frame after each hidden→visible show.
///
/// The acknowledgement is scheduled as a framework post-frame callback, so it
/// fires after the frame that presents the show has been built. It is sent once
/// per show: further visible snapshots within the same show do not re-ack, and
/// a hide before the frame cancels it.
class OverlayFrameHeartbeat {
  OverlayFrameHeartbeat({required this.onFrame});

  /// Called once per show, after its first painted frame.
  final void Function() onFrame;

  bool _visible = false;
  bool _pending = false;
  bool _callbackScheduled = false;

  /// Feed every snapshot the render engine receives.
  void onSnapshot({required bool visible}) {
    if (visible && !_visible) _pending = true;
    if (!visible) _pending = false;
    _visible = visible;
    if (_pending && !_callbackScheduled) {
      _callbackScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback(_ack);
      // Do not rely on the caller to schedule the frame that runs the callback.
      SchedulerBinding.instance.scheduleFrame();
    }
  }

  void _ack(Duration _) {
    _callbackScheduled = false;
    if (!_pending || !_visible) return;
    _pending = false;
    onFrame();
  }
}

/// The render-engine side of the overlay shell seam (ADR 0002 phase 2).
///
/// Lives inside the dedicated overlay Flutter engine. It receives the relayed
/// render state from the native shell (`updateSnapshot` / `setWaveformBars`)
/// and relays the three coarse interactions back
/// (`startDrag` / `bodyClicked` / `showContextMenu`). It owns no window or
/// rendering state itself — the host widget keeps that and rebuilds on each
/// callback.
///
/// Kept separate from the entrypoint so the wiring is unit-testable without
/// booting a second engine.
class OverlayRenderChannel implements RenderChannel {
  /// Binds the handler on [name] and remembers the interaction sink.
  ///
  /// [clock] overrides the time source used by the receive-telemetry throttle.
  /// Leave null in production (defaults to [DateTime.now]); inject a fake clock
  /// in unit tests to exercise the throttle boundary without real time delays.
  OverlayRenderChannel({
    required String name,
    required this.onSnapshot,
    required this.onWaveformBars,
    MethodChannel? channel,
    DateTime Function()? clock,
  }) : _channel = channel ?? MethodChannel(name),
       _clock = clock ?? _wallClock {
    _channel.setMethodCallHandler(_handle);
  }

  static DateTime _wallClock() => DateTime.now();

  final MethodChannel _channel;
  final DateTime Function() _clock;

  // Throttle: emit at most one log per [_kLogThrottle] for high-frequency
  // events so the ~30Hz waveform path is not flooded.
  static const Duration _kLogThrottle = Duration(seconds: 1);
  DateTime? _lastSnapshotLog;
  DateTime? _lastWaveformLog;

  /// Called with a fully-resolved snapshot relayed from the main engine.
  final void Function(FloatingOverlaySnapshot snapshot) onSnapshot;

  /// Called with the latest pre-computed waveform bar array.
  final void Function(List<double> bars) onWaveformBars;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'updateSnapshot':
        final args = call.arguments;
        if (args is Map) {
          final snapshot = FloatingOverlaySnapshot.fromMap(args);
          final now = _clock();
          if (_lastSnapshotLog == null ||
              now.difference(_lastSnapshotLog!) >= _kLogThrottle) {
            _lastSnapshotLog = now;
            debugPrint(
              '[overlay-engine] onSnapshot: '
              'visible=${snapshot.visible} state=${snapshot.state.name}',
            );
          }
          onSnapshot(snapshot);
        }
        return null;
      case 'setWaveformBars':
        final args = call.arguments;
        final raw = args is Map ? args['bars'] : null;
        if (raw is List || raw is Uint8List) {
          final bars = decodeWaveformBars(raw);
          final now = _clock();
          if (_lastWaveformLog == null ||
              now.difference(_lastWaveformLog!) >= _kLogThrottle) {
            _lastWaveformLog = now;
            debugPrint('[overlay-engine] onWaveformBars: ${bars.length} bars');
          }
          onWaveformBars(bars);
        }
        return null;
      default:
        return null;
    }
  }

  /// Asks the native shell to start an OS window drag (macOS `performDrag`).
  void startDrag() {
    _channel.invokeMethod('startDrag');
  }

  /// Reports a tap on the pill body (toggles recording on the main engine).
  void bodyClicked() {
    _channel.invokeMethod('bodyClicked');
  }

  /// Asks the native shell to show its context menu at the cursor.
  void showContextMenu() {
    _channel.invokeMethod('showContextMenu');
  }

  /// Acknowledges that this engine painted a frame for the current show (see
  /// [OverlayFrameHeartbeat]). The shell relays it to the main engine, which
  /// stops the re-boot deadline. Only macOS consumes it; Windows answers
  /// NotImplemented, so the failure is swallowed here instead of escaping.
  void frameRendered() {
    _channel.invokeMethod('frameRendered').catchError((Object error) {
      debugPrint('[overlay-engine] frameRendered not handled: $error');
      return null;
    });
  }

  /// Tells the native shell the inbound handler is registered, so it can flush
  /// the render state cached during the engine boot race. Must be called only
  /// after the handler is set (i.e. after construction).
  @override
  void notifyReady() {
    debugPrint(
      '[overlay-engine] notifyReady → channel ready, flushing pending state',
    );
    _channel.invokeMethod('ready');
  }

  /// Reports an uncaught Dart error in this engine back to the native shell
  /// (see [RenderChannel.reportError]). Fire-and-forget: platforms without a
  /// `reportError` handler simply ignore the call.
  @override
  void reportError(String message) {
    debugPrint('[overlay-engine-ERROR] $message');
    _channel.invokeMethod('reportError', {'message': message});
  }

  /// Detaches the handler. The engine outlives individual app widgets, so this
  /// is mainly for tests and hot-restart hygiene.
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
