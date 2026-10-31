/// Logs the transitions of macOS secure input (F35-8): "on" with the holder,
/// and "off". Only changes are logged, so a quiet system writes nothing.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../desktop_paste/desktop_paste_controller.dart';

final _log = AppLogger('SecureInput');

/// One flag read in the native host every 2 s. The holder is only looked up
/// on the change to "on", never on a timer tick.
const Duration kSecureInputPollInterval = Duration(seconds: 2);

const Duration _lookupTimeout = Duration(seconds: 2);

enum SecureInputTransition { on, off }

/// Turns a series of samples into transitions. The first sample counts as a
/// change only when secure input is already on, so a normal start is silent.
class SecureInputTransitionTracker {
  bool? _last;

  SecureInputTransition? observe(bool active) {
    final previous = _last;
    _last = active;
    if (previous == active) return null;
    if (previous == null && !active) return null;
    return active ? SecureInputTransition.on : SecureInputTransition.off;
  }
}

/// Polls [SecureInputProbe] and writes one line per transition. Unsupported
/// samples are ignored and never count as a change.
class SecureInputLogMonitor {
  SecureInputLogMonitor(this._probe, {void Function(String message)? log})
    : _write = log ?? _log.info;

  final SecureInputProbe _probe;
  final void Function(String message) _write;
  final SecureInputTransitionTracker _tracker = SecureInputTransitionTracker();

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  void start() {
    _stopped = false;
    _timer ??= Timer.periodic(
      kSecureInputPollInterval,
      (_) => unawaited(tick()),
    );
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> tick() async {
    if (_busy) return;
    _busy = true;
    try {
      final state = await _probe.secureInputState().timeout(_lookupTimeout);
      if (_stopped || state == SecureInputState.unsupported) return;
      final transition = _tracker.observe(state == SecureInputState.active);
      switch (transition) {
        case SecureInputTransition.on:
          _write(await _describeHolder());
        case SecureInputTransition.off:
          _write('Secure input off.');
        case null:
          break;
      }
    } on Object catch (e) {
      _log.debug('Secure input poll failed', e);
    } finally {
      _busy = false;
    }
  }

  Future<String> _describeHolder() async {
    SecureInputHolder? holder;
    try {
      holder = await _probe.secureInputHolder().timeout(_lookupTimeout);
    } on Object {
      holder = null;
    }
    if (holder == null) return 'Secure input on, holder unknown.';
    final who = holder.name ?? holder.bundleId ?? 'an unnamed app';
    final pid = holder.pid == null ? '' : ' (pid ${holder.pid})';
    return 'Secure input on, held by $who$pid.';
  }
}

/// Started once per process on macOS only. Other platforms and builds without
/// a paste controller (Mac App Store) get no timer at all.
final secureInputLogProvider = Provider<SecureInputLogMonitor?>((ref) {
  if (!Platform.isMacOS) return null;
  final controller = ref.read(desktopPasteControllerProvider);
  if (controller is! SecureInputProbe) return null;
  final monitor = SecureInputLogMonitor(controller as SecureInputProbe)
    ..start();
  ref.onDispose(monitor.stop);
  return monitor;
});
