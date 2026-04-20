import 'package:flutter/services.dart';

import 'desktop_paste_controller.dart';

/// macOS bridge for desktop auto-paste via CGEvent Cmd+V.
class MacOSDesktopPasteController extends DesktopPasteController {
  static const _channel = MethodChannel('com.whispaste.desktop_paste');

  bool _disposed = false;

  @override
  Future<bool> capturePasteTarget() async {
    if (_disposed) return false;
    final captured = await _channel.invokeMethod<bool>('captureTarget');
    return captured ?? false;
  }

  @override
  Future<bool> pasteClipboard({required Duration delay}) async {
    if (_disposed) return false;
    final didPaste = await _channel.invokeMethod<bool>('pasteClipboard', {
      'delayMs': delay.inMilliseconds,
    });
    return didPaste ?? false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _channel.invokeMethod<void>('destroy');
    } on MissingPluginException {
      // Expected in test environments without the native runner bridge.
    }
  }
}
