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
  Future<NativePasteResult> pasteClipboard({required Duration delay}) =>
      _sendShortcut('pasteClipboard', delay);

  @override
  Future<NativePasteResult> copySelection({required Duration delay}) =>
      _sendShortcut('copySelection', delay);

  /// Paste and copy share one native contract: focus the captured target,
  /// wait [delay], send the shortcut, report a [NativePasteResult].
  Future<NativePasteResult> _sendShortcut(String method, Duration delay) async {
    if (disposed) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final raw = await channel.invokeMethod<Object?>(method, {
      'delayMs': delay.inMilliseconds,
    });
    if (raw is Map) {
      return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
    }
    return NativePasteResult.fromLegacyBool(raw as bool?);
  }

  @override
  Future<NativePasteResult> typeText(
    String text, {
    required Duration delay,
  }) async {
    if (disposed) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final raw = await channel.invokeMethod<Object?>('typeText', {
      'text': text,
      'delayMs': delay.inMilliseconds,
    });
    if (raw is Map) {
      return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
    }
    return NativePasteResult.fromLegacyBool(raw as bool?);
  }

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async {
    if (disposed) return false;
    try {
      final raw = await channel.invokeMethod<bool>('writeClipboardText', {
        'text': text,
      });
      return raw ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
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

  /// Shared channel plumbing for [ClipboardReceiptBridge] — only the
  /// macOS/Windows controllers mix it in (see
  /// [ChannelClipboardReceiptBridge]); Linux has no native handler.
  Future<Object?> _invokeReceiptMethod(
    String method, [
    Map<String, Object?>? args,
  ]) async {
    if (disposed) return null;
    try {
      return await channel.invokeMethod<Object?>(method, args);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      _log.debug('$method failed', e);
      return null;
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

/// Channel implementation of [ClipboardReceiptBridge] for the macOS and
/// Windows native hosts (`DesktopPasteHost.swift` / `desktop_paste_host.cpp`).
/// Every channel failure degrades to the "no receipt" answer, so the caller
/// falls back to the classic fixed-delay restore.
mixin ChannelClipboardReceiptBridge on ChannelDesktopPasteController
    implements ClipboardReceiptBridge {
  @override
  Future<bool> writeClipboardTextWithReceipt(String text) async =>
      await _invokeReceiptMethod('writeClipboardTextWithReceipt', {
        'text': text,
      }) ==
      true;

  @override
  Future<ClipboardReadReceipt> waitForClipboardRead() async {
    final raw = await _invokeReceiptMethod('waitForClipboardRead');
    return ClipboardReadReceipt.fromCode(
      raw is Map ? raw['status'] as String? : null,
    );
  }

  @override
  Future<ClipboardRestoreOutcome> restoreClipboardTextIfOwner(
    String text,
  ) async {
    final raw = await _invokeReceiptMethod('restoreClipboardTextIfOwner', {
      'text': text,
    });
    return ClipboardRestoreOutcome.fromCode(
      raw is Map ? raw['status'] as String? : null,
    );
  }
}
