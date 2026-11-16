import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart side of the native hang watchdog (#338).
///
/// Each runner (macOS Swift, Windows C++, Linux C++/GTK) runs a watchdog
/// thread with the same contract:
///
/// * Dart arms it with `arm` once the app is up (so the start phase never
///   counts), passing the directory for the marker file.
/// * Dart then sends `beat` every [beatInterval]. The call is answered on the
///   platform thread, so a beat proves that both the UI isolate and the main
///   thread still run.
/// * No beat for [threshold] (20 s) means a hang. A watchdog tick that came
///   much later than planned means the machine slept; the watchdog then
///   grants a grace period instead of counting the sleep as a hang.
/// * On a hang the runner writes [markerFileName] into the marker directory
///   and restarts the app (new instance after the old one exited), at most
///   once per 10 minutes. Within the cooldown it only writes the marker.
///
/// On the next start [consumeHangMarker] reads and deletes the marker; the
/// app then shows a calm notice and sends one crash event to Sentry.
class HangWatchdogClient {
  HangWatchdogClient({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(hangWatchdogChannel);

  /// The app's one client: the shell starts it, every quit path stops it
  /// first (`runGracefulEngineShutdown`), so a slow teardown never counts
  /// as a hang and restarts an app the user just quit.
  static final instance = HangWatchdogClient();

  // Unique name on purpose: the parity guard resolves channel constants by
  // name across all files, so a generic `channelName` would capture other
  // hosts' MethodChannel(channelName) parameters.
  static const hangWatchdogChannel = 'com.whispaste.hang_watchdog';
  static const beatInterval = Duration(seconds: 2);
  static const threshold = Duration(seconds: 20);

  final MethodChannel _channel;
  Timer? _timer;

  bool get isRunning => _timer != null;

  /// Arms the native watchdog and starts the heartbeat. Safe to call twice.
  Future<void> start({required String markerDirectory}) async {
    if (_timer != null) return;
    try {
      await _channel.invokeMethod<void>('arm', {
        'markerDir': markerDirectory,
        'thresholdMs': threshold.inMilliseconds,
      });
    } on MissingPluginException {
      return; // tests, or a runner without the host
    } on PlatformException {
      return;
    }
    _timer = Timer.periodic(beatInterval, (_) => _beat());
  }

  void _beat() {
    unawaited(_channel.invokeMethod<void>('beat').catchError((Object _) {}));
  }

  /// Stops the heartbeat and disarms the watchdog (orderly quit).
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    // Nothing armed, or the runner is already tearing down: either way the
    // watchdog no longer counts.
    await _channel
        .invokeMethod<void>('disarm')
        .then<void>((_) {}, onError: (Object _) {});
  }

  /// Blocks the UI isolate on purpose so the watchdog fires. Only reachable
  /// in debug and profile builds; release builds compile it to a no-op.
  static void debugBlockUiIsolate(Duration duration) {
    if (kReleaseMode) return;
    sleep(duration);
  }
}

/// File the runners write after a detected hang (key=value lines).
const markerFileName = 'hang_watchdog_marker';

/// What the runner recorded about a hang of the previous session.
@immutable
class HangMarker {
  const HangMarker({required this.restarted, required this.stalledMs});

  /// True when the watchdog restarted the app, false when the restart
  /// cooldown only allowed the diagnosis.
  final bool restarted;

  /// How long the main thread had been silent when the watchdog fired.
  final int stalledMs;

  static HangMarker? parse(String text) {
    final values = <String, String>{};
    for (final line in text.split('\n')) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      values[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    final stalled = int.tryParse(values['stalled_ms'] ?? '');
    if (stalled == null) return null;
    return HangMarker(
      restarted: values['restarted'] == '1',
      stalledMs: stalled,
    );
  }
}

/// Reads and deletes the marker in [directory]; null when there is none or
/// it is unreadable. Deleting first makes sure the notice shows only once.
Future<HangMarker?> consumeHangMarker(String directory) async {
  final file = File('$directory${Platform.pathSeparator}$markerFileName');
  try {
    if (!await file.exists()) return null;
    final text = await file.readAsString();
    await file.delete();
    return HangMarker.parse(text);
  } on FileSystemException {
    return null;
  }
}
