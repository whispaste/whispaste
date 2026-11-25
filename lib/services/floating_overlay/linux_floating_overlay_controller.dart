import 'package:flutter/services.dart';

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
    implements
        FloatingOverlayController,
        RenderEngineRecovery,
        OverlayCaptureExclusion {
  static const _channelName = 'com.whispaste.floating_overlay';

  LinuxFloatingOverlayController() : super(_channelName);

  /// Whether the overlay can take the keyboard focus for the write
  /// preview's edit field and give it back confirmed (#254): plain X11 with
  /// a WM that manages the overlay and publishes `_NET_ACTIVE_WINDOW`.
  /// Answered for the session, before any overlay exists; false on Wayland.
  static Future<bool> editFocusSupport() async =>
      await const MethodChannel(
        _channelName,
      ).invokeMethod<bool>('editFocusSupport') ??
      false;

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
  Future<void> setContextMenuItems(
    List<Map<String, Object?>> items, {
    String appearance = 'system',
  }) => invokeMethod('setContextMenuItems', {
    'items': items,
    'appearance': appearance,
  });

  /// Asks the native shell to re-boot the render engine (frame heartbeat,
  /// see [FloatingOverlayService]).
  @override
  Future<void> rebootRenderEngine() => invokeMethod('rebootRenderEngine');

  /// "In Bildschirmfreigaben und Screenshots verbergen" (overlay F).
  @override
  Future<void> setCaptureExcluded(bool excluded) =>
      invokeMethod('setCaptureExcluded', {'excluded': excluded});
}
