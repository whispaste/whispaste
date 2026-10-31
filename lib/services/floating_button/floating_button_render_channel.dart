import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../core/theme/overlay_customization.dart';
import '../../core/theme/overlay_design_spec.dart';
import '../../shared_render_engine_helpers.dart' show RenderChannel;
import 'floating_button_controller_interface.dart';
import 'idle_capsule.dart';

final _log = AppLogger('FloatingButtonRenderChannel');

/// Acknowledges the painted frame after a state message from the native shell.
///
/// The acknowledgement is a framework post-frame callback, so it fires only
/// once the engine has actually built and painted the frame that presents the
/// message. A stalled engine therefore never acknowledges, and the shell's
/// stall deadline runs out. Several messages in one frame share one ack.
class FloatingButtonFrameAck {
  FloatingButtonFrameAck({required this.onFrame});

  /// Called once after the frame that presents the pending message(s).
  final void Function() onFrame;

  bool _scheduled = false;

  /// Requests an acknowledgement for the frame that presents the message.
  void request() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback(_ack);
    // Do not rely on the caller to schedule the frame that runs the callback.
    SchedulerBinding.instance.scheduleFrame();
  }

  void _ack(Duration _) {
    _scheduled = false;
    onFrame();
  }
}

/// The render-engine side of the button shell seam (ADR 0002 phase 2).
///
/// Lives inside the dedicated button Flutter engine. It receives the relayed
/// render state from the native shell (`setState` / `setDiameter`) and relays
/// the three coarse interactions back (`clicked` / `startDrag` /
/// `showContextMenu`). It owns no window or rendering state itself — the host
/// widget keeps that and rebuilds on each callback.
///
/// Kept separate from the entrypoint so the wiring is unit-testable without
/// booting a second engine.
class FloatingButtonRenderChannel implements RenderChannel {
  /// Binds the handler on [name] and remembers the interaction sink.
  FloatingButtonRenderChannel({
    required String name,
    required this.onState,
    required this.onDiameter,
    this.onTheme,
    this.onLook,
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  late final FloatingButtonFrameAck _frameAck = FloatingButtonFrameAck(
    onFrame: frameRendered,
  );

  /// Called when the native shell relays a new visual state.
  final void Function(FloatingButtonVisualState state) onState;

  /// Called when the native shell relays a new disc diameter in logical pixels.
  final void Function(double diameter) onDiameter;

  /// Called when the host relays the overlay presets (ticket, ADR 0024): the
  /// background the disc is drawn on and the wave colour of its recording
  /// ring. Absent or unknown names keep the defaults.
  final void Function(OverlayBackground background, OverlayWave wave)? onTheme;

  /// Called with the shape, recording ring and resting opacity (ticket) that
  /// arrive in the same `setTheme` payload.
  final void Function(FloatingButtonLook look)? onLook;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'setState':
        _frameAck.request();
        final args = call.arguments;
        if (args is Map) {
          final raw = args['state'];
          if (raw is String) {
            try {
              onState(FloatingButtonVisualState.values.byName(raw));
            } catch (e) {
              // Unknown state name — ignore gracefully so a future state added
              // on the host side does not crash an older render engine.
              _log.debug(
                'Unknown FloatingButtonVisualState "$raw" — ignored',
                e,
              );
            }
          }
        }
        return null;
      case 'setDiameter':
        _frameAck.request();
        final args = call.arguments;
        if (args is Map) {
          final raw = args['diameter'] ?? args['size'];
          if (raw is num) onDiameter(raw.toDouble());
        }
        return null;
      case 'setSize':
        // Alias: host may send setSize{size} instead of setDiameter.
        _frameAck.request();
        final args = call.arguments;
        if (args is Map) {
          final raw = args['size'] ?? args['diameter'];
          if (raw is num) onDiameter(raw.toDouble());
        }
        return null;
      case 'setTheme':
        _frameAck.request();
        final args = call.arguments;
        if (args is Map) {
          final background = OverlayBackground.fromValue(
            args['background'] as String?,
          );
          final wave = OverlayWave.fromValue(args['wave'] as String?);
          onTheme?.call(background, wave);
          onLook?.call(FloatingButtonLook.fromThemeMap(args));
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

  /// Asks the native shell to resize its window to [contentSize] (logical
  /// pixels, without the shadow padding, which the shell adds). An [expanded]
  /// pill grows toward the screen interior; the shell returns the edges it
  /// pinned ([CapsulePins]), and a rest size returns to the capsule's home
  /// position with the default pins. Null when the shell reports none.
  Future<CapsulePins?> setWindowSize(
    Size contentSize, {
    required bool expanded,
  }) async {
    final result = await _channel
        .invokeMapMethod<String, Object?>('setWindowSize', {
          'width': contentSize.width,
          'height': contentSize.height,
          'expanded': expanded,
        });
    if (result == null) return null;
    return CapsulePins(
      pinnedRight: result['pinnedRight'] == true,
      pinnedBottom: result['pinnedBottom'] == true,
    );
  }

  /// Reports a tap on the button disc.
  void clicked() {
    _channel.invokeMethod('clicked');
  }

  /// Asks the native shell to show its context menu at the cursor (if items
  /// are set) or invoke `onSecondaryClicked` on the public channel (if empty).
  void showContextMenu() {
    _channel.invokeMethod('showContextMenu');
  }

  /// Acknowledges that this engine painted a frame for the latest state
  /// message (see [FloatingButtonFrameAck]). The shell relays it to the main
  /// engine, which stops its stall deadline. Windows answers NotImplemented
  /// until it has the same handler, so that failure is swallowed here.
  void frameRendered() {
    _channel.invokeMethod('frameRendered').catchError((Object error) {
      _log.debug('frameRendered not handled: $error');
      return null;
    });
  }

  /// Tells the native shell the inbound handler is registered, so it can flush
  /// the render state cached during the engine boot race. Must be called only
  /// after the handler is set (i.e. after construction).
  @override
  void notifyReady() {
    _channel.invokeMethod('ready');
  }

  /// Reports an uncaught Dart error in this engine back to the native shell
  /// (see [RenderChannel.reportError]). Fire-and-forget: platforms without a
  /// `reportError` handler simply ignore the call.
  @override
  void reportError(String message) {
    _log.error('[button-engine-ERROR] $message');
    _channel.invokeMethod('reportError', {'message': message});
  }

  /// Detaches the handler. The engine outlives individual app widgets, so this
  /// is mainly for tests and hot-restart hygiene.
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
