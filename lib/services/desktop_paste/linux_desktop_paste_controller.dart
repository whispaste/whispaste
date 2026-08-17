import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';

/// Linux bridge for desktop auto-paste (visual-refresh-2026 ticket 30).
///
/// Backed by a virtual /dev/uinput keyboard — no TCC/AX-style permission
/// system exists on Linux, so [repairTccEntries] is unsupported same as
/// Windows. `permission_missing` (surfaced via [checkCapability] and the
/// paste/type status codes) means the uinput device node is present but this
/// user can't write to it yet — see `desktop_paste_host.cc`'s class comment
/// for the udev-access fix.
class LinuxDesktopPasteController extends ChannelDesktopPasteController {
  LinuxDesktopPasteController()
    : super(AppLogger('LinuxDesktopPasteController'));

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();
}
