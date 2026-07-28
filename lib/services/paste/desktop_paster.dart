import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../desktop_paste/desktop_paste_controller.dart';
import 'paster.dart';

final _log = AppLogger('DesktopPaster');

/// [Paster] implementation for Windows and macOS using [DesktopPasteController].
///
/// Implements the full paste lifecycle:
/// - Blocklist check via bundle ID
/// - On macOS and Windows, tries direct Unicode typing first (see
///   [typeText]) — more broadly compatible and clipboard-free — falling
///   back to the classic clipboard save → set transcript → native paste →
///   wait → clipboard restore sequence if typing doesn't land. Linux stays
///   on the classic sequence until it has a native typeText handler too.
///
/// The choice of native mechanism is an implementation detail: from the
/// user's perspective there is one "paste" action, regardless of which of
/// the two channels actually delivered the text.
class DesktopPaster implements Paster {
  const DesktopPaster(this._controller);

  final DesktopPasteController _controller;

  @override
  Future<void> prime() async {
    try {
      await _controller.capturePasteTarget();
    } on MissingPluginException catch (e) {
      // Not available in test environments — silently degrade.
      _log.debug('capturePasteTarget unavailable (MissingPlugin)', e);
    }
  }

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async {
    try {
      final raw = await _controller.checkCapability(
        promptIfMissing: promptIfMissing,
      );
      return PasteCapability(
        status: switch (raw.status) {
          NativeCapabilityStatus.ready => PasteCapabilityStatus.ready,
          NativeCapabilityStatus.permissionMissing =>
            PasteCapabilityStatus.permissionMissing,
          NativeCapabilityStatus.unsupported =>
            PasteCapabilityStatus.unsupported,
        },
        canPrompt: raw.canPrompt,
        detail: raw.detail,
      );
    } on MissingPluginException {
      return const PasteCapability(status: PasteCapabilityStatus.unsupported);
    } on Exception {
      return const PasteCapability(status: PasteCapabilityStatus.unsupported);
    }
  }

  /// Returns [PasteOutcome.blocked] when the captured target's bundle ID is
  /// on [blocklist]; `null` otherwise (including when the lookup is
  /// unsupported or the target ID is unavailable). Shared by [paste] and
  /// [typeText] — both gate on the same blocklist.
  Future<PasteOutcome?> _checkBlocklist(String blocklist) async {
    final trimmed = blocklist.trim();
    if (trimmed.isEmpty) return null;
    try {
      final targetId = await _controller.getTargetBundleId();
      if (targetId == null || targetId.isEmpty) return null;
      final blocked = trimmed
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (blocked.contains(targetId.toLowerCase())) {
        return PasteOutcome.blocked;
      }
      return null;
    } on MissingPluginException catch (e) {
      // Bundle ID lookup unsupported — skip blocklist.
      _log.debug(
        'getTargetBundleId unavailable (MissingPlugin) — blocklist skipped',
        e,
      );
      return null;
    }
  }

