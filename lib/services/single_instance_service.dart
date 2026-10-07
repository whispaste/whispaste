import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import 'path_service.dart' as paths;

/// What a launch asks of the running (primary) WhisPaste instance.
///
/// A plain launch only brings the existing window to the front. The
/// remote-control flags let shortcuts, scripts and launchers (GNOME/KDE
/// custom shortcuts on Wayland, Raycast/Alfred, window managers) drive the
/// recording without the opt-in automation API: `whispaste --toggle`
/// starts/stops a dictation, `whispaste --cancel` discards the running one.
enum InstanceCommand {
  /// Plain launch — focus the running instance's window.
  focus,

  /// `--toggle` — start a dictation, or stop the running one.
  toggle,

  /// `--cancel` — discard the running dictation (no-op when idle).
  cancel;

  /// Parses the process arguments. Unrelated arguments are ignored; if both
  /// flags are given, the first one wins.
  static InstanceCommand fromArgs(List<String> args) {
    for (final arg in args) {
      if (arg == '--toggle') return toggle;
      if (arg == '--cancel') return cancel;
    }
    return focus;
  }
}

/// Ensures only one instance of WhisPaste runs at a time.
///
/// Uses an exclusive file lock in the app data directory. If the lock is
/// acquired, this is the primary instance. If it's already held, another
/// instance is running — we drop a signal file for it to pick up and exit.
/// The signal carries the second launch's [InstanceCommand], so the same
/// channel forwards `--toggle`/`--cancel` to the running instance.
///
/// Deliberately network-free: an earlier version used a loopback
/// `ServerSocket` for this, which required the `com.apple.security.network.
/// server` sandbox entitlement. Apple App Review rejected the Mac App Store
/// submission over that entitlement having no reviewer-visible listening
/// functionality — do not reintroduce a socket here.
class SingleInstanceService {
  static const String _dirName = 'single_instance';
  static const String _lockFileName = 'instance.lock';
  static const String _signalFileName = 'focus.signal';
  static const Duration _debounce = Duration(milliseconds: 400);
  static const Duration _rearmDelay = Duration(seconds: 2);

  static final _log = AppLogger('SingleInstance');

  static RandomAccessFile? _lock;
  static StreamSubscription<FileSystemEvent>? _watch;
  static StreamSubscription<ProcessSignal>? _toggleSignal;
  static Timer? _rearmTimer;
  static final Map<InstanceCommand, DateTime> _lastSignalHandled = {};
  static String? _lastSignalContent;
  static void Function(InstanceCommand command)? _onRemoteCommand;
  static final List<InstanceCommand> _pendingRemoteCommands = [];

  /// Time source for the debounce window; tests pin it instead of racing
  /// the wall clock.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Overrides the lock directory for tests, isolating them from the real
  /// app data path. `null` (the default) uses [paths.appDataDir].
  @visibleForTesting
  static String? lockDirOverride;

  /// Callback invoked when a second instance requests focus.
  static void Function()? onSecondInstanceLaunched;

  /// Handler for [InstanceCommand.toggle]/[InstanceCommand.cancel] requests.
  ///
  /// Commands that arrive while no handler is registered (the recording
  /// pipeline is wired up only after the first frame) are queued and
  /// delivered, in order, as soon as one is set.
  static set onRemoteCommand(void Function(InstanceCommand command)? handler) {
    _onRemoteCommand = handler;
    if (handler == null) return;
    final pending = List.of(_pendingRemoteCommands);
    _pendingRemoteCommands.clear();
    pending.forEach(handler);
  }

