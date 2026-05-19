import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'floating_overlay_controller.dart';
import 'floating_overlay_events.dart';

/// Windows implementation of [FloatingOverlayController].
///
/// Communicates with the C++ FloatingOverlayHost via a single MethodChannel.
/// Events are received through the same channel (C++ calls InvokeMethod).
///
/// Platform plumbing (disposed guard, stream controller, channel lifecycle)
/// is inherited from [MethodChannelPlatformHost].
class WindowsFloatingOverlayController
    extends MethodChannelPlatformHost<FloatingOverlayEvent>
    implements FloatingOverlayController {
  static const _channelName = 'com.whispaste.floating_overlay';

  WindowsFloatingOverlayController() : super(_channelName);

  @override
  FloatingOverlayEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onDragEnded':
        final args = call.arguments as Map?;
        if (args != null) {
          final x = (args['x'] as num?)?.toDouble() ?? 0;
          final y = (args['y'] as num?)?.toDouble() ?? 0;
          final anchorMode = (args['anchorMode'] as String?) ?? 'topLeft';
          return OverlayDragEnded(x, y, anchorMode);
        }
        return null;
      case 'onCloseClicked':
        return const OverlayCloseClicked();
      case 'onBodyClicked':
        return const OverlayBodyClicked();
      case 'onRetryClicked':
        return const OverlayRetryClicked();
      case 'onContextMenu':
        final args = call.arguments as Map?;
        final action = args?['action'] as String?;
        if (action != null) return OverlayContextMenuAction(action);
        return null;
      default:
        return null;
    }
  }

  @override
  Future<void> updateSnapshot(FloatingOverlaySnapshot snapshot) =>
      invokeMethod('updateSnapshot', snapshot.toMap());

  @override
  Future<void> setAudioLevel(double level) =>
      invokeMethod('setAudioLevel', {'level': level});

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

  @override
  Future<void> setOpacity(double opacity) =>
      invokeMethod('setOpacity', {'opacity': opacity});
}
