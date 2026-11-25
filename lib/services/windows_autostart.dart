import 'package:flutter/services.dart';

import 'autostart_backend.dart';

/// MSIX must register a manifest task, never a versioned WindowsApps EXE.
/// Package identity comes from Windows, not a path/name heuristic.
class WindowsAutostartBackend implements AutostartBackend {
  WindowsAutostartBackend(this.unpacked);

  final AutostartBackend unpacked;
  static const channel = MethodChannel('com.whispaste.autostart');

  Future<bool> _isPackaged() async =>
      (await channel.invokeMethod<bool>('isPackaged'))!;

  @override
  Future<bool> isEnabled() async => await _isPackaged()
      ? (await channel.invokeMethod<bool>('isEnabled'))!
      : unpacked.isEnabled();

  @override
  Future<void> enable() async {
    if (!await _isPackaged()) return unpacked.enable();
    if (await channel.invokeMethod<bool>('enable') != true) {
      throw StateError('Windows did not enable the startup task');
    }
  }

  @override
  Future<void> disable() async {
    if (!await _isPackaged()) return unpacked.disable();
    if (await channel.invokeMethod<bool>('disable') != false) {
      throw StateError('Windows did not disable the startup task');
    }
  }

  @override
  Future<bool> requiresApproval() async => false;

  @override
  Future<void> openLoginItems() async {}
}

/// launch_at_startup concatenates the path and arguments without quoting.
String windowsAutostartExecutable(String executable) => '"$executable"';
