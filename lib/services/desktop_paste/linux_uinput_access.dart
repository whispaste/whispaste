/// Grants and removes Auto-Paste's /dev/uinput access on a .deb install
/// (security review R-02).
///
/// The package grants nothing on install. After the user agreed in the app,
/// this runs the root helper the .deb ships through pkexec; the polkit
/// action `de.whispaste.uinput.manage` asks for the administrator password
/// (packaging/linux/whispaste-uinput-access, de.whispaste.uinput.policy).
/// Flatpak, AppImage and the tarball have no helper: there the app shows
/// the command to copy instead.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';

final _log = AppLogger('LinuxUinputAccess');

/// How a grant or removal ended.
enum UinputAccessChange {
  done,

  /// The user closed the password dialog or polkit refused.
  cancelled,
  failed,

  /// No helper on this install (not a .deb).
  unavailable,
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class LinuxUinputAccess {
  LinuxUinputAccess({ProcessRunner? run, bool Function(String path)? exists})
    : _run = run ?? Process.run,
      _exists = exists ?? ((path) => File(path).existsSync());

  static const helperPath = '/usr/libexec/whispaste/uinput-access';
  static const pkexecPath = '/usr/bin/pkexec';

  final ProcessRunner _run;
  final bool Function(String path) _exists;

  /// Whether this install can grant and remove the access itself.
  bool get canManage => _exists(helperPath) && _exists(pkexecPath);

  /// Whether the udev rule the helper installs is in place.
  Future<bool> isGranted() async {
    if (!_exists(helperPath)) return false;
    try {
      return (await _run(helperPath, const ['status'])).exitCode == 0;
    } on ProcessException catch (e) {
      _log.warning('uinput access status unavailable', e);
      return false;
    }
  }

  Future<UinputAccessChange> enable() => _change('enable');

  Future<UinputAccessChange> disable() => _change('disable');

  Future<UinputAccessChange> _change(String verb) async {
    if (!canManage) return UinputAccessChange.unavailable;
    try {
      final result = await _run(pkexecPath, [helperPath, verb]);
      switch (result.exitCode) {
        case 0:
          _log.info('uinput access: $verb done');
          return UinputAccessChange.done;
        // pkexec: 126 = dialog dismissed, 127 = not authorized.
        case 126 || 127:
          _log.info('uinput access: $verb cancelled');
          return UinputAccessChange.cancelled;
        default:
          _log.warning('uinput access: $verb failed (${result.exitCode})');
          return UinputAccessChange.failed;
      }
    } on ProcessException catch (e) {
      _log.warning('uinput access: pkexec not runnable', e);
      return UinputAccessChange.failed;
    }
  }
}

final linuxUinputAccessProvider = Provider<LinuxUinputAccess>(
  (ref) => LinuxUinputAccess(),
);
