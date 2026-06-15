import 'package:flutter/services.dart';

import '../method_channel_platform_host.dart';
import 'floating_overlay_events.dart';

/// Shared [parseNativeEvent] implementation for all platform-specific
/// [FloatingOverlayController] classes.
///
/// All three platform controllers use the same channel protocol, so the
/// method body is identical. Extracting it here eliminates the duplication
/// while keeping three named classes for the platform factory.
mixin FloatingOverlayControllerMixin
    on MethodChannelPlatformHost<FloatingOverlayEvent> {
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
}
