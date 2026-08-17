import '../method_channel_platform_host.dart';
import 'snippet_picker_controller_interface.dart';
import 'snippet_picker_controller_mixin.dart';
import 'snippet_picker_events.dart';

/// Linux implementation of [SnippetPickerController] (visual-refresh-2026
/// ticket 30).
///
/// Same channel name and method contract as [WindowsSnippetPickerController]
/// / [MacOSSnippetPickerController] — see
/// `snippet_picker_controller_interface.dart` for the shared shell contract
/// this mirrors. The native counterpart is `linux/runner/snippet_picker_host.cc`.
class LinuxSnippetPickerController
    extends MethodChannelPlatformHost<SnippetPickerEvent>
    with SnippetPickerControllerMixin
    implements SnippetPickerController {
  static const _channelName = 'com.whispaste.snippet_picker';

  LinuxSnippetPickerController() : super(_channelName);

  @override
  Future<void> show({required List<Map<String, String>> items}) =>
      invokeMethod('show', {'items': items});

  @override
  Future<void> hide() => invokeMethod('hide');
}
