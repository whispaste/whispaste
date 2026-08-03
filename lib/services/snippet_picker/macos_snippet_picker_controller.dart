import '../method_channel_platform_host.dart';
import 'snippet_picker_controller_interface.dart';
import 'snippet_picker_controller_mixin.dart';
import 'snippet_picker_events.dart';

/// macOS implementation of [SnippetPickerController].
///
/// Communicates with the Swift `SnippetPickerHost` via a single
/// MethodChannel; events are received through the same channel (Swift calls
/// `invokeMethod`). Platform plumbing (disposed guard, stream controller,
/// channel lifecycle) is inherited from [MethodChannelPlatformHost].
class MacOSSnippetPickerController
    extends MethodChannelPlatformHost<SnippetPickerEvent>
    with SnippetPickerControllerMixin
    implements SnippetPickerController {
  static const _channelName = 'com.whispaste.snippet_picker';

  MacOSSnippetPickerController() : super(_channelName);

  @override
  Future<void> show({
    required double x,
    required double y,
    required List<Map<String, String>> items,
  }) => invokeMethod('show', {'x': x, 'y': y, 'items': items});

  @override
  Future<void> hide() => invokeMethod('hide');
}
