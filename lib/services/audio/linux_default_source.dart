/// Name of the PulseAudio/PipeWire default source on Linux (#930).
///
/// With "System default" the `record` plugin runs `parecord` without a device,
/// so the sound server decides which source records. To suggest a different
/// microphone after silence, the app has to know that source, otherwise the
/// suggestion could name the silent device itself.
///
/// Why `pactl`: `record_linux` already lists its devices with `pactl`, so the
/// default source comes from the same tool and the same sound server (native
/// PulseAudio and `pipewire-pulse` answer identically), and no new dependency
/// is added. `pactl get-default-source` prints the source's `Name:`, which is
/// the `node.name` that `record_linux` uses as the device id. Older
/// pulseaudio-utils lack that subcommand; `pactl info` (`Default Source:`)
/// serves as fallback.
library;

import 'dart:async';
import 'dart:io';

import 'package:record/record.dart' show InputDevice;

/// Runs `pactl` with [args] and returns stdout, or `null` on any failure.
typedef PactlRunner = Future<String?> Function(List<String> args);

const _timeout = Duration(seconds: 1);

Future<String?> _runPactl(List<String> args) async {
  try {
    final result = await Process.run(
      'pactl',
      args,
      environment: {'LC_ALL': 'C'},
    ).timeout(_timeout);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  } on Exception {
    return null;
  }
}

/// The source name of the sound server's default source, or `null` when it
/// cannot be determined (no `pactl`, no server, timeout).
Future<String?> linuxDefaultSourceName({PactlRunner run = _runPactl}) async {
  final direct = (await run(const ['get-default-source']))?.trim();
  if (direct != null && direct.isNotEmpty) return direct;
  final info = await run(const ['info']);
  if (info == null) return null;
  for (final line in info.split('\n')) {
    final t = line.trim();
    if (t.startsWith('Default Source:')) {
      final name = t.substring('Default Source:'.length).trim();
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

/// The label of the device in [devices] whose id is [sourceName], or `null`.
/// A default source that is not a listed input (for example a monitor, which
/// the listing hides) gives `null`: then nothing is suggested.
String? labelForSourceName(String? sourceName, List<InputDevice> devices) {
  if (sourceName == null || sourceName.isEmpty) return null;
  for (final d in devices) {
    if (d.id == sourceName && d.label.isNotEmpty) return d.label;
  }
  return null;
}

/// Label of the device that records under "System default", or `null`.
Future<String?> linuxDefaultInputLabel(
  List<InputDevice> devices, {
  PactlRunner run = _runPactl,
}) async => labelForSourceName(await linuxDefaultSourceName(run: run), devices);
