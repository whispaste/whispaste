import 'package:flutter/services.dart';

import 'floating_overlay_controller_interface.dart';

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
class OverlayRenderChannel {
  /// Binds the handler on [name] and remembers the interaction sink.
  OverlayRenderChannel({
    required String name,
    required this.onSnapshot,
    required this.onWaveformBars,
    MethodChannel? channel,
  }) : _channel = channel ?? MethodChannel(name) {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;

  /// Called with a fully-resolved snapshot relayed from the main engine.
  final void Function(FloatingOverlaySnapshot snapshot) onSnapshot;

  /// Called with the latest pre-computed waveform bar array.
  final void Function(List<double> bars) onWaveformBars;

  Future<dynamic> _handle(MethodCall call) async {
    switch (call.method) {
      case 'updateSnapshot':
        final args = call.arguments;
        if (args is Map) {
          onSnapshot(FloatingOverlaySnapshot.fromMap(args));
        }
        return null;
      case 'setWaveformBars':
        final args = call.arguments;
        final raw = args is Map ? args['bars'] : null;
        if (raw is List) {
          onWaveformBars(
            raw.map((e) => (e as num?)?.toDouble() ?? 0.0).toList(),
          );
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

  /// Tells the native shell the inbound handler is registered, so it can flush
  /// the render state cached during the engine boot race. Must be called only
  /// after the handler is set (i.e. after construction).
  void notifyReady() {
    _channel.invokeMethod('ready');
  }

  /// Detaches the handler. The engine outlives individual app widgets, so this
  /// is mainly for tests and hot-restart hygiene.
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
