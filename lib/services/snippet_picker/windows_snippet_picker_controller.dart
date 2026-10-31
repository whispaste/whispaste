import '../method_channel_platform_host.dart';
import 'snippet_picker_controller_interface.dart';
import 'snippet_picker_controller_mixin.dart';
import 'snippet_picker_events.dart';

/// Windows implementation of [SnippetPickerController] (ticket 29).
///
/// Same channel name and method contract as [MacOSSnippetPickerController]
/// — see `snippet_picker_controller_interface.dart` for the shared shell
/// contract this mirrors. The native counterpart is
/// `windows/runner/snippet_picker_host.cpp`.
class WindowsSnippetPickerController
    extends MethodChannelPlatformHost<SnippetPickerEvent>
    with SnippetPickerControllerMixin
    implements SnippetPickerController {
  static const _channelName = 'com.whispaste.snippet_picker';

  WindowsSnippetPickerController() : super(_channelName);

  @override
  Future<void> show({required List<Map<String, String>> items}) =>
      invokeMethod('show', {'items': items});

  @override
  Future<void> hide() => invokeMethod('hide');
}
