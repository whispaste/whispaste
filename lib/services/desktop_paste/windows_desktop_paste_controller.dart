import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';

/// Windows bridge for desktop auto-paste.
class WindowsDesktopPasteController extends ChannelDesktopPasteController {
  WindowsDesktopPasteController()
    : super(AppLogger('WindowsDesktopPasteController'));

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();
}
