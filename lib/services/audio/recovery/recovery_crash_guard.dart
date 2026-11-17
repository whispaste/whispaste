/// Crash-loop breaker for the transcription of interrupted recordings (#1783).
///
/// Since 1.5 the start transcribes recordings that a crash or quit left
/// behind (`recoverInterruptedRecordings`). A native fault inside that
/// transcription (STT engine, backend load, speech check) kills the process
/// before any Dart `catch` runs, the journal entry stays, and the next start
/// runs into the same crash again (#1780: five crashes in seven minutes).
///
/// Same pattern as `gpu_load_crash_guard.dart` and the speech-check marker in
/// `parakeet_speech_gate.dart`: a marker file is written to disk (flushed)
/// right before the native work and removed once it returned, on success and
/// on failure alike. A marker that is still there at the next use means the
/// earlier process died inside that work. Its recordings move to the crashed
/// record together with the app version, and the start does not transcribe
/// them again in that version. The recording itself stays in the journal, so
/// the history page offers it for a manual recovery; nothing is deleted.
/// A new app version may try once more, guarded the same way.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/app_info.dart' as app_info;
import '../../../core/logging/app_logger.dart';
import '../../path_service.dart' show appDataDir;

final _log = AppLogger('RecoveryCrashGuard');

class RecoveryCrashGuard {
  RecoveryCrashGuard({required this.dir, required this.appVersion});

  factory RecoveryCrashGuard.bundled() => RecoveryCrashGuard(
    dir: appDataDir,
    appVersion: () => app_info.appVersion,
  );

  /// The app data folder that holds the marker files.
  final String Function() dir;

  /// The running app version; a crash is only binding for this version.
  final String Function() appVersion;

  static const _attemptFileName = '.recovery_attempt';
  static const _crashedFileName = '.recovery_crashed';

  File get _attempt => File(p.join(dir(), _attemptFileName));
  File get _crashed => File(p.join(dir(), _crashedFileName));

  /// Recordings whose transcription runs in this process right now.
  final Set<String> _inFlight = {};

  bool _settled = false;

  /// Recordings found in a marker of an earlier process, not yet reported.
  List<String> _unreported = const [];

  /// Moves a marker left by an earlier process into the crashed record, once
  /// per process and before this process writes its own marker.
  void _settle() {
    if (_settled) return;
    _settled = true;
    try {
      if (!_attempt.existsSync()) return;
      final lines = _attempt.readAsLinesSync();
      final version = lines.isEmpty ? '' : lines.first.trim();
      final ids = [
        for (final line in lines.skip(1))
          if (line.trim().isNotEmpty) line.trim(),
      ];
      final crashed = _readCrashed();
      for (final id in ids) {
        crashed[id] = version;
      }
      // The marker goes only once the crash is on record: losing both would
      // let the next start run into the same crash again.
      if (ids.isNotEmpty && !_writeCrashed(crashed)) return;
      _attempt.deleteSync();
      _unreported = ids;
    } on Object catch (e) {
      _log.warning('Recovery crash marker unreadable: $e');
    }
  }

  /// The recordings an earlier process died on while transcribing them.
  /// Returns each crash once; empty when there was none.
  List<String> takePreviousCrash() {
    _settle();
    final ids = _unreported;
    _unreported = const [];
    return ids;
  }

  /// Whether the start must not transcribe [id] on its own: an attempt with
  /// this app version already crashed the app.
  bool skipsAutomatic(String id) {
    _settle();
    return _readCrashed()[id] == appVersion();
  }

  /// Whether an attempt on [id] crashed the app in any version. The history
  /// page marks such a recording as not processed automatically.
  bool crashedBefore(String id) {
    _settle();
    return _readCrashed().containsKey(id);
  }

  /// Drops crash records of recordings that are no longer interrupted
  /// (recovered, discarded), so the record never grows.
  void forgetAllExcept(Iterable<String> ids) {
    _settle();
    final crashed = _readCrashed();
    final keep = ids.toSet();
    final before = crashed.length;
    crashed.removeWhere((id, _) => !keep.contains(id));
    if (crashed.length != before) _writeCrashed(crashed);
  }

  /// Writes the marker before the native transcription of [id].
  void markAttempt(String id) {
    _settle();
    _inFlight.add(id);
    _writeAttempt();
  }

  /// Removes [id] from the marker once its transcription returned.
  void clearAttempt(String id) {
    _inFlight.remove(id);
    _writeAttempt();
  }

  /// Removes the marker on an orderly quit: a transcription that the user
  /// ended by quitting did not crash the app.
  void clearAllAttempts() {
    _inFlight.clear();
    _writeAttempt();
  }

  void _writeAttempt() {
    try {
      if (_inFlight.isEmpty) {
        if (_attempt.existsSync()) _attempt.deleteSync();
        return;
      }
      _attempt.parent.createSync(recursive: true);
      // flush: the marker must reach the disk before the risky native call,
      // otherwise a hard crash right after can leave no marker behind.
      _attempt.writeAsStringSync(
        [appVersion(), ..._inFlight].join('\n'),
        flush: true,
      );
    } on Object catch (e) {
      // Best-effort: without the marker this start only loses the crash-loop
      // protection, it never blocks the recovery itself.
      _log.warning('Recovery crash marker not written: $e');
    }
  }

  Map<String, String> _readCrashed() {
    try {
      if (!_crashed.existsSync()) return {};
      return {
        for (final line in _crashed.readAsLinesSync())
          if (line.contains('\t'))
            line.substring(0, line.indexOf('\t')): line
                .substring(line.indexOf('\t') + 1)
                .trim(),
      };
    } on Object catch (e) {
      _log.warning('Recovery crash record unreadable: $e');
      return {};
    }
  }

  bool _writeCrashed(Map<String, String> crashed) {
    try {
      if (crashed.isEmpty) {
        if (_crashed.existsSync()) _crashed.deleteSync();
        return true;
      }
      _crashed.parent.createSync(recursive: true);
      _crashed.writeAsStringSync(
        [for (final e in crashed.entries) '${e.key}\t${e.value}'].join('\n'),
        flush: true,
      );
      return true;
    } on Object catch (e) {
      _log.warning('Recovery crash record not written: $e');
      return false;
    }
  }
}

final recoveryCrashGuardProvider = Provider<RecoveryCrashGuard>(
  (ref) => RecoveryCrashGuard.bundled(),
);
