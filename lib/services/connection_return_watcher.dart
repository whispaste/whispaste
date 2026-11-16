import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import 'model_download_service.dart' show sttModels;

final _log = AppLogger('ConnectionWatcher');

/// Answers whether the model download host is reachable right now.
typedef ConnectionProbe = Future<bool> Function();

/// How often [ConnectionReturnWatcher] probes while it runs.
const Duration kConnectionProbeInterval = Duration(seconds: 10);

/// The default probe: resolves the host the speech models come from. A name
/// lookup is enough to tell "no network" from "network", costs a few bytes and
/// sends nothing to the server.
Future<bool> lookupModelHost() async {
  final host = Uri.parse(sttModels.first.url).host;
  try {
    final addresses = await InternetAddress.lookup(
      host,
    ).timeout(const Duration(seconds: 4));
    return addresses.isNotEmpty;
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

/// The probe [ConnectionReturnWatcher] uses in the app; tests replace it.
final connectionProbeProvider = Provider<ConnectionProbe>(
  (_) => lookupModelHost,
);

/// Tells once that the connection is back after a failed download, so the page
/// can offer a retry. It never starts a download itself: the user decides.
///
/// Probes every [interval] after [start]; the first successful probe calls
/// [onReturned] once and stops the timer. [stop] cancels it at any time and
/// silences a probe that is still running.
class ConnectionReturnWatcher {
  ConnectionReturnWatcher({
    required this.onReturned,
    ConnectionProbe? probe,
    this.interval = kConnectionProbeInterval,
  }) : _probe = probe ?? lookupModelHost;

  final void Function() onReturned;
  final Duration interval;
  final ConnectionProbe _probe;

  Timer? _timer;
  bool _probing = false;

  /// Whether the timer is armed.
  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    // A slow probe must not pile up with the next tick.
    if (_probing) return;
    _probing = true;
    try {
      final reachable = await _probe();
      // Stopped while the probe ran: nobody listens any more.
      if (!reachable || _timer == null) return;
      stop();
      onReturned();
    } on Object catch (e) {
      _log.warning('Connection probe failed', e);
    } finally {
      _probing = false;
    }
  }
}