  /// Maps a non-success [NativePasteResult] to the matching [PasteOutcome].
  /// Shared by [paste] and [typeText] — both native bridges report the same
  /// status vocabulary.
  PasteOutcome _mapFailure(NativePasteResult result) => switch (result.status) {
    NativePasteStatus.noTarget => PasteOutcome.noTarget,
    NativePasteStatus.permissionMissing => PasteOutcome.permissionMissing,
    NativePasteStatus.foregroundBlocked => PasteOutcome.elevationBlocked,
    _ => PasteOutcome.failed,
  };

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    // 1. Blocklist check
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) return blocked;

    // Prefer direct Unicode typing on macOS/Windows: more broadly compatible
    // (lands even in apps that don't respond to a paste shortcut) and skips
    // the clipboard save/restore round-trip entirely. Falls through to the
    // classic clipboard+paste-shortcut sequence below if typing doesn't land
    // — e.g. an app that only accepts the literal paste shortcut. Linux
    // stays on the classic sequence until it has a native typeText handler.
    if (Platform.isMacOS || Platform.isWindows) {
      final typeOutcome = await _typeTextCore(text, options);
      if (typeOutcome == PasteOutcome.success) return typeOutcome;
      _log.info(
        'Direct typing did not land ($typeOutcome) — falling back to '
        'clipboard + paste shortcut',
      );
    }

    // 2. Save current clipboard contents so we can restore after paste.
    String? previousClipboard;
    try {
      final data = await Clipboard.getData(
        Clipboard.kTextPlain,
      ).timeout(const Duration(seconds: 2));
      previousClipboard = data?.text;
    } on Exception catch (e) {
      // Best-effort snapshot; failure here is non-fatal.
      _log.debug(
        'Clipboard read before paste failed — proceeding without restore',
        e,
      );
    }

    // 3. Write transcript to clipboard.
    try {
      await Clipboard.setData(
        ClipboardData(text: text),
      ).timeout(const Duration(seconds: 5));
    } on Exception {
      return PasteOutcome.failed;
    }

    // 4. Trigger native paste shortcut.
    final delayMs = options.autoPasteDelayMs.clamp(0, 30000);
    final delay = Duration(milliseconds: delayMs);
    NativePasteResult pasteResult = const NativePasteResult(
      status: NativePasteStatus.unknown,
    );
    try {
      pasteResult = await _controller.pasteClipboard(delay: delay);
    } on MissingPluginException {
      return PasteOutcome.platformUnavailable;
    } on Exception {
      return PasteOutcome.failed;
    }

    // Always log the native detail string so we can diagnose silent-drop
    // scenarios where Swift reports success (CGEvent post returned, no
    // error) but the keystroke didn't actually land in the target app.
    _log.info(
      'Native paste result: status=${pasteResult.status.name} '
      'detail=${pasteResult.detail ?? "<none>"}',
    );

    if (!pasteResult.isSuccess) {
      return _mapFailure(pasteResult);
    }

    // 5. Wait before restoring clipboard.
    // Minimum 500 ms so the OS paste has landed before we overwrite it.
    final restoreMs = math.max(500, delayMs + 350);
    await Future<void>.delayed(Duration(milliseconds: restoreMs));

    // 6. Restore previous clipboard contents.
    try {
      await Clipboard.setData(
        ClipboardData(text: previousClipboard ?? ''),
      ).timeout(const Duration(seconds: 5));
    } on Exception catch (e) {
      // Non-fatal — clipboard restore is best-effort.
      _log.debug('Clipboard restore after paste failed', e);
    }

    return PasteOutcome.success;
  }

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async {
    // 1. Blocklist check — same policy as paste().
    final blocked = await _checkBlocklist(options.blocklist);
    if (blocked != null) return blocked;
    return _typeTextCore(text, options);
  }

  /// The actual native Unicode-type call, without a blocklist check — reused
  /// by both [typeText] (which does its own check first) and [paste]'s
  /// macOS-preferred-mechanism attempt (which already checked the blocklist
  /// before calling this, so re-checking would be a redundant native round
  /// trip). No clipboard involved, so there is nothing to save/restore.
  Future<PasteOutcome> _typeTextCore(String text, PasteOptions options) async {
    final delayMs = options.autoPasteDelayMs.clamp(0, 30000);
    NativePasteResult typeResult = const NativePasteResult(
      status: NativePasteStatus.unknown,
    );
    try {
      typeResult = await _controller.typeText(
        text,
        delay: Duration(milliseconds: delayMs),
      );
    } on MissingPluginException {
      return PasteOutcome.platformUnavailable;
    } on Exception {
      return PasteOutcome.failed;
    }

    _log.info(
      'Native type result: status=${typeResult.status.name} '
      'detail=${typeResult.detail ?? "<none>"}',
    );

    if (!typeResult.isSuccess) {
      return _mapFailure(typeResult);
    }

    return PasteOutcome.success;
  }
}

final pasterProvider = Provider<Paster?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return DesktopPaster(controller);
});
