import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';
import 'windows_desktop_paste_controller.dart' show fieldTypeChannelName;

const _fieldTypeChannel = MethodChannel(fieldTypeChannelName);

/// macOS bridge for desktop auto-paste via CGEvent Cmd+V.
class MacOSDesktopPasteController extends ChannelDesktopPasteController
    with ChannelClipboardReceiptBridge
    implements FocusedFieldTypeProbe {
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

  /// Role and subrole of the focused field through Accessibility (#949), never
  /// its content. Without the permission, in the Mac App Store build or on any
  /// failure the host answers `unknown` and the paste goes on as before.
  @override
  Future<FocusedFieldType> focusedFieldType() async {
    if (disposed) return FocusedFieldType.unknown;
    try {
      final code = await _fieldTypeChannel.invokeMethod<String>(
        'focusedFieldType',
      );
      return FocusedFieldType.fromCode(code);
    } on MissingPluginException {
      return FocusedFieldType.unknown;
    }
  }
}
