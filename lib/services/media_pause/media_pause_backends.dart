/// Platform backends of [MediaPauseBackend] and [MediaDuckBackend]
/// (#563, #1511).
///
/// Windows and macOS talk to a native host over [mediaPauseChannelName]
/// (contract below); Linux speaks MPRIS on the session bus directly and turns
/// streams down with `pactl`.
library;

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';

import '../../core/logging/app_logger.dart';
import 'media_pause_controller.dart';

final _log = AppLogger('MediaPause');

/// Channel contract of the native hosts (Windows media_pause_host.cpp,
/// macOS MediaPauseHost.swift):
///  * `isAvailable` -> `bool`
///  * `pauseIfPlaying` -> `'paused'` | `'nothing'` | `'unavailable'`
///  * `resumePaused` -> `null` (resumes only what `pauseIfPlaying` paused)
///  * `duckAvailable` -> `bool`
///  * `playingVolumes` -> `List<Map>` with `id` (`String`) and `levels`
///    (`List<double>`, `0..1`) of everything audible except WhisPaste itself
///  * `setVolumes` (argument: the same list) -> `null`; skips vanished ids
///  * `requestPlayerAccess` (macOS only) -> `int`: asks macOS once for the
///    automation permission of each supported player that runs, returns how
///    many may be controlled
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
      return MediaPauseOutcome.noAnswer;
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

