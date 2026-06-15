import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show protected;

import '../../core/logging/app_logger.dart';
import 'desktop_paste_controller_interface.dart';

/// Shared base for channel-based desktop paste controllers (macOS + Windows).
///
/// Both platforms use the same `com.whispaste.desktop_paste` channel with
/// identical method names, argument shapes, and return-value parsing. The only
/// platform-specific behaviour is `repairTccEntries` (macOS only).
abstract class ChannelDesktopPasteController extends DesktopPasteController {
  ChannelDesktopPasteController(this._log);

  @protected
  static const channel = MethodChannel('com.whispaste.desktop_paste');

  final AppLogger _log;

  @protected
  bool disposed = false;

  @override
  Future<bool> capturePasteTarget() async {
    if (disposed) return false;
    final captured = await channel.invokeMethod<bool>('captureTarget');
    return captured ?? false;
  }

  @override
  Future<String?> getTargetBundleId() async {
    if (disposed) return null;
    final id = await channel.invokeMethod<String>('getTargetBundleId');
    return id;
  }

  @override
  Future<NativePasteResult> pasteClipboard({required Duration delay}) async {
    if (disposed) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final raw = await channel.invokeMethod<Object?>('pasteClipboard', {
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
    if (disposed) {
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    }
    try {
      final raw = await channel.invokeMethod<Object?>('checkCapability', {
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
    if (disposed) return const TestPasteOutcomeUnsupported();
    try {
      final raw = await channel.invokeMethod<Object?>('diagnosticPaste', {
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
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    try {
      await channel.invokeMethod<void>('destroy');
    } on MissingPluginException catch (e) {
      // Expected in test environments without the native runner bridge.
      _log.debug('destroy channel unavailable (MissingPlugin)', e);
    }
  }
}
