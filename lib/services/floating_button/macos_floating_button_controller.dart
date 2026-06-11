import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'floating_button_controller_interface.dart';
import 'floating_button_events.dart';

/// macOS implementation of [FloatingButtonController].
///
/// Communicates with the Swift FloatingButtonHost via a single MethodChannel.
/// Events are received through the same channel (Swift calls invokeMethod).
///
/// Platform plumbing (disposed guard, stream controller, channel lifecycle)
/// is inherited from [MethodChannelPlatformHost].
class MacOSFloatingButtonController
    extends MethodChannelPlatformHost<FloatingButtonEvent>
    implements FloatingButtonController {
  static const _channelName = 'com.whispaste.floating_button';

  MacOSFloatingButtonController() : super(_channelName);

  @override
  FloatingButtonEvent? parseNativeEvent(MethodCall call) {
    switch (call.method) {
      case 'onClicked':
        return const FloatingButtonClicked();
      case 'onSecondaryClicked':
        return const FloatingButtonSecondaryClicked();
      case 'onContextMenu':
        final args = call.arguments as Map?;
        final id = args?['id'] as String?;
        if (id != null) return FloatingButtonContextMenuSelected(id);
        return null;
      case 'onDragEnded':
        final args = call.arguments as Map?;
        if (args != null) {
          final x = (args['x'] as num?)?.toDouble() ?? 0;
          final y = (args['y'] as num?)?.toDouble() ?? 0;
          return FloatingButtonDragEnded(x, y);
        }
        return null;
      default:
        return null;
    }
  }

  @override
  Future<void> show({double x = 200, double y = 200, int size = 56}) =>
      invokeMethod('show', {'x': x, 'y': y, 'size': size});

  @override
  Future<void> hide() => invokeMethod('hide');

  @override
  Future<void> setState(FloatingButtonVisualState state) =>
      invokeMethod('setState', {'state': state.name});

  @override
  Future<void> setTheme({required bool isDark}) =>
      invokeMethod('setTheme', {'isDark': isDark});

  @override
  Future<void> setPosition(double x, double y) =>
      invokeMethod('setPosition', {'x': x, 'y': y});

  @override
  Future<void> setSize(int size) => invokeMethod('setSize', {'size': size});

  @override
  Future<void> setOpacity(double opacity) =>
      invokeMethod('setOpacity', {'opacity': opacity});

  @override
  Future<void> setContextMenuItems(List<Map<String, String>> items) =>
      invokeMethod('setContextMenuItems', {'items': items});

  @override
  Future<({double x, double y})?> getPosition() async {
    final result = await invokeMapMethod<String, dynamic>('getPosition');
    if (result == null) return null;
    final x = (result['x'] as num?)?.toDouble();
    final y = (result['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }
}
