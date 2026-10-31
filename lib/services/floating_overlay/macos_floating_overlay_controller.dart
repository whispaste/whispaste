import '../method_channel_platform_host.dart';
import 'floating_overlay_controller_interface.dart';
import 'floating_overlay_controller_mixin.dart';
import 'floating_overlay_events.dart';
import 'overlay_waveform_payload.dart';

/// macOS implementation of [FloatingOverlayController].
///
/// Communicates with the Swift FloatingOverlayHost via a single MethodChannel.
/// Events are received through the same channel (Swift calls invokeMethod).
///
/// Platform plumbing (disposed guard, stream controller, channel lifecycle)
/// is inherited from [MethodChannelPlatformHost].
class MacOSFloatingOverlayController
    extends MethodChannelPlatformHost<FloatingOverlayEvent>
    with FloatingOverlayControllerMixin
    implements FloatingOverlayController, RenderEngineRecovery {
  static const _channelName = 'com.whispaste.floating_overlay';

  MacOSFloatingOverlayController() : super(_channelName);

  final WaveformSendGate _waveformGate = WaveformSendGate();

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) =>
      invokeMethod('updateSnapshot', snapshot.toMap());

  /// Sends one byte per bar (see [encodeWaveformBars]) and skips a payload
  /// identical to the last one sent.
  @override
  Future<void> setWaveformBars(List<double> bars) {
    final payload = encodeWaveformBars(bars);
    if (!_waveformGate.accept(payload)) return Future<void>.value();
    return invokeMethod('setWaveformBars', {'bars': payload});
  }

  @override
  Future<void> rebootRenderEngine() => invokeMethod('rebootRenderEngine');

  @override
  Future<void> setPosition(double x, double y, OverlayAnchorMode anchor) =>
      invokeMethod('setPosition', {'x': x, 'y': y, 'anchorMode': anchor.name});

  @override
  Future<void> setContextMenuItems(List<({String id, String label})> items) =>
      invokeMethod('setContextMenuItems', {
        'items': items
            .map((item) => {'id': item.id, 'label': item.label})
            .toList(),
      });
}
