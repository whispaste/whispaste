import 'package:flutter/services.dart';

import 'desktop_paste_controller_interface.dart';

/// Windows bridge for desktop auto-paste.
class WindowsDesktopPasteController extends DesktopPasteController {
  static const _channel = MethodChannel('com.whispaste.desktop_paste');

  bool _disposed = false;

  @override
  Future<bool> capturePasteTarget() async {
    if (_disposed) return false;
    final captured = await _channel.invokeMethod<bool>('captureTarget');
    return captured ?? false;
  }

  @override
  Future<String?> getTargetBundleId() async {
    if (_disposed) return null;
    final id = await _channel.invokeMethod<String>('getTargetBundleId');
    return id;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    if (_disposed) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final raw = await _channel.invokeMethod<Object?>('pasteClipboard', {
      'delayMs': delay.inMilliseconds,
    });
    if (raw is Map) {
      return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
    }
    return NativePasteResult.fromLegacyBool(raw as bool?);
  }

  @override
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  }) async {
    if (_disposed) {
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    }
    try {
      final raw = await _channel.invokeMethod<Object?>('checkCapability', {
        'prompt': promptIfMissing,
      });
      if (raw is Map) {
        return NativeCapabilityResult.fromMap(raw.cast<Object?, Object?>());
      }
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    } on MissingPluginException {
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    }
  }

  @override
  Future<TestPasteOutcome> diagnosticPaste(String demoText) async {
    if (_disposed) return const TestPasteOutcomeUnsupported();
    try {
      final raw = await _channel.invokeMethod<Object?>('diagnosticPaste', {
        'demoText': demoText,
      });
      if (raw is Map) {
        return TestPasteOutcome.fromMap(raw.cast<Object?, Object?>());
      }
      return const TestPasteOutcomeUnsupported();
    } on PlatformException {
      return const TestPasteOutcomeFailure('exception');
    } on MissingPluginException {
      return const TestPasteOutcomeFailure('exception');
    }
  }

  @override
  Future<TccRepairResult> repairTccEntries() async =>
      TccRepairResult.unsupported();

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
