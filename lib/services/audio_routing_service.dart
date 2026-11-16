/// Bridge to the native CoreAudio default-input-device switch.
///
/// On macOS, the underlying `record_macos` plugin uses `AVAudioEngine.inputNode`
/// which silently ignores `setDeviceID()` on macOS 15/26 — the user's mic
/// selection in WhisPaste settings then has no effect. To work around this
/// we flip the system default input device to the chosen one for the
/// duration of a recording and restore the original on stop.
///
/// Windows supports default-input lookup only; switching remains macOS-only.
/// Linux resolves its default source through the sound server.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../core/logging/app_logger.dart';
import 'audio/linux_lid_state.dart';

final _log = AppLogger('AudioRouting');

class AudioRoutingService {
  AudioRoutingService();

  static const _channel = MethodChannel('com.whispaste.audio_routing');

  /// Whether changing the system default is supported (macOS workaround).
  bool get isSupported => Platform.isMacOS;

  bool get canReadDefaultInput => Platform.isMacOS || Platform.isWindows;

  /// Returns the current system default input device's UID, or `null` if the
  /// lookup failed or the platform is not supported.
  Future<String?> getDefaultInputDevice() async {
    if (!canReadDefaultInput) return null;
    try {
      return await _channel.invokeMethod<String>('getDefaultInputDevice');
    } on PlatformException catch (e) {
      _log.warning('getDefaultInputDevice failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Matches the native endpoint ID against record's IDs, never display names.
  /// Unknown/default-disconnected endpoints must not produce a suggestion.
  Future<String?> defaultInputLabel(List<InputDevice> devices) async {
    final id = await getDefaultInputDevice();
    if (id == null || id.isEmpty) return null;
    for (final device in devices) {
      if (device.id == id && device.label.isNotEmpty) return device.label;
    }
    return null;
  }

  /// Whether the notebook lid is closed (macOS clamshell mode, #846; Linux
  /// ACPI lid switch, #932): the built-in microphone is silent then. `false`
  /// on Windows (it only announces lid changes as events, there is no query,
  /// so silence detection stays the signal), on machines without a lid, and
  /// whenever the lookup fails: an unknown state never excludes a device.
  Future<bool> isLidClosed() async {
    if (Platform.isLinux) return linuxLidClosed();
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isLidClosed') ?? false;
    } on PlatformException catch (e) {
      _log.warning('isLidClosed failed: $e');
      return false;
    } on MissingPluginException {
      return false;
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
