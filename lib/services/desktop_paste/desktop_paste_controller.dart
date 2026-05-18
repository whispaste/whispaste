import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'macos_desktop_paste_controller.dart';
import 'windows_desktop_paste_controller.dart';

/// Structured outcome of a native paste call. Mirrors the `{status, detail}`
/// map returned by the platform bridges so the UI can distinguish the
/// silent failure modes (no target / permission missing / post failed)
/// instead of seeing a bare `false`.
enum NativePasteStatus {
  success,
  noTarget,
  permissionMissing,
  postFailed,
  unknown;

  static NativePasteStatus fromCode(String? code) => switch (code) {
    'success' => NativePasteStatus.success,
    'no_target' => NativePasteStatus.noTarget,
    'no_accessibility' ||
    'permission_missing' => NativePasteStatus.permissionMissing,
    'post_failed' ||
    'send_input_failed' ||
    'foreground_blocked' => NativePasteStatus.postFailed,
    _ => NativePasteStatus.unknown,
  };
}

class NativePasteResult {
  const NativePasteResult({required this.status, this.detail});

  final NativePasteStatus status;
  final String? detail;

  bool get isSuccess => status == NativePasteStatus.success;

  factory NativePasteResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const NativePasteResult(status: NativePasteStatus.unknown);
    }
    final code = map['status'] as String?;
    final detail = map['detail'] as String?;
    return NativePasteResult(
      status: NativePasteStatus.fromCode(code),
      detail: detail,
    );
  }

  factory NativePasteResult.fromLegacyBool(bool? value) => NativePasteResult(
    status: value == true
        ? NativePasteStatus.success
        : NativePasteStatus.postFailed,
  );
}

enum NativeCapabilityStatus { ready, permissionMissing, unsupported }

class NativeCapabilityResult {
  const NativeCapabilityResult({
    required this.status,
    this.canPrompt = false,
    this.detail,
  });

  final NativeCapabilityStatus status;
  final bool canPrompt;
  final String? detail;

  factory NativeCapabilityResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const NativeCapabilityResult(
        status: NativeCapabilityStatus.unsupported,
      );
    }
    final code = map['status'] as String?;
    return NativeCapabilityResult(
      status: switch (code) {
        'ready' => NativeCapabilityStatus.ready,
        'permission_missing' => NativeCapabilityStatus.permissionMissing,
        _ => NativeCapabilityStatus.unsupported,
      },
      canPrompt: map['canPrompt'] as bool? ?? false,
      detail: map['detail'] as String?,
    );
  }
}

/// Platform-agnostic interface for desktop clipboard pasting.
///
/// The controller captures the current paste target before recording starts and
/// later restores focus so a simulated paste lands back in the intended app.
abstract class DesktopPasteController {
  /// Creates the platform-specific controller, or `null` if unsupported.
  static DesktopPasteController? create() {
    if (Platform.isWindows) return WindowsDesktopPasteController();
    if (Platform.isMacOS) return MacOSDesktopPasteController();
    return null;
  }

  /// Captures the current desktop window/application as the paste target.
  ///
  /// Returns `true` when a suitable external target window was captured.
  Future<bool> capturePasteTarget();

  /// Returns the bundle ID (macOS) or process name (Windows) of the captured
  /// paste target, or `null` if no target was captured.
  Future<String?> getTargetBundleId();

  /// Restores the captured target and sends the paste shortcut.
  ///
  /// Returns a [NativePasteResult] so the caller can distinguish silent
  /// failure modes (no target, permission missing, OS post failed).
  Future<NativePasteResult> pasteClipboard({required Duration delay});

  /// Probes whether the OS would allow Auto-Paste right now — without
  /// actually pasting. When [promptIfMissing] is `true`, triggers the
  /// OS-native permission dialog if applicable (macOS Accessibility).
  Future<NativeCapabilityResult> checkCapability({
    bool promptIfMissing = false,
  });

  /// Wipes stale TCC entries for the permission services Auto-Paste uses
  /// (macOS Accessibility + AppleEvents). The next paste attempt will
  /// trigger fresh OS prompts bound to the current binary's signature —
  /// the documented workaround for ad-hoc-signed apps whose UI toggle
  /// shows "ON" but `AXIsProcessTrusted()` returns `false`.
  ///
  /// No-op on platforms without TCC (Windows). Returns the per-service
  /// counts of cleared entries (negative = call failed).
  Future<TccRepairResult> repairTccEntries();

  /// Releases any native resources held by the controller.
  Future<void> dispose();
}

class TccRepairResult {
  const TccRepairResult({
    required this.accessibilityCleared,
    required this.appleEventsCleared,
    this.error,
  });

  /// Count of Accessibility entries cleared. -1 = call failed, 0 = nothing
  /// to clear (clean state), 1+ = stale entries removed.
  final int accessibilityCleared;
  final int appleEventsCleared;
  final String? error;

  bool get isSupported => error == null;

  factory TccRepairResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const TccRepairResult(
        accessibilityCleared: -1,
        appleEventsCleared: -1,
        error: 'no_response',
      );
    }
    return TccRepairResult(
      accessibilityCleared: (map['ax'] as int?) ?? -1,
      appleEventsCleared: (map['ae'] as int?) ?? -1,
      error: map['error'] as String?,
    );
  }

  factory TccRepairResult.unsupported() => const TccRepairResult(
    accessibilityCleared: 0,
    appleEventsCleared: 0,
    error: 'unsupported_platform',
  );
}

/// Shared provider for the platform desktop paste controller.
final desktopPasteControllerProvider = Provider<DesktopPasteController?>((ref) {
  final controller = DesktopPasteController.create();
  ref.onDispose(() {
    if (controller == null) return;
    unawaited(controller.dispose());
  });
  return controller;
});
