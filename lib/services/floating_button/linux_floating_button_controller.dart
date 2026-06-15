import '../method_channel_platform_host.dart';
import 'floating_button_controller_interface.dart';
import 'floating_button_controller_mixin.dart';
import 'floating_button_events.dart';

/// Linux implementation of [FloatingButtonController].
///
/// Communicates with the C++ FloatingButtonHost via a single MethodChannel.
/// Events are received through the same channel (C++ calls InvokeMethod).
///
/// Platform plumbing (disposed guard, stream controller, channel lifecycle)
/// is inherited from [MethodChannelPlatformHost].
///
/// The native side (linux/runner/floating_button_host.cc) mirrors the
/// Windows host: same method names, same argument shapes, same event names.
class LinuxFloatingButtonController
    extends MethodChannelPlatformHost<FloatingButtonEvent>
    with FloatingButtonControllerMixin
    implements FloatingButtonController {
  static const _channelName = 'com.whispaste.floating_button';

  LinuxFloatingButtonController() : super(_channelName);

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
  Future<void> setContextMenuItems(List<Map<String, String>> items) =>
      invokeMethod('setContextMenuItems', {'items': items});
}
