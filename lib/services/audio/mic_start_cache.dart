/// What a recording start looks up on every call: the microphone permission
/// and the input-device listing. Both are remembered briefly so a start with a
/// chosen microphone does not repeat them each time.
///
/// Only a granted permission is remembered; a denied one is checked again. A
/// listing is dropped by [invalidate] (a failed start, system wake) or when it
/// is older than [deviceListingMaxAge]. There is no device-change event on any
/// platform yet, so the age bound limits how long an unplugged microphone can
/// stay listed.
library;

import 'package:record/record.dart' show InputDevice;

class MicStartCache {
  MicStartCache({
    this.deviceListingMaxAge = const Duration(seconds: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration deviceListingMaxAge;
  final DateTime Function() _clock;

  bool _permissionGranted = false;
  List<InputDevice>? _devices;
  DateTime? _devicesAt;

  /// Returns the permission, asking [check] only until it has been granted.
  Future<bool> hasPermission(Future<bool> Function() check) async {
    if (_permissionGranted) return true;
    final granted = await check();
    _permissionGranted = granted;
    return granted;
  }

  /// Returns the device listing, asking [list] only when no fresh listing is
  /// held. A failed listing (`null`) is returned as is and never kept.
  Future<List<InputDevice>?> inputDevices(
    Future<List<InputDevice>?> Function() list,
  ) async {
    final cached = _devices;
    final at = _devicesAt;
    if (cached != null &&
        at != null &&
        _clock().difference(at) < deviceListingMaxAge) {
      return cached;
    }
    final fresh = await list();
    _devices = fresh;
    _devicesAt = fresh == null ? null : _clock();
    return fresh;
  }

  /// Forgets the granted permission and the listing. Called after a failed
  /// start and after the system wakes, when either may have changed.
  void invalidate() {
    _permissionGranted = false;
    _devices = null;
    _devicesAt = null;
  }
}
