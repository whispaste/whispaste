/// Bridge to the native CoreAudio default-input-device switch.
///
/// On macOS, the underlying `record_macos` plugin uses `AVAudioEngine.inputNode`
/// which silently ignores `setDeviceID()` on macOS 15/26 — the user's mic
/// selection in WhisPaste settings then has no effect. To work around this
/// we flip the system default input device to the chosen one for the
/// duration of a recording and restore the original on stop.
///
/// Linux/Windows: no-op (`isSupported` returns `false`).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../core/logging/app_logger.dart';

final _log = AppLogger('AudioRouting');

class AudioRoutingService {
  AudioRoutingService();

  static const _channel = MethodChannel('com.whispaste.audio_routing');

  bool get isSupported => Platform.isMacOS;

  /// Returns the current system default input device's UID, or `null` if the
  /// lookup failed or the platform is not supported.
  Future<String?> getDefaultInputDevice() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('getDefaultInputDevice');
    } on PlatformException catch (e) {
      _log.warning('getDefaultInputDevice failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Enumerates every CoreAudio input device. Returns an empty list when the
  /// platform is not supported or the lookup fails — callers should treat
  /// empty as "fall back to system default", not as an error.
  ///
  /// The UIDs returned here are the same ones [setDefaultInputDevice] expects,
  /// which the `record_macos`-driven path doesn't guarantee.
  Future<List<InputDevice>> listInputDevices() async {
    if (!isSupported) return const <InputDevice>[];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'listInputDevices',
      );
      if (raw == null) return const <InputDevice>[];
      return raw
          .whereType<Map<Object?, Object?>>()
          .map((m) {
            final id = m['id'];
            final label = m['label'];
            if (id is! String || label is! String) return null;
            return InputDevice(id: id, label: label);
          })
          .whereType<InputDevice>()
          .toList(growable: false);
    } on PlatformException catch (e) {
      _log.warning('listInputDevices failed: $e');
      return const <InputDevice>[];
    } on MissingPluginException {
      return const <InputDevice>[];
    }
  }

  /// Switches the system default input device to the one with `uid`. Returns
  /// `true` on success.
  Future<bool> setDefaultInputDevice(String uid) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setDefaultInputDevice', {
        'uid': uid,
      });
      return ok ?? false;
    } on PlatformException catch (e) {
      _log.warning('setDefaultInputDevice($uid) failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
