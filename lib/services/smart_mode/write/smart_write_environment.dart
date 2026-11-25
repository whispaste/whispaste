/// Native boundaries of the write preview, replaceable in safety tests.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/linux_keyring_lock_probe.dart';
import '../../floating_overlay/linux_floating_overlay_controller.dart';
import '../../hotkey_service.dart';
import '../../paste/paster.dart';

class SmartWriteEnvironment {
  const SmartWriteEnvironment({
    required this.wayland,
    required this.target,
    required this.foreground,
    required this.copy,
    required this.grab,
    required this.release,
    this.canEditPreview = false,
    this.returnFocus = _focusUnconfirmed,
  });

  final bool wayland;
  final Future<String?> Function() target;
  final Future<ForegroundWindow?> Function() foreground;
  final Future<bool> Function(String) copy;
  final Future<bool> Function(void Function(), void Function()) grab;
  final Future<void> Function() release;

  /// Whether the preview offers its edit field on this platform (D13, #254).
  /// The field takes the keyboard focus from the target app, so it may only
  /// show where [returnFocus] can hand it back and confirm it. On for Linux
  /// X11 (#2161); off elsewhere until the platform's native part lands.
  final bool canEditPreview;

  /// Gives the keyboard focus back to the app [target] names, before a draft
  /// edited in the preview is pasted (D13). True only when the platform
  /// confirmed that [target] is frontmost again; without that confirmation
  /// nothing is pasted and nothing copied.
  final Future<bool> Function(String? target) returnFocus;
}

/// Whether the write preview offers its edit field on [os]
/// (`Platform.operatingSystem`). On only where the native focus return of
/// that platform landed (#254); each platform part switches only its own
/// value, together with a real [SmartWriteEnvironment.returnFocus].
///
/// macOS: the overlay panel takes the keyboard during the edit session and
/// `activateTarget` hands it back with confirmation (#2159).
///
/// Windows (#2160): the overlay shell activates for the edit session and
/// `activateTarget` brings the captured target back, confirmed through
/// `GetForegroundWindow`.
///
/// Linux: only where the native overlay host answered [linuxOverlayFocus],
/// that is a plain X11 session with a WM that manages the overlay and
/// publishes `_NET_ACTIVE_WINDOW` (`overlay_edit_focus.h`). A Wayland session
/// stays off (R7): WhisPaste runs there under XWayland and cannot activate
/// the target app again, so a paste after editing would land in the overlay
/// itself instead of with the D18 hint in the target app.
bool smartWriteCanEditPreview(String os, {bool linuxOverlayFocus = false}) =>
    switch (os) {
      'macos' => true,
      'linux' => linuxOverlayFocus,
      'windows' => true,
      _ => false,
    };

/// Platforms without a confirmed focus return, and test doubles (#254).
Future<bool> _focusUnconfirmed(String? target) async => false;

/// Gives the keyboard back to [target] through [sender] and confirms it
/// (#254, D13): the host activates only the captured paste target and only
/// when its id is [target], then the window in front must be that app and
/// not WhisPaste. Any missing answer counts as unconfirmed.
Future<bool> returnFocusThrough(
  UndoKeystrokeSender? sender,
  String? target,
) async {
  if (sender == null || target == null || target.isEmpty) return false;
  try {
    if (!await sender.activateTarget(target)) return false;
    final front = await sender.foregroundWindow();
    return front != null && !front.isOwn && front.id == target;
  } on Object catch (_) {
    return false;
  }
}

/// The Linux overlay host's answer whether its overlay can take the keyboard
/// focus for the edit field and the paste host can confirm the return
/// (#254). False on other platforms, without an answer, and on Wayland.
final smartWriteOverlayEditFocusProvider = FutureProvider<bool>((ref) {
  if (!Platform.isLinux) return Future.value(false);
  final answer = Completer<bool>();
  void settle(bool value) {
    if (!answer.isCompleted) answer.complete(value);
  }

  // An own timer instead of Future.timeout: disposing the provider cancels
  // it, so the wait for an overlay host that never answers outlives nothing.
  final limit = Timer(const Duration(seconds: 5), () => settle(false));
  ref.onDispose(limit.cancel);
  LinuxFloatingOverlayController.editFocusSupport().then(
    (supported) {
      limit.cancel();
      settle(supported);
    },
    onError: (Object _) {
      limit.cancel();
      settle(false);
    },
  );
  return answer.future;
});

final smartWriteEnvironmentProvider = Provider<SmartWriteEnvironment>((ref) {
  final paster = ref.watch(pasterProvider);
  final sender = paster is UndoKeystrokeSender
      ? paster as UndoKeystrokeSender
      : null;
  final keys = ref.read(hotkeyServiceProvider.notifier);
  var generation = 0;
  final linuxOverlayFocus =
      ref.watch(smartWriteOverlayEditFocusProvider).value ?? false;
  return SmartWriteEnvironment(
    canEditPreview: smartWriteCanEditPreview(
      Platform.operatingSystem,
      linuxOverlayFocus: linuxOverlayFocus,
    ),
    // macOS: activate the captured target and confirm it is in front
    // (#2159). X11: the paste host activates the captured target window
    // through `_NET_ACTIVE_WINDOW` and answers true only once the WM reports
    // it active (`activateTarget`, the same path as the keystroke undo). It
    // answers false on Wayland by itself. Windows: the native host brings
    // back only the captured window and confirms it via
    // `GetForegroundWindow` (#2160). Not tied to [linuxOverlayFocus]:
    // the preview keeps the environment it read first, possibly before the
    // overlay host answered.
    returnFocus: Platform.isMacOS
        ? (target) => returnFocusThrough(sender, target)
        : Platform.isLinux || Platform.isWindows
        ? (target) async {
            if (target == null) return false;
            return await sender?.activateTarget(target) ?? false;
          }
        : _focusUnconfirmed,
    wayland:
        Platform.isLinux &&
        (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' ||
            (Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty ?? false)),
    target: () async => paster?.getTargetBundleId(),
    foreground: () async => sender?.foregroundWindow(),
    copy: (text) async => sender?.copyOriginalToClipboard(text) ?? false,
    grab: (insert, discard) async {
      final current = ++generation;
      final escape = await keys.registerCancelDictationKey(onCancel: discard);
      if (current != generation) return false;
      final enter = await keys.registerNoticeActionKey(
        onPressed: insert,
        key: LogicalKeyboardKey.enter,
      );
      return current == generation && escape && enter;
    },
    release: () async {
      generation++;
      // Invalidate both epochs synchronously before either native wait.
      final enter = keys.unregisterNoticeActionKey();
      final escape = keys.unregisterCancelDictationKey();
      await enter;
      await escape;
    },
  );
});

final smartWriteKeyringProbeProvider =
    Provider<Future<KeyringAvailability> Function()>(
      (ref) => probeLinuxKeyring,
    );
