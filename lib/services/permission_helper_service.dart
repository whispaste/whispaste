/// Permission helper — on macOS a small panel docks to System Settings >
/// Privacy > Accessibility or > Input Monitoring with one text-free picture
/// on both builds: the WhisPaste row whose switch turns on (a looping clip, a
/// still under "Reduce motion"; assets/permission_guide/, #753). On the
/// Developer-ID build the picture can also be dragged into the list. The app
/// hears when the grant arrives (`internal-notes
/// onboarding-v6/intro-av/spec.md`, "macOS accessibility permission helper").
///
/// Native side: `macos/Runner/PermissionHelperHost.swift` on the channel
/// `whispaste/permission_helper` (`show`, `hide`; events `granted`, `closed`).
///
/// Windows and Linux need neither grant, so there is no native host:
/// [PermissionHelperService.show] answers
/// [PermissionHelperShowResult.unsupported] without a channel call, and the
/// onboarding keeps its keyboard-operable text guide, which is always shown
/// on every platform.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('PermissionHelper');

/// The permission the panel helps with.
enum PermissionHelperKind {
  /// Privacy > Accessibility: Auto-Paste.
  accessibility,

  /// Privacy > Input Monitoring: a single key as the trigger (#1198).
  inputMonitoring,
}

/// What [PermissionHelperService.show] did.
enum PermissionHelperShowResult {
  /// System Settings is open and the panel is docked to it.
  shown,

  /// The permission is already granted; nothing was shown.
  granted,

  /// No helper on this platform or build; show the text guide only.
  unsupported,

  /// The native call failed; the text guide still works.
  failed,
}

/// Why the panel closed by itself.
enum PermissionHelperCloseReason {
  /// The user granted the permission.
  granted,

  /// Nothing happened for 5 minutes.
  timeout,

  /// The user quit System Settings or closed the panel.
  cancelled,
}

/// One event from the native panel.
typedef PermissionHelperEvent = ({
  PermissionHelperKind kind,
  PermissionHelperCloseReason reason,
});

final class PermissionHelperService {
  PermissionHelperService({MethodChannel? channel, bool? isMacOS})
    : _channel = channel ?? const MethodChannel('whispaste/permission_helper'),
      _isMacOS = isMacOS ?? Platform.isMacOS {
    if (_isMacOS) _channel.setMethodCallHandler(_onNativeCall);
  }

  final MethodChannel _channel;
  final bool _isMacOS;
  final _events = StreamController<PermissionHelperEvent>.broadcast();

  /// The panel closed by itself: granted, timed out or cancelled. The
  /// onboarding advances on [PermissionHelperCloseReason.granted].
  Stream<PermissionHelperEvent> get events => _events.stream;

  /// Opens System Settings at the [kind] list and docks the panel with
  /// [text] (localised, e.g. `onboardingAccessibilityDragHint`), a smaller
  /// [note] under it (e.g. remove an old entry with "−" first) and a close
  /// button labelled [closeLabel].
  Future<PermissionHelperShowResult> show(
    PermissionHelperKind kind, {
    required String text,
    required String note,
    required String closeLabel,
  }) async {
    if (!_isMacOS) return PermissionHelperShowResult.unsupported;
    try {
      final answer = await _channel.invokeMethod<String>('show', {
        'kind': kind.name,
        'text': text,
        'note': note,
        'closeLabel': closeLabel,
      });
      return switch (answer) {
        'shown' => PermissionHelperShowResult.shown,
        'granted' => PermissionHelperShowResult.granted,
        'unsupported' => PermissionHelperShowResult.unsupported,
        _ => PermissionHelperShowResult.failed,
      };
    } on PlatformException catch (e) {
      _log.warning('show failed: $e');
      return PermissionHelperShowResult.failed;
    } on MissingPluginException {
      return PermissionHelperShowResult.failed;
    }
  }

  /// Closes the panel without an event, e.g. when the user leaves the step.
  Future<void> hide() async {
    if (!_isMacOS) return;
    try {
      await _channel.invokeMethod<void>('hide');
    } on PlatformException catch (e) {
      _log.debug('hide failed: $e');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> _onNativeCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return;
    final kind = PermissionHelperKind.values.asNameMap()[args['kind']];
    if (kind == null) return;
    final reason = switch (call.method) {
      'granted' => PermissionHelperCloseReason.granted,
      'closed' =>
        PermissionHelperCloseReason.values.asNameMap()[args['reason']],
      _ => null,
    };
    if (reason != null) _events.add((kind: kind, reason: reason));
  }

  void dispose() {
    if (_isMacOS) _channel.setMethodCallHandler(null);
    _events.close();
  }
}

final permissionHelperProvider = Provider<PermissionHelperService>((ref) {
  final service = PermissionHelperService();
  ref.onDispose(service.dispose);
  return service;
});
