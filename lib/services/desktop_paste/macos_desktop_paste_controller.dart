import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';

/// macOS bridge for desktop auto-paste via CGEvent Cmd+V.
class MacOSDesktopPasteController extends ChannelDesktopPasteController {
  MacOSDesktopPasteController()
    : super(AppLogger('MacOSDesktopPasteController'));

  @override
  Future<TccRepairResult> repairTccEntries() async {
    if (disposed) return TccRepairResult.unsupported();
    try {
      final raw = await ChannelDesktopPasteController.channel
          .invokeMethod<Object?>('repairTccEntries');
      if (raw is Map) {
        return TccRepairResult.fromMap(raw.cast<Object?, Object?>());
      }
      return TccRepairResult.unsupported();
    } on MissingPluginException {
      return TccRepairResult.unsupported();
    }
  }
}
