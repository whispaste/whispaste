import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import '../../shared_render_engine_helpers.dart' show RenderChannel;
import 'floating_button_controller_interface.dart';

final _log = AppLogger('FloatingButtonRenderChannel');

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
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Called when the native shell relays a new visual state.
  final void Function(FloatingButtonVisualState state) onState;

  /// Called when the native shell relays a new disc diameter in logical pixels.
  final void Function(double diameter) onDiameter;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'setState':
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
        final args = call.arguments;
        if (args is Map) {
          final raw = args['diameter'] ?? args['size'];
          if (raw is num) onDiameter(raw.toDouble());
        }
        return null;
      case 'setSize':
        // Alias: host may send setSize{size} instead of setDiameter.
        final args = call.arguments;
        if (args is Map) {
          final raw = args['size'] ?? args['diameter'];
          if (raw is num) onDiameter(raw.toDouble());
        }
        return null;
      case 'setTheme':
        // The V2 disc is theme-independent (white disc, dark mic on white
        // background): accept and ignore so the host can relay setTheme without
        // breaking the protocol — a future redesign can wire this up.
        return null;
      default:
        return null;
    }
  }

  /// Asks the native shell to start an OS window drag (macOS `performDrag`).
  void startDrag() {
    _channel.invokeMethod('startDrag');
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

  /// Tells the native shell the inbound handler is registered, so it can flush
  /// the render state cached during the engine boot race. Must be called only
  /// after the handler is set (i.e. after construction).
  @override
  void notifyReady() {
    _channel.invokeMethod('ready');
  }

  /// Detaches the handler. The engine outlives individual app widgets, so this
  /// is mainly for tests and hot-restart hygiene.
  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
