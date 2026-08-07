/// Shared microphone-selection logic for every quick-switch surface (tray
/// submenu, status-bar chip).
///
/// A selection persists the label to settings on all platforms (same path as
/// the settings dropdown) and, on macOS, additionally flips the system
/// default input device right away via [AudioRoutingService] so the switch
/// works without opening System Settings.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';
import 'audio_routing_service.dart';

/// Sentinel label meaning "system default" — mirrors `settings.microphone`.
const micDefaultLabel = 'Default';

/// Builds the option list for a microphone quick-switcher: the system-default
/// sentinel first, then the enumerated devices.
///
/// A selected-but-absent device (e.g. unplugged while undocked) is appended
/// so the current selection never silently disappears.
List<String> buildMicrophoneOptions({
  required List<String> deviceLabels,
  required String selectedLabel,
}) {
  final devices = deviceLabels
      .where((label) => label != micDefaultLabel && label.isNotEmpty)
      .toList();
  if (selectedLabel != micDefaultLabel && !devices.contains(selectedLabel)) {
    devices.add(selectedLabel);
  }
  return [micDefaultLabel, ...devices];
}

/// Applies a microphone choice made from any quick-switch surface.
///
/// Injectable dependencies keep the persistence path and the CoreAudio
/// routing unit-testable without a Riverpod container or platform channels.
class MicrophoneSelectionService {
  MicrophoneSelectionService({
    required this._persistLabel,
    AudioRoutingService? audioRouting,
  }) : _audioRouting = audioRouting ?? AudioRoutingService();

  static final _log = AppLogger('MicrophoneSelection');

  final Future<void> Function(String label) _persistLabel;
  final AudioRoutingService _audioRouting;

  /// Persists [label] on all platforms, then on macOS immediately switches
  /// the system default input to the matching device.
  Future<void> select(String label) async {
    try {
      await _persistLabel(label);
      _log.info('Mic selection → "$label"');
    } on Exception catch (e) {
      _log.warning('Persisting mic selection failed: $e');
    }

    if (label != micDefaultLabel && _audioRouting.isSupported) {
      await _applySystemDefaultInput(label);
    }
  }

  /// Resolves [label] against the CoreAudio enumeration and switches the
  /// system default input to it. Only those UIDs are valid for
  /// [AudioRoutingService.setDefaultInputDevice] — the ids from the
  /// `record`-package enumeration are not guaranteed to be.
  Future<void> _applySystemDefaultInput(String label) async {
    final devices = await _audioRouting.listInputDevices();
    String? uid;
    for (final d in devices) {
      if (d.label == label) {
        uid = d.id;
        break;
      }
    }
    if (uid == null) {
      _log.warning(
        'Mic "$label" not found in CoreAudio device list — '
        'system default left unchanged',
      );
      return;
    }
    final ok = await _audioRouting.setDefaultInputDevice(uid);
    if (ok) {
      _log.info('System default input switched to "$label" ($uid)');
    } else {
      _log.warning('Switching system default input to "$label" failed');
    }
  }
}

/// Shared microphone-selection service — the tray menu and the status-bar
/// chip both route their clicks through this single instance so the two
/// surfaces can never drift apart in behavior.
final microphoneSelectionServiceProvider = Provider<MicrophoneSelectionService>(
  (ref) => MicrophoneSelectionService(
    persistLabel: (label) => ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(microphone: label)),
  ),
);
