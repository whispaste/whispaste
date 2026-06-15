import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'floating_button_events.dart';

/// Shared [parseNativeEvent] and [getPosition] implementations for all
/// platform-specific [FloatingButtonController] classes.
///
/// All three platform controllers use the same channel protocol, so the
/// method bodies are identical. Extracting them here eliminates the duplication
/// while keeping three named classes for the platform factory.
mixin FloatingButtonControllerMixin
    on MethodChannelPlatformHost<FloatingButtonEvent> {
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

  Future<({double x, double y})?> getPosition() async {
    final result = await invokeMapMethod<String, dynamic>('getPosition');
    if (result == null) return null;
    final x = (result['x'] as num?)?.toDouble();
    final y = (result['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return (x: x, y: y);
  }
}