  /// Attempt to claim the single-instance lock.
  /// Returns `true` if this is the primary instance.
  /// Returns `false` if another instance is already running (and was signalled
  /// with [command]).
  ///
  /// When this process becomes the primary and [command] is
  /// [InstanceCommand.toggle], the toggle is queued for [onRemoteCommand]:
  /// `whispaste --toggle` with no running instance starts the app and then
  /// starts a dictation. Handling a primary [InstanceCommand.cancel] (nothing
  /// to cancel) is the caller's decision.
  static Future<bool> ensureSingleInstance({
    InstanceCommand command = InstanceCommand.focus,
  }) async {
    // Already holding the lock — we ARE the primary. Never open a second
    // handle: on POSIX, closing any file descriptor for a file drops every
    // advisory lock this process holds on it, even ones held via other
    // handles, so a second open/close here would silently release the lock
    // out from under the first.
    if (_lock != null) return true;

    late final String dir;
    try {
      dir = lockDirOverride ?? p.join(paths.appDataDir(), _dirName);
      await Directory(dir).create(recursive: true);
    } catch (e) {
      // Can't even resolve/create the lock directory — fail open. Treating
      // this as "secondary" would exit(0) on every launch (see main.dart),
      // permanently bricking the app over a transient FS/permission issue.
      _log.warning('Cannot prepare single-instance lock dir, failing open: $e');
      return true;
    }

    final lockFile = File(p.join(dir, _lockFileName));
    late final RandomAccessFile raf;
    try {
      // FileMode.append (never `write`): opening for write would truncate
      // the file, which can itself fail against a locked byte range on
      // Windows.
      raf = await lockFile.open(mode: FileMode.append);
    } catch (e) {
      // Separate from the lock() try/catch below on purpose: open() can
      // throw the same FileSystemException class as a held lock (e.g.
      // permission errors, a virtualized MSIX path), and conflating the two
      // would misclassify "can't even open the file" as "secondary" — exit
      // on every launch. Fail open here too, same reasoning as above.
      _log.warning('Cannot open single-instance lock file, failing open: $e');
      return true;
    }

    final lockedAt = DateTime.now();
    try {
      // Non-blocking: throws FileSystemException immediately if another
      // process already holds it, instead of waiting.
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      _log.info('Another instance detected, sending ${command.name} signal');
      await _writeSignal(dir, command);
      return false;
    }

    _lock = raf;
    _log.info('Single instance lock acquired at $dir');
    if (command == InstanceCommand.toggle) _dispatchRemoteCommand(command);
    _startWatching(dir);
    _watchToggleSignal();
    await _catchUpOnMissedSignal(dir, lockedAt);
    return true;
  }

  /// Releases the instance lock without exiting — used right before a
  /// deliberate self-relaunch (see `MacOSLifecycleChannel.restart`). Without
  /// this, the freshly-spawned replacement process starts while this process
  /// still holds the lock, loses `ensureSingleInstance()`, and exits itself
  /// as a "second instance" — the old process then also quits on schedule,
  /// so the app closes entirely instead of restarting. Safe to call even if
  /// the lock was never acquired (e.g. this is already a secondary instance).
  static Future<void> release() async {
    _rearmTimer?.cancel();
    _rearmTimer = null;
    await _watch?.cancel();
    _watch = null;
    await _toggleSignal?.cancel();
    _toggleSignal = null;
    final raf = _lock;
    _lock = null;
    _lastSignalHandled.clear();
    _lastSignalContent = null;
    _pendingRemoteCommands.clear();
    if (raf == null) return;
    try {
      await raf.unlock();
    } catch (e) {
      // Already released (e.g. Windows reporting the segment as unlocked) —
      // closing below still guarantees the OS-level lock is gone.
      _log.debug('unlock() no-op, already released: $e');
    }
    await raf.close();
    _log.info('Single instance lock released (relaunch in progress)');
  }

