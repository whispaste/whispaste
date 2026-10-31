import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show protected;

import '../../core/logging/app_logger.dart';
import '../paste/input_idle.dart';
import 'desktop_paste_controller_interface.dart';

/// Shared base for channel-based desktop paste controllers (macOS + Windows).
///
/// Both platforms use the same `com.whispaste.desktop_paste` channel with
/// identical method names, argument shapes, and return-value parsing. The only
/// platform-specific behaviour is `repairTccEntries` (macOS only).
abstract class ChannelDesktopPasteController extends DesktopPasteController
    implements SecureInputProbe {
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

  /// Sends Cmd+Z to the frontmost app (macOS). Other platforms have no
  /// handler and report false, so the caller falls back to the clipboard.
  Future<bool> sendUndoShortcut() async {
    if (disposed) return false;
    try {
      return await channel.invokeMethod<bool>('sendUndoShortcut') ?? false;
    } on MissingPluginException {
      return false;
    } on Object catch (e) {
      // Any malformed or failed answer means no keystroke; the caller copies.
      _log.debug('Undo keystroke not sent', e);
      return false;
    }
  }

  bool _secureInputUnsupportedLogged = false;

  /// macOS secure input (W-E1): true while a secure field takes the keys, so a
  /// synthetic paste never reaches it. Only macOS answers; a host without the
  /// handler (Windows, Linux) reports [SecureInputState.unsupported], logged
  /// once, and the paste runs as before.
  @override
  Future<SecureInputState> secureInputState() async {
    if (disposed) return SecureInputState.unsupported;
    try {
      final raw = await channel.invokeMethod<String>('secureInputState');
      return SecureInputState.fromCode(raw);
    } on MissingPluginException {
      if (!_secureInputUnsupportedLogged) {
        _secureInputUnsupportedLogged = true;
        _log.info('Secure input detection not available on this platform');
      }
      return SecureInputState.unsupported;
    } on Object catch (e) {
      _log.debug('Secure input state unavailable', e);
      return SecureInputState.unsupported;
    }
  }

  /// The app that holds macOS secure input, for the skipped-paste notice
  /// (F35-8). Only macOS answers; a host without the handler (Windows, Linux)
  /// gets MissingPluginException and reports no holder, so the notice stays
  /// generic there. Read only after a skipped paste, never on the paste path.
  @override
  Future<SecureInputHolder?> secureInputHolder() async {
    if (disposed) return null;
    try {
      final raw = await channel.invokeMapMethod<String, Object?>(
        'secureInputHolder',
      );
      if (raw == null) return null;
      final name = raw['name'];
      final bundleId = raw['bundleId'];
      final pid = raw['pid'];
      return SecureInputHolder(
        name: name is String && name.isNotEmpty ? name : null,
        bundleId: bundleId is String && bundleId.isNotEmpty ? bundleId : null,
        pid: pid is int ? pid : null,
      );
    } on MissingPluginException {
      return null;
    } on Object catch (e) {
      _log.debug('Secure input holder unavailable', e);
      return null;
    }
  }

  /// Native input-idle snapshot (DEV-185, GS-056). Null when the host cannot
  /// answer; the caller then treats the input as typed.
  Future<InputIdleSnapshot?> inputIdleSnapshot() async {
    if (disposed) return null;
    try {
      final raw = await channel.invokeMapMethod<String, Object?>(
        'inputIdleSnapshot',
      );
      final key = raw?['keyIdle'];
      final mouse = raw?['mouseIdle'];
      final synthetic = raw?['syntheticIdle'];
      if (key is! num || mouse is! num || synthetic is! num) return null;
      return InputIdleSnapshot(
        keyIdle: key.toDouble(),
        mouseIdle: mouse.toDouble(),
        syntheticIdle: synthetic.toDouble(),
      );
    } on MissingPluginException {
      return null;
    } on Object catch (e) {
      // A malformed answer must not reach the paste path; input then counts as typed.
      _log.warning('Input idle snapshot unavailable, input counts as typed', e);
      return null;
    }
  }

  /// Extra arguments for the paste and copy shortcuts (pasteClipboard,
  /// copySelection, typeText). Linux adds the terminal shortcut flag here.
  @protected
  Future<Map<String, Object?>> shortcutArguments() async => const {};

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
      ...await shortcutArguments(),
    });
    if (raw is Map) {
      return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
    }
    // A non-bool answer counts as no answer (postFailed), like a missing one.
    return NativePasteResult.fromLegacyBool(raw is bool ? raw : null);
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
      ...await shortcutArguments(),
    });
    if (raw is Map) {
      return NativePasteResult.fromMap(raw.cast<Object?, Object?>());
    }
    return NativePasteResult.fromLegacyBool(raw is bool ? raw : null);
  }

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async {
    if (disposed) return false;
    try {
      // Object? so a non-bool answer is false instead of a TypeError.
      final raw = await channel.invokeMethod<Object?>('writeClipboardText', {
        'text': text,
      });
      return raw == true;
    } on MissingPluginException {
      // Every platform with this controller implements the method (GS-106).
      // Without it the caller falls back to a plain write that clipboard
      // history records, so make the gap loud in debug builds.
      _log.error('writeClipboardText has no native handler; plain write used');
      assert(false, 'writeClipboardText has no native handler');
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

  /// Shared channel plumbing for [ClipboardReceiptBridge] — the desktop
  /// controllers mix it in (see [ChannelClipboardReceiptBridge]).
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

/// Channel implementation of [ClipboardReceiptBridge] for the native hosts
/// (`DesktopPasteHost.swift`, `desktop_paste_host.cpp`,
/// `clipboard_receipt.cc`).
/// Every channel failure degrades to the "no receipt" answer, so the caller
/// falls back to the classic fixed-delay restore.
mixin ChannelClipboardReceiptBridge on ChannelDesktopPasteController
    implements ClipboardReceiptBridge, ClipboardSnapshotBridge {
  @override
  Future<ClipboardSnapshot> snapshotClipboard() async =>
      ClipboardSnapshot.fromMap(
        await _invokeReceiptMethod('snapshotClipboard'),
      );

  @override
  Future<ClipboardRestoreOutcome> restoreClipboardSnapshotIfOwner() async {
    final raw = await _invokeReceiptMethod('restoreClipboardSnapshotIfOwner');
    return ClipboardRestoreOutcome.fromCode(
      raw is Map ? raw['status'] as String? : null,
    );
  }

  @override
  Future<void> discardClipboardSnapshot() async {
    await _invokeReceiptMethod('discardClipboardSnapshot');
  }

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
