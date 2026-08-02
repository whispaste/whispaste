import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import 'path_service.dart' as paths;

/// Ensures only one instance of WhisPaste runs at a time.
///
/// Uses an exclusive file lock in the app data directory. If the lock is
/// acquired, this is the primary instance. If it's already held, another
/// instance is running — we drop a signal file for it to pick up and exit.
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
  static Timer? _rearmTimer;
  static DateTime? _lastSignalHandled;

  /// Overrides the lock directory for tests, isolating them from the real
  /// app data path. `null` (the default) uses [paths.appDataDir].
  @visibleForTesting
  static String? lockDirOverride;

  /// Callback invoked when a second instance requests focus.
  static void Function()? onSecondInstanceLaunched;

  /// Attempt to claim the single-instance lock.
  /// Returns `true` if this is the primary instance.
  /// Returns `false` if another instance is already running (and was signalled).
  static Future<bool> ensureSingleInstance() async {
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
    // FileMode.append (never `write`): opening for write would truncate the
    // file, which can itself fail against a locked byte range on Windows.
    final raf = await lockFile.open(mode: FileMode.append);
    final lockedAt = DateTime.now();
    try {
      // Non-blocking: throws FileSystemException immediately if another
      // process already holds it, instead of waiting.
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      _log.info('Another instance detected, sending focus signal');
      await _writeFocusSignal(dir);
      return false;
    }

    _lock = raf;
    _log.info('Single instance lock acquired at $dir');
    _startWatching(dir);
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
    final raf = _lock;
    _lock = null;
    _lastSignalHandled = null;
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

  /// Writes the focus-request signal for the primary instance to pick up.
  /// Kept in a separate file from the lock file so a secondary instance can
  /// always write it, even though the lock file itself may hold an exclusive
  /// (and on Windows, mandatory) lock.
  static Future<void> _writeFocusSignal(String dir) async {
    try {
      final file = File(p.join(dir, _signalFileName));
      await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
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
            _fireFocusDebounced();
          },
          onError: (Object e) {
            _log.warning('Single-instance watcher error: $e');
            _rearmWatcher(dir);
          },
          onDone: () => _rearmWatcher(dir),
          cancelOnError: true,
        );
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
        _fireFocusDebounced();
      }
    } catch (e) {
      // No signal to catch up on — e.g. a benign race deleting the file
      // between the exists() check and lastModified().
      _log.debug('No missed focus signal to catch up on: $e');
    }
  }

  static void _fireFocusDebounced() {
    final cb = onSecondInstanceLaunched;
    if (cb == null) return;
    final now = DateTime.now();
    if (_lastSignalHandled != null &&
        now.difference(_lastSignalHandled!) < _debounce) {
      return;
    }
    _lastSignalHandled = now;
    _log.info('Received focus signal from second instance');
    cb();
  }
}