  /// Writes the signal for the primary instance to pick up.
  /// Kept in a separate file from the lock file so a secondary instance can
  /// always write it, even though the lock file itself may hold an exclusive
  /// (and on Windows, mandatory) lock.
  ///
  /// Format: `<ISO-8601 timestamp> <command>`. The unique timestamp keeps
  /// every signal distinct (see [_onSignal]); an older primary that predates
  /// the command suffix still treats any new content as a focus request.
  static Future<void> _writeSignal(String dir, InstanceCommand command) async {
    try {
      final file = File(p.join(dir, _signalFileName));
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} ${command.name}',
        flush: true,
      );
    } catch (e) {
      _log.warning('Failed to signal existing instance: $e');
    }
  }

  /// Watches the lock directory for the signal file being (re)written by a
  /// secondary instance. Watches the directory rather than the file itself —
  /// Windows' `ReadDirectoryChangesW` backing only supports watching
  /// directories, not individual files.
  static void _startWatching(String dir) {
    _watch = Directory(dir)
        .watch(recursive: false)
        .listen(
          (event) {
            if (event is FileSystemDeleteEvent) return;
            if (p.basename(event.path) != _signalFileName) return;
            unawaited(_onSignal(dir));
          },
          onError: (Object e) {
            _log.warning('Single-instance watcher error: $e');
            _rearmWatcher(dir);
          },
          onDone: () => _rearmWatcher(dir),
          cancelOnError: true,
        );
  }

  /// Unix only: `SIGUSR2` toggles the recording, same as `--toggle` (e.g.
  /// `pkill -USR2 -x whispaste`) but without booting a second process.
  /// Checked safe: neither the Dart VM, the Flutter engine nor GTK/GLib
  /// install a SIGUSR2 handler of their own. Armed only once this process
  /// holds the lock, so only the primary reacts; before that (early startup)
  /// the signal's default action still terminates the process, which is why
  /// `--toggle` stays the documented, robust way.
  static void _watchToggleSignal() {
    if (Platform.isWindows) return;
    try {
      _toggleSignal = ProcessSignal.sigusr2.watch().listen(
        (_) => _fireDebounced(InstanceCommand.toggle),
      );
    } on SignalException catch (e) {
      _log.warning('SIGUSR2 toggle unavailable: $e');
    }
  }

  /// Re-arms the directory watcher after its stream ends (e.g. a Windows
  /// change-buffer overflow) — only while we still hold the lock, so this
  /// never races a concurrent [release].
  static void _rearmWatcher(String dir) {
    _rearmTimer?.cancel();
    _rearmTimer = Timer(_rearmDelay, () {
      if (_lock != null) _startWatching(dir);
    });
  }

  /// Closes the race between the lock being acquired and the watcher being
  /// armed: if a signal file already exists and was written at/after
  /// [lockedAt], treat it as a signal we would otherwise have missed.
  static Future<void> _catchUpOnMissedSignal(
    String dir,
    DateTime lockedAt,
  ) async {
    try {
      final file = File(p.join(dir, _signalFileName));
      if (!await file.exists()) return;
      final modified = await file.lastModified();
      // 1s slack for coarse filesystem mtime granularity.
      if (!modified.isBefore(lockedAt.subtract(const Duration(seconds: 1)))) {
        await _onSignal(dir);
      }
    } catch (e) {
      // No signal to catch up on — e.g. a benign race deleting the file
      // between the exists() check and lastModified().
      _log.debug('No missed focus signal to catch up on: $e');
    }
  }

  /// Handles one directory event for the signal file. Every secondary
  /// instance writes a fresh timestamp, so the content identifies the
  /// signal: Windows can report a single write as several events, and on a
  /// loaded machine those can land further apart than [_debounce] — they
  /// all read the same content and focus the window only once.
  static Future<void> _onSignal(String dir) async {
    final String content;
    try {
      content = (await File(
        p.join(dir, _signalFileName),
      ).readAsString()).trim();
    } catch (e) {
      // Deleted or still locked mid-write — a later event re-reads it.
      _log.debug('Focus signal not readable yet: $e');
      return;
    }
    // Empty: the event fired between truncate and write.
    if (content.isEmpty || content == _lastSignalContent) return;
    _lastSignalContent = content;
    _fireDebounced(_parseSignalCommand(content));
  }

  /// Reads the command suffix of a signal. Anything unrecognised — including
  /// a bare timestamp from an older secondary — is a focus request.
  static InstanceCommand _parseSignalCommand(String content) {
    final suffix = content.split(' ').last;
    for (final command in InstanceCommand.values) {
      if (command.name == suffix) return command;
    }
    return InstanceCommand.focus;
  }

  /// Collapses distinct signals from secondary instances launched in quick
  /// succession (e.g. a double-click on the app icon) into one. Debounced
  /// per command, so a focus request never swallows a following toggle.
  static void _fireDebounced(InstanceCommand command) {
    final focusCb = onSecondInstanceLaunched;
    if (command == InstanceCommand.focus && focusCb == null) return;
    final now = clock();
    final last = _lastSignalHandled[command];
    if (last != null && now.difference(last) < _debounce) return;
    _lastSignalHandled[command] = now;
    _log.info('Received ${command.name} signal from second instance');
    if (command == InstanceCommand.focus) {
      focusCb!();
    } else {
      _dispatchRemoteCommand(command);
    }
  }

  static void _dispatchRemoteCommand(InstanceCommand command) {
    final handler = _onRemoteCommand;
    if (handler == null) {
      _pendingRemoteCommands.add(command);
      return;
    }
    handler(command);
  }
}