/// Volume half of the native hosts (same channel as the pause).
class ChannelMediaDuckBackend implements MediaDuckBackend {
  ChannelMediaDuckBackend([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(mediaPauseChannelName);

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel
              .invokeMethod<bool>('duckAvailable')
              .timeout(mediaPauseCallTimeout) ??
          false;
    } on PlatformException catch (e) {
      _log.warning('duckAvailable failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  @override
  Future<List<DuckTarget>> playingTargets() async {
    final raw = await _channel
        .invokeMethod<List<Object?>>('playingVolumes')
        .timeout(mediaPauseCallTimeout);
    return [for (final e in raw ?? const <Object?>[]) ?DuckTarget.fromJson(e)];
  }

  @override
  Future<void> setLevels(List<DuckTarget> targets) async {
    if (targets.isEmpty) return;
    await _channel
        .invokeMethod<void>('setVolumes', [for (final t in targets) t.toJson()])
        .timeout(mediaPauseCallTimeout);
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

/// Runs `pactl` with the arguments and returns stdout, or `null` on failure.
typedef PactlCall = Future<String?> Function(List<String> args);

Future<String?> _runPactl(List<String> args) async {
  try {
    final result = await Process.run(
      'pactl',
      args,
      environment: {'LC_ALL': 'C'},
    ).timeout(mediaPauseCallTimeout);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  } on Exception {
    return null;
  }
}

/// One playback stream from `pactl list sink-inputs`.
class PactlSinkInput {
  const PactlSinkInput({
    required this.index,
    required this.corked,
    required this.rawVolumes,
    this.processId,
    this.applicationName,
  });

  final int index;
  final bool corked;

  /// Per-channel volume in PulseAudio units (`65536` = 100 %).
  final List<int> rawVolumes;
  final int? processId;

  /// `application.name`: the sound server keys the volume it hands on to an
  /// app's next stream by it.
  final String? applicationName;

  /// Opaque target id: the stream index plus its process and app name, so a
  /// crash restore never touches another stream that reused the index.
  String get targetId => '$index:${processId ?? ''}:${applicationName ?? ''}';
}

/// Parses `LC_ALL=C pactl list sink-inputs` (PulseAudio and pipewire-pulse
/// print the same layout).
List<PactlSinkInput> parsePactlSinkInputs(String output) {
  final inputs = <PactlSinkInput>[];
  int? index;
  var corked = false;
  var volumes = <int>[];
  int? pid;
  String? name;
  void flush() {
    if (index != null && volumes.isNotEmpty) {
      inputs.add(
        PactlSinkInput(
          index: index,
          corked: corked,
          rawVolumes: volumes,
          processId: pid,
          applicationName: name,
        ),
      );
    }
  }

  final rawVolume = RegExp(r':\s*(\d+)\s*/');
  final processId = RegExp(r'application\.process\.id\s*=\s*"(\d+)"');
  final appName = RegExp(r'^application\.name\s*=\s*"(.*)"$');
  for (final line in output.split('\n')) {
    final t = line.trim();
    if (t.startsWith('Sink Input #')) {
      flush();
      index = int.tryParse(t.substring('Sink Input #'.length).trim());
      corked = false;
      volumes = <int>[];
      pid = null;
      name = null;
    } else if (t.startsWith('Corked:')) {
      corked = t.substring('Corked:'.length).trim() == 'yes';
    } else if (t.startsWith('Volume:')) {
      volumes = [
        for (final m in rawVolume.allMatches(t.substring('Volume'.length)))
          int.parse(m.group(1)!),
      ];
    } else if (processId.firstMatch(t) case final m?) {
      pid = int.tryParse(m.group(1)!);
    } else if (appName.firstMatch(t) case final m?) {
      name = m.group(1);
    }
  }
  flush();
  return inputs;
}

/// PulseAudio volume units per 100 %.
const pulseVolumeNorm = 65536;

/// Linux: turns down every uncorked playback stream except WhisPaste's own
/// and restores each stream's exact per-channel volume afterwards.
class PactlMediaDuckBackend implements MediaDuckBackend {
  PactlMediaDuckBackend({PactlCall? run, int? ownPid})
    : _run = run ?? _runPactl,
      _ownPid = ownPid ?? pid;

  final PactlCall _run;
  final int _ownPid;

  Future<List<PactlSinkInput>?> _list() async {
    final out = await _run(const ['list', 'sink-inputs']);
    return out == null ? null : parsePactlSinkInputs(out);
  }

  @override
  Future<bool> isAvailable() async => await _run(const ['info']) != null;

  @override
  Future<List<DuckTarget>> playingTargets() async {
    final inputs = await _list() ?? const [];
    return [
      for (final i in inputs)
        if (!i.corked && i.processId != _ownPid)
          DuckTarget(i.targetId, [
            for (final v in i.rawVolumes) v / pulseVolumeNorm,
          ]),
    ];
  }

  @override
  Future<void> setLevels(List<DuckTarget> targets) async {
    if (targets.isEmpty) return;
    final inputs = await _list();
    if (inputs == null) throw const PactlUnavailable();
    final present = {for (final i in inputs) i.targetId: i};
    final named = {for (final t in targets) t.id};
    final taken = <int>{};
    for (final t in targets) {
      var input = present[t.id];
      if (input != null && input.rawVolumes.length != t.levels.length) {
        continue;
      }
      // The stream ended. PipeWire and PulseAudio hand the volume last set
      // for an app to its next stream, so a player that opened a new stream
      // while ducked (next track, new video) would stay quiet for good. Such
      // a successor of the same app (name or process) that carries exactly
      // the ducked volume gets the old volume back; anything else is left
      // alone.
      input ??= _successor(t, inputs, named, taken);
      if (input == null) continue;
      taken.add(input.index);
      await _run([
        'set-sink-input-volume',
        '${input.index}',
        // Integers are raw volume units in pactl, so a restore is exact.
        for (final l in t.levels) '${(l * pulseVolumeNorm).round()}',
      ]);
    }
  }

  static PactlSinkInput? _successor(
    DuckTarget original,
    List<PactlSinkInput> inputs,
    Set<String> named,
    Set<int> taken,
  ) {
    // `index:pid:name`; the name may itself contain colons.
    final parts = original.id.split(':');
    final pid = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final name = parts.length > 2 ? parts.sublist(2).join(':') : '';
    if (pid == null && name.isEmpty) return null;
    final ducked = [
      for (final l in original.levels) (l * duckFactor * pulseVolumeNorm),
    ];
    for (final i in inputs) {
      final sameApp =
          (pid != null && i.processId == pid) ||
          (name.isNotEmpty && i.applicationName == name);
      if (!sameApp ||
          named.contains(i.targetId) ||
          taken.contains(i.index) ||
          i.rawVolumes.length != ducked.length) {
        continue;
      }
      // The sound server may round once when it hands the volume on.
      final matches = Iterable<int>.generate(
        ducked.length,
      ).every((c) => (i.rawVolumes[c] - ducked[c]).abs() <= 2);
      if (matches) return i;
    }
    return null;
  }
}

class PactlUnavailable implements Exception {
  const PactlUnavailable();

  @override
  String toString() => 'pactl is not reachable';
}

/// Seam for tests: widget tests must not open the real platform channel (its
/// call timeout would leave a pending timer). `test/flutter_test_config.dart`
/// swaps in the unavailable backend.
MediaPauseBackend Function() mediaPauseBackendFactory =
    createPlatformMediaPauseBackend;

MediaPauseBackend createPlatformMediaPauseBackend() {
  // macOS (#1511): no system-wide media control is open to apps since 15.4
  // (#1254), so the host pauses the supported players (Music, Spotify) by
  // Apple Events and reports "unavailable" for anything else.
  if (Platform.isWindows || Platform.isMacOS) return ChannelMediaPauseBackend();
  if (Platform.isLinux) return MprisMediaPauseBackend();
  return const UnavailableMediaPauseBackend();
}

/// Seam for tests, like [mediaPauseBackendFactory].
MediaDuckBackend Function() mediaDuckBackendFactory =
    createPlatformMediaDuckBackend;

MediaDuckBackend createPlatformMediaDuckBackend() {
  if (Platform.isWindows || Platform.isMacOS) return ChannelMediaDuckBackend();
  if (Platform.isLinux) return PactlMediaDuckBackend();
  return const UnavailableMediaDuckBackend();
}
