import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'channel_desktop_paste_controller.dart';
import 'desktop_paste_controller_interface.dart';

/// Native channel for the focused field's type (#948). Returns only one of
/// the wire codes of [FocusedFieldType.fromCode], never field content.
const fieldTypeChannelName = 'com.whispaste.field_type';

const _fieldTypeChannel = MethodChannel(fieldTypeChannelName);

/// Windows bridge for desktop auto-paste.
class WindowsDesktopPasteController extends ChannelDesktopPasteController
    with ChannelClipboardReceiptBridge
    implements FocusedFieldTypeProbe {
  WindowsDesktopPasteController()
    : super(AppLogger('WindowsDesktopPasteController'));

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

  @override
  Future<FocusedFieldType> focusedFieldType() async {
    final code = await _fieldTypeChannel.invokeMethod<String>(
      'focusedFieldType',
    );
    return FocusedFieldType.fromCode(code);
  }
}
