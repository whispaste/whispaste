import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_paste/desktop_paste_controller.dart';
import 'paster.dart';

/// [Paster] implementation for Windows and macOS using [DesktopPasteController].
///
/// Implements the full paste lifecycle:
/// - Blocklist check via bundle ID
/// - Clipboard save → set transcript → native paste → wait → clipboard restore
class DesktopPaster implements Paster {
  const DesktopPaster(this._controller);

  final DesktopPasteController _controller;

  @override
  Future<void> prime() async {
    try {
      await _controller.capturePasteTarget();
    } on MissingPluginException {
      // Not available in test environments — silently degrade.
    }
  }

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async {
    // 1. Blocklist check
    final blocklist = options.blocklist.trim();
    if (blocklist.isNotEmpty) {
      try {
        final targetId = await _controller.getTargetBundleId();
        if (targetId != null && targetId.isNotEmpty) {
          final blocked = blocklist
              .split(',')
              .map((e) => e.trim().toLowerCase())
              .where((e) => e.isNotEmpty)
              .toSet();
          if (blocked.contains(targetId.toLowerCase())) {
            return PasteOutcome.blocked;
          }
        }
      } on MissingPluginException {
        // Bundle ID lookup unsupported — skip blocklist.
      }
    }

    // 2. Save current clipboard contents so we can restore after paste.
    String? previousClipboard;
    try {
      final data = await Clipboard.getData(
        Clipboard.kTextPlain,
      ).timeout(const Duration(seconds: 2));
      previousClipboard = data?.text;
    } on Exception {
      // Best-effort snapshot; failure here is non-fatal.
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
    bool pasted = false;
    try {
      pasted = await _controller.pasteClipboard(delay: delay);
    } on MissingPluginException {
      return PasteOutcome.platformUnavailable;
    } on Exception {
      return PasteOutcome.failed;
    }

    if (!pasted) return PasteOutcome.failed;

    // 5. Wait before restoring clipboard.
    // Minimum 500 ms so the OS paste has landed before we overwrite it.
    final restoreMs = math.max(500, delayMs + 350);
    await Future<void>.delayed(Duration(milliseconds: restoreMs));

    // 6. Restore previous clipboard contents.
    try {
      await Clipboard.setData(
        ClipboardData(text: previousClipboard ?? ''),
      ).timeout(const Duration(seconds: 5));
    } on Exception {
      // Non-fatal — clipboard restore is best-effort.
    }

    return PasteOutcome.success;
  }
}

final pasterProvider = Provider<Paster?>((ref) {
  final controller = ref.watch(desktopPasteControllerProvider);
  if (controller == null) return null;
  return DesktopPaster(controller);
});
