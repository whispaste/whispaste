/// Platform backends of [MediaPauseBackend] (#563).
///
/// Windows talks to a native host over [mediaPauseChannelName]
/// (contract below); Linux speaks MPRIS on the session bus directly.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'media_pause_controller.dart';

final _log = AppLogger('MediaPause');

/// Channel contract of the native host (Windows media_pause_host.cpp):
///  * `isAvailable` -> `bool`
///  * `pauseIfPlaying` -> `'paused'` | `'nothing'` | `'unavailable'`
///  * `resumePaused` -> `null` (resumes only what `pauseIfPlaying` paused)
const mediaPauseChannelName = 'com.whispaste.media_pause';

/// Upper bound for any native or bus call so a wedged player cannot hold the
/// queue (and with it a later resume) forever.
const mediaPauseCallTimeout = Duration(seconds: 3);

class ChannelMediaPauseBackend implements MediaPauseBackend {
  ChannelMediaPauseBackend([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(mediaPauseChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel
              .invokeMethod<bool>('isAvailable')
              .timeout(mediaPauseCallTimeout) ??
          false;
    } on PlatformException catch (e) {
      _log.warning('isAvailable failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<MediaPauseOutcome> pauseIfPlaying() async {
    try {
      final raw = await _channel
          .invokeMethod<String>('pauseIfPlaying')
          .timeout(mediaPauseCallTimeout);
      return switch (raw) {
        'paused' => MediaPauseOutcome.paused,
        'nothing' => MediaPauseOutcome.nothingPlaying,
        _ => MediaPauseOutcome.unavailable,
      };
    } on PlatformException catch (e) {
      _log.warning('pauseIfPlaying failed: $e');
      return MediaPauseOutcome.unavailable;
    } on MissingPluginException {
      return MediaPauseOutcome.unavailable;
    } on TimeoutException {
      return MediaPauseOutcome.unavailable;
    }
  }

  @override
  Future<void> resumePaused() async {
    try {
      await _channel
          .invokeMethod<void>('resumePaused')
          .timeout(mediaPauseCallTimeout);
    } on PlatformException catch (e) {
      _log.warning('resumePaused failed: $e');
    } on MissingPluginException {
      _log.debug('resumePaused: no host, nothing was paused');
    } on TimeoutException {
      _log.warning('resumePaused timed out');
    }
  }
}

/// The three MPRIS operations the Linux backend needs; the bus-free seam for
/// tests.
abstract interface class MprisBus {
  /// Bus names of all running MPRIS players.
  Future<List<String>> listPlayers();

  /// `PlaybackStatus` of [player]: `Playing`, `Paused` or `Stopped`.
  Future<String?> playbackStatus(String player);

  Future<void> pause(String player);

  Future<void> play(String player);

  /// Whether a session bus is reachable at all.
  Future<bool> isReachable();
}

const _mprisPrefix = 'org.mpris.MediaPlayer2.';
const _mprisPath = '/org/mpris/MediaPlayer2';
const _mprisPlayerIface = 'org.mpris.MediaPlayer2.Player';

class DBusMprisBus implements MprisBus {
  DBusMprisBus({DBusClient Function()? sessionBus})
    : _sessionBus = sessionBus ?? DBusClient.session;

  final DBusClient Function() _sessionBus;

  Future<T> _withBus<T>(Future<T> Function(DBusClient bus) body) async {
    final bus = _sessionBus();
    try {
      return await body(bus).timeout(mediaPauseCallTimeout);
    } finally {
      unawaited(bus.close());
    }
  }

  DBusRemoteObject _player(DBusClient bus, String name) =>
      DBusRemoteObject(bus, name: name, path: DBusObjectPath(_mprisPath));

  @override
  Future<bool> isReachable() async {
    try {
      await _withBus((bus) => bus.listNames());
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> listPlayers() => _withBus((bus) async {
    final names = await bus.listNames();
    return names.where((n) => n.startsWith(_mprisPrefix)).toList();
  });

  @override
  Future<String?> playbackStatus(String player) => _withBus((bus) async {
    final value = await _player(
      bus,
      player,
    ).getProperty(_mprisPlayerIface, 'PlaybackStatus');
    return value is DBusString ? value.value : null;
  });

  @override
  Future<void> pause(String player) => _withBus((bus) async {
    await _player(bus, player).callMethod(
      _mprisPlayerIface,
      'Pause',
      const [],
      replySignature: DBusSignature(''),
    );
  });

  @override
  Future<void> play(String player) => _withBus((bus) async {
    await _player(bus, player).callMethod(
      _mprisPlayerIface,
      'Play',
      const [],
      replySignature: DBusSignature(''),
    );
  });
}

/// Linux: pauses every MPRIS player whose status is `Playing` and resumes
/// exactly those afterwards.
class MprisMediaPauseBackend implements MediaPauseBackend {
  MprisMediaPauseBackend([MprisBus? bus]) : _bus = bus ?? DBusMprisBus();

  final MprisBus _bus;
  final List<String> _paused = [];

  @override
  Future<bool> isAvailable() => _bus.isReachable();

  @override
  Future<MediaPauseOutcome> pauseIfPlaying() async {
    final List<String> players;
    try {
      players = await _bus.listPlayers();
    } catch (e) {
      _log.warning('Listing MPRIS players failed: $e');
      return MediaPauseOutcome.unavailable;
    }
    for (final player in players) {
      try {
        if (await _bus.playbackStatus(player) != 'Playing') continue;
        await _bus.pause(player);
        _paused.add(player);
      } catch (e) {
        _log.warning('Pausing $player failed: $e');
      }
    }
    return _paused.isEmpty
        ? MediaPauseOutcome.nothingPlaying
        : MediaPauseOutcome.paused;
  }

  @override
  Future<void> resumePaused() async {
    final players = List<String>.of(_paused);
    _paused.clear();
    for (final player in players) {
      try {
        // A player that exited meanwhile has no status any more: skip it,
        // and never start one the user paused during the dictation.
        if (await _bus.playbackStatus(player) != 'Paused') continue;
        await _bus.play(player);
      } catch (e) {
        _log.warning('Resuming $player failed: $e');
      }
    }
  }
}

/// Seam for tests: widget tests must not open the real platform channel (its
/// call timeout would leave a pending timer). `test/flutter_test_config.dart`
/// swaps in the unavailable backend.
MediaPauseBackend Function() mediaPauseBackendFactory =
    createPlatformMediaPauseBackend;

MediaPauseBackend createPlatformMediaPauseBackend() {
  // macOS: Apple blocks third-party media control since 15.4 and the old API
  // was private; no backend, so no media command is ever sent (#1254).
  if (Platform.isWindows) return ChannelMediaPauseBackend();
  if (Platform.isLinux) return MprisMediaPauseBackend();
  return const UnavailableMediaPauseBackend();
}
