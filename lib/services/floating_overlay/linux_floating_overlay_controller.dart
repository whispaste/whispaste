import '../method_channel_platform_host.dart';
import 'floating_overlay_controller_interface.dart';
import 'floating_overlay_controller_mixin.dart';
import 'floating_overlay_events.dart';

/// Linux implementation of [FloatingOverlayController].
///
/// Communicates with the C++ FloatingOverlayHost via a single MethodChannel.
/// Events are received through the same channel (C++ calls InvokeMethod).
///
/// Platform plumbing (disposed guard, stream controller, channel lifecycle)
/// is inherited from [MethodChannelPlatformHost].
///
/// The native side (linux/runner/floating_overlay_host.cc) mirrors the
/// Windows host: same method names, same argument shapes, same event names.
class LinuxFloatingOverlayController
    extends MethodChannelPlatformHost<FloatingOverlayEvent>
    with FloatingOverlayControllerMixin
    implements FloatingOverlayController {
  static const _channelName = 'com.whispaste.floating_overlay';

  LinuxFloatingOverlayController() : super(_channelName);

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) =>
      invokeMethod('updateSnapshot', snapshot.toMap());

  @override
  Future<void> setWaveformBars(List<double> bars) =>
      invokeMethod('setWaveformBars', {'bars': bars});

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
