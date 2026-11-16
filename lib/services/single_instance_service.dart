import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../core/data/instance_write_gate.dart';
import '../core/logging/app_logger.dart';
import 'app_link.dart';
import 'opened_files.dart';
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
  cancel,

  /// `whispaste://newsletter/confirmed` — the newsletter confirmation page
  /// handed the user back: show the window and the newsletter status.
  newsletterConfirmed,

  /// The file manager asked to transcribe files (#1684). Never parsed from
  /// arguments: a launch with files sends it, and the paths travel in
  /// request files next to the signal (see
  /// [SingleInstanceService.onOpenFiles]).
  openFiles;

  /// Parses the process arguments. Unrelated arguments are ignored; if
  /// several are given, the first one wins. Windows and Linux pass an opened
  /// `whispaste://` link as an argument; macOS delivers it through
  /// [SingleInstanceService.openUrls].
  static InstanceCommand fromArgs(List<String> args) {
    for (final arg in args) {
      if (arg == '--toggle') return toggle;
      if (arg == '--cancel') return cancel;
      switch (AppLink.parse(arg)) {
        case AppLink.newsletterConfirmed:
          return newsletterConfirmed;
        case AppLink.other:
          return focus;
        case AppLink.none:
          break;
      }
    }
    return focus;
  }
}

/// Outcome of trying one lock site (see [SingleInstanceService]).
enum LockSiteResult {
  /// This process now holds the lock.
  acquired,

  /// Another process holds the lock: a WhisPaste is running.
  held,

  /// The lock could not be tried at all (folder or file not creatable, for
  /// example missing rights). Says nothing about another instance.
  unavailable,
}

/// What a launch may do after the single-instance check (#1647).
enum InstanceClaim {
  /// This process holds at least one lock and no other process holds any:
  /// it is the only WhisPaste and starts normally.
  primary,

  /// Another WhisPaste holds a lock; it was signalled and this launch exits.
  secondary,

  /// No lock could be tried anywhere, so a running WhisPaste cannot be ruled
  /// out. The app starts, but keeps the history database closed until the
  /// user confirms on the start screen ([InstanceWriteGate]).
  unverified;

  /// Combines the results of every lock site. A held lock anywhere means
  /// another instance runs; otherwise one acquired lock is enough, because
  /// every running instance holds every site it can reach.
  static InstanceClaim from(Iterable<LockSiteResult> sites) {
    if (sites.contains(LockSiteResult.held)) return secondary;
    if (sites.contains(LockSiteResult.acquired)) return primary;
    return unverified;
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
/// A second lock of the same kind lives in the user's temporary folder
/// ([fallbackLockDir], #1647). Every primary holds both locks where it can,
/// so a launch whose app-data folder is not writable (rights, a broken
/// profile) still finds a running instance through the second one, and still
/// starts normally when it can take that one itself. Only when neither lock
/// can even be tried is the result [InstanceClaim.unverified]: the app opens
/// with a start screen instead of the history, see [InstanceWriteGate].
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

  /// Locks this process holds, by lock folder.
  static final Map<String, RandomAccessFile> _locks = {};
  static final Map<String, StreamSubscription<FileSystemEvent>> _watches = {};
  static StreamSubscription<ProcessSignal>? _toggleSignal;
  static final Map<String, Timer> _rearmTimers = {};
  static InstanceClaim? _claim;
  static final Map<InstanceCommand, DateTime> _lastSignalHandled = {};
  static String? _lastSignalContent;

  /// Bumped by [release]; a signal read that started before it is dropped.
  static int _generation = 0;
  static void Function(InstanceCommand command)? _onRemoteCommand;
  static final List<InstanceCommand> _pendingRemoteCommands = [];
  static void Function(List<String> paths)? _onOpenFiles;
  static final List<List<String>> _pendingOpenFiles = [];

  /// Serialises reads of the open-file requests, so two signals arriving
  /// together never hand out the same request twice.
  static Future<void> _openRequestsDrain = Future.value();

  /// Folder (inside a lock folder) for the paths second launches hand over.
  static const String _openRequestsDirName = 'open_files';

  /// Time source for the debounce window; tests pin it instead of racing
  /// the wall clock.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// Overrides the lock directory for tests, isolating them from the real
  /// app data path. `null` (the default) uses [paths.appDataDir].
  @visibleForTesting
  static String? lockDirOverride;

  /// Overrides the second lock folder for tests. While [lockDirOverride] is
  /// set and this is not, tests use no second lock, so they never touch the
  /// real temporary folder (or a WhisPaste running on the test machine).
  @visibleForTesting
  static String? fallbackLockDirOverride;

  /// The result of the last [ensureSingleInstance], or null before it ran.
  static InstanceClaim? get claim => _claim;

  /// The second lock folder in the user's temporary folder: per user on
  /// every system (`$TMPDIR` on macOS, also inside the sandbox; `%TEMP%` on
  /// Windows; `$XDG_RUNTIME_DIR` on Linux, else `/tmp` with the user name),
  /// and per build like the app data ([paths.appDataFolderName]).
  static String? fallbackLockDir() {
    final override = fallbackLockDirOverride;
    if (override != null) return override;
    if (lockDirOverride != null) return null;
    final name = '${paths.appDataFolderName(linux: true)}-instance';
    if (Platform.isLinux) {
      final runtime = Platform.environment['XDG_RUNTIME_DIR'];
      if (runtime != null && runtime.isNotEmpty) return p.join(runtime, name);
      final user = Platform.environment['USER'] ?? 'user';
      return p.join(Directory.systemTemp.path, '$name-$user');
    }
    return p.join(Directory.systemTemp.path, name);
  }

  /// The file a second launch writes for the primary. Outside callers (the
  /// Linux desktop-shortcut launcher) write `<unique token> <command>` here
  /// directly to skip booting a second process.
  static String signalFilePath() => p.join(
    lockDirOverride ?? p.join(paths.appDataDir(), _dirName),
    _signalFileName,
  );

  /// Callback invoked when a second instance requests focus.
  static void Function()? onSecondInstanceLaunched;

  /// Handler for every [InstanceCommand] except [InstanceCommand.focus].
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

  /// Handler for files the file manager asked to transcribe (#1684): the
  /// files of this process's own launch and those a second launch forwards.
  /// Each call carries the files of one launch (or one macOS open event).
  ///
  /// Files that arrive while no handler is registered (the history and the
  /// import queue are wired up only after the first frame) are queued and
  /// delivered, in order, as soon as one is set.
  static set onOpenFiles(void Function(List<String> paths)? handler) {
    _onOpenFiles = handler;
    if (handler == null) return;
    final pending = List.of(_pendingOpenFiles);
    _pendingOpenFiles.clear();
    pending.forEach(handler);
  }

  /// Sets [onOpenFiles] to [handler] only while [ready], else clears it, so
  /// opened files wait in the queue (#1705). The app is not ready while the
  /// onboarding is on top: no model may be set up yet, and the import would
  /// run hidden behind it. The files then come out once it closes.
  static void deliverOpenFilesWhen({
    required bool ready,
    required void Function(List<String> paths) handler,
  }) {
    onOpenFiles = ready ? handler : null;
  }

  /// Puts [files] back at the end of the queue: their handler took them but
  /// could not process them any more (its widget was rebuilt meanwhile).
  /// The current handler, or the next one set, receives them (#1705).
  static void requeueOpenFiles(List<String> files) {
    if (files.isEmpty) return;
    _dispatchOpenFiles(files);
  }

  /// Attempt to claim the single-instance lock.
  /// Returns `true` if this process may start: it is the primary instance,
  /// or no lock could be tried ([claim] is then
  /// [InstanceClaim.unverified] and the history database stays closed until
  /// the user confirms). Returns `false` if another instance is already
  /// running (and was signalled with [command]).
  ///
  /// When this process may start and [command] is
  /// [InstanceCommand.toggle] or [InstanceCommand.newsletterConfirmed], it is
  /// queued for [onRemoteCommand]: `whispaste --toggle` with no running
  /// instance starts the app and then starts a dictation, an opened
  /// newsletter link starts it and then shows the status. Handling a primary [InstanceCommand.cancel] (nothing
  /// to cancel) is the caller's decision.
  ///
  /// [openFiles] are the files the launch was asked to transcribe (#1684,
  /// [openedFilesFromArgs]). A second launch hands them to the running
  /// instance; a starting one queues them for [onOpenFiles].
  static Future<bool> ensureSingleInstance({
    InstanceCommand command = InstanceCommand.focus,
    List<String> openFiles = const [],
  }) async {
    // Already holding a lock — we ARE the primary. Never open a second
    // handle: on POSIX, closing any file descriptor for a file drops every
    // advisory lock this process holds on it, even ones held via other
    // handles, so a second open/close here would silently release the lock
    // out from under the first.
    if (_locks.isNotEmpty) return true;

    final lockedAt = DateTime.now();
    final results = <LockSiteResult>[];
    for (final dir in [_primaryLockDir(), fallbackLockDir()]) {
      if (dir == null) {
        results.add(LockSiteResult.unavailable);
        continue;
      }
      final result = await _tryLock(dir);
      results.add(result);
      if (result == LockSiteResult.held) {
        await _releaseLocks();
        if (openFiles.isNotEmpty) {
          _log.info('Another instance detected, handing over files');
          await _signalOpenFiles(dir, openFiles);
        } else {
          _log.info(
            'Another instance detected, sending ${command.name} signal',
          );
          await _writeSignal(dir, command);
        }
        _claim = InstanceClaim.secondary;
        return false;
      }
    }

    final wasUnverified = _claim == InstanceClaim.unverified;
    final claim = InstanceClaim.from(results);
    _claim = claim;
    if (claim == InstanceClaim.unverified) {
      // Neither lock could be tried. Not "secondary": that would exit on
      // every launch and lock the user out over a rights problem. Not a
      // plain start either: another WhisPaste may write to the same data.
      _log.warning(
        'Single-instance check unavailable; history stays closed until '
        'the user confirms',
      );
      InstanceWriteGate.close();
    } else {
      // A retry from the start screen that now holds a lock needs no
      // confirmation any more.
      InstanceWriteGate.open();
      if (results.contains(LockSiteResult.unavailable)) {
        _log.warning('One single-instance lock unavailable, the other holds');
      }
      _watchToggleSignal();
    }
    // A retry from the start screen already queued the launch's command.
    if (!wasUnverified &&
        (command == InstanceCommand.toggle ||
            command == InstanceCommand.newsletterConfirmed)) {
      _dispatchRemoteCommand(command);
    }
    if (!wasUnverified && openFiles.isNotEmpty) {
      _dispatchOpenFiles(openFiles);
    }
    for (final dir in _locks.keys.toList()) {
      _startWatching(dir);
    }
    // Launches that lost the race for the lock (several files opened at
    // once start one process each on Windows) may have handed over their
    // files before the watchers were armed. Requests older than this start
    // are left over from an earlier run and are dropped.
    await _drainOpenFileRequests(
      notBefore: lockedAt.subtract(const Duration(seconds: 1)),
    );
    for (final dir in _locks.keys.toList()) {
      await _catchUpOnMissedSignal(dir, lockedAt);
    }
    return true;
  }

  /// The user answered the start screen of an [InstanceClaim.unverified]
  /// start with "open anyway". Tries the locks once more first: a passing
  /// problem may be gone, and a WhisPaste that turned up in the meantime is
  /// brought to the front instead. Returns false in that case (this launch
  /// should quit); otherwise opens the [InstanceWriteGate] and returns true.
  static Future<bool> confirmUnverifiedStart() async {
    if (!await ensureSingleInstance()) return false;
    InstanceWriteGate.open();
    return true;
  }

  /// The lock folder in the app data, or null when it cannot be resolved
  /// (e.g. `APPDATA` unset on Windows).
  static String? _primaryLockDir() {
    try {
      return lockDirOverride ?? p.join(paths.appDataDir(), _dirName);
    } catch (e) {
      _log.warning('Cannot resolve the single-instance lock dir: $e');
      return null;
    }
  }

  /// Tries the lock in [dir]. A folder or file that cannot be created is
  /// [LockSiteResult.unavailable], never [LockSiteResult.held]: mistaking it
  /// for a running instance would exit on every launch.
  static Future<LockSiteResult> _tryLock(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
    } catch (e) {
      _log.warning('Cannot prepare single-instance lock dir $dir: $e');
      return LockSiteResult.unavailable;
    }

    final lockFile = File(p.join(dir, _lockFileName));
    final RandomAccessFile raf;
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
      // on every launch.
      _log.warning('Cannot open single-instance lock file in $dir: $e');
      return LockSiteResult.unavailable;
    }

    try {
      // Non-blocking: throws FileSystemException immediately if another
      // process already holds it, instead of waiting.
      await raf.lock(FileLock.exclusive);
    } on FileSystemException {
      await raf.close();
      return LockSiteResult.held;
    }
    _locks[dir] = raf;
    _log.info('Single instance lock acquired at $dir');
    return LockSiteResult.acquired;
  }

  /// Releases the instance lock without exiting — used right before a
  /// deliberate self-relaunch (see `MacOSLifecycleChannel.restart`). Without
  /// this, the freshly-spawned replacement process starts while this process
  /// still holds the lock, loses `ensureSingleInstance()`, and exits itself
  /// as a "second instance" — the old process then also quits on schedule,
  /// so the app closes entirely instead of restarting. Safe to call even if
  /// the lock was never acquired (e.g. this is already a secondary instance).
  static Future<void> release() async {
    _generation++;
    for (final timer in _rearmTimers.values) {
      timer.cancel();
    }
    _rearmTimers.clear();
    final watches = _watches.values.toList();
    _watches.clear();
    for (final watch in watches) {
      await watch.cancel();
    }
    await _toggleSignal?.cancel();
    _toggleSignal = null;
    _lastSignalHandled.clear();
    _lastSignalContent = null;
    _pendingRemoteCommands.clear();
    _pendingOpenFiles.clear();
    // The claim stays: a relaunch that fails reclaims through
    // ensureSingleInstance, which overwrites it.
    final hadLocks = _locks.isNotEmpty;
    await _releaseLocks();
    if (hadLocks) {
      _log.info('Single instance lock released (relaunch in progress)');
    }
  }

  /// Unlocks and closes every lock this process holds.
  static Future<void> _releaseLocks() async {
    final locks = _locks.values.toList();
    _locks.clear();
    for (final raf in locks) {
      try {
        await raf.unlock();
      } catch (e) {
        // Already released (e.g. Windows reporting the segment as unlocked)
        // — closing below still guarantees the OS-level lock is gone.
        _log.debug('unlock() no-op, already released: $e');
      }
      await raf.close();
    }
  }

  /// Resets [claim] and the write gate between tests.
  @visibleForTesting
  static void debugResetClaim() {
    _claim = null;
    InstanceWriteGate.open();
  }

  /// Writes the signal for the primary instance to pick up.
  /// Kept in a separate file from the lock file so a secondary instance can
  /// always write it, even though the lock file itself may hold an exclusive
  /// (and on Windows, mandatory) lock.
  ///
  /// Format: `<ISO-8601 timestamp> <process id> <command>`. Timestamp and
  /// process id keep every signal distinct (see [_onSignal]), also for
  /// launches in the same instant (several files opened at once); an older
  /// primary that predates the command suffix still treats any new content
  /// as a focus request.
  static Future<void> _writeSignal(String dir, InstanceCommand command) async {
    try {
      final file = File(p.join(dir, _signalFileName));
      await file.writeAsString(
        '${DateTime.now().toIso8601String()} $pid ${command.name}',
        flush: true,
      );
    } catch (e) {
      _log.warning('Failed to signal existing instance: $e');
    }
  }

  /// Hands [files] to the primary in [dir]: one request file per launch in
  /// the `open_files` folder, then an [InstanceCommand.openFiles] signal.
  /// Concurrent launches each write their own request, so none overwrites
  /// another's files the way a shared signal file would. Written under a
  /// temporary name and renamed, so a reader never sees half a request.
  static Future<void> _signalOpenFiles(String dir, List<String> files) async {
    try {
      final folder = Directory(p.join(dir, _openRequestsDirName));
      await folder.create(recursive: true);
      final name =
          '${DateTime.now().microsecondsSinceEpoch}-$pid-'
          '${Random().nextInt(1 << 32)}';
      final temp = File(p.join(folder.path, '$name.tmp'));
      await temp.writeAsString(jsonEncode(files), flush: true);
      await temp.rename(p.join(folder.path, '$name.req'));
    } catch (e) {
      // Still signal: the running instance at least comes to the front.
      _log.warning('Failed to hand files to the existing instance: $e');
    }
    await _writeSignal(dir, InstanceCommand.openFiles);
  }

  /// What a second launch with files does, for tests: the request plus the
  /// signal, in [dir].
  @visibleForTesting
  static Future<void> debugSignalOpenFiles(String dir, List<String> files) =>
      _signalOpenFiles(dir, files);

  /// Reads and deletes every open-file request in the lock folders this
  /// process holds and hands their files to [onOpenFiles], oldest first.
  /// With [notBefore], older requests are deleted unread.
  static Future<void> _drainOpenFileRequests({DateTime? notBefore}) {
    final next = _openRequestsDrain.then((_) => _drainOnce(notBefore));
    _openRequestsDrain = next.catchError((Object _) {});
    return next;
  }

  static Future<void> _drainOnce(DateTime? notBefore) async {
    final generation = _generation;
    final requests = <File>[];
    for (final dir in _locks.keys.toList()) {
      final folder = Directory(p.join(dir, _openRequestsDirName));
      try {
        if (!await folder.exists()) continue;
        await for (final entry in folder.list()) {
          if (entry is File && entry.path.endsWith('.req')) {
            requests.add(entry);
          }
        }
      } catch (e) {
        _log.warning('Cannot read handed-over files in $dir: $e');
      }
    }
    // Names start with the writer's time stamp.
    requests.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final request in requests) {
      try {
        final stale =
            notBefore != null &&
            (await request.lastModified()).isBefore(notBefore);
        final files = stale
            ? const <String>[]
            : _decodeRequest(await request.readAsString());
        await request.delete();
        if (generation != _generation) return;
        if (files.isNotEmpty) _dispatchOpenFiles(files);
      } catch (e) {
        // Taken by a concurrent reader, or not readable: never retried, so
        // a broken request cannot block the ones behind it.
        _log.warning('Skipping a handed-over file request: $e');
        try {
          if (await request.exists()) await request.delete();
        } catch (_) {}
      }
    }
  }

  static List<String> _decodeRequest(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! List) return const [];
    return [
      for (final f in decoded)
        if (f is String && f.isNotEmpty) f,
    ];
  }

  /// Watches the lock directory for the signal file being (re)written by a
  /// secondary instance. Watches the directory rather than the file itself —
  /// Windows' `ReadDirectoryChangesW` backing only supports watching
  /// directories, not individual files.
  static void _startWatching(String dir) {
    _watches[dir] = Directory(dir)
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
    _rearmTimers[dir]?.cancel();
    _rearmTimers[dir] = Timer(_rearmDelay, () {
      _rearmTimers.remove(dir);
      if (_locks.containsKey(dir)) _startWatching(dir);
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
  @visibleForTesting
  static Future<void> debugReadSignal(String dir) async {
    await _onSignal(dir);
    // The watcher may have taken this signal first; wait for its read of
    // the handed-over files too.
    await _openRequestsDrain;
  }

  static Future<void> _onSignal(String dir) async {
    final generation = _generation;
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
    if (generation != _generation) return;
    // Empty: the event fired between truncate and write.
    if (content.isEmpty || content == _lastSignalContent) return;
    _lastSignalContent = content;
    final command = _parseSignalCommand(content);
    if (command == InstanceCommand.openFiles) {
      // Not debounced: every request is its own set of files, and reading
      // them is idempotent.
      _log.info('Received files from second instance');
      await _drainOpenFileRequests();
      return;
    }
    _fireDebounced(command);
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

  /// URLs macOS opened in this (already running) process: the system hands
  /// a `whispaste://` link to the running app instead of starting a second
  /// one. Treated like the same link as a launch argument.
  ///
  /// File URLs are files Finder asked to open (Open With, #1684): they go to
  /// [onOpenFiles], all URLs of one open event as one call. macOS grants the
  /// sandboxed app access to exactly these files.
  static void openUrls(Iterable<String> urls) {
    final files = <String>[];
    for (final url in urls) {
      if (AppLink.parse(url) == AppLink.none) {
        final file = openedFileFromArg(url);
        if (file != null) {
          files.add(file);
        } else {
          onSecondInstanceLaunched?.call();
        }
        continue;
      }
      final command = InstanceCommand.fromArgs([url]);
      if (command == InstanceCommand.focus) {
        onSecondInstanceLaunched?.call();
      } else {
        _dispatchRemoteCommand(command);
      }
    }
    if (files.isNotEmpty) _dispatchOpenFiles(files);
  }

  static void _dispatchOpenFiles(List<String> files) {
    final handler = _onOpenFiles;
    if (handler == null) {
      _pendingOpenFiles.add(List.unmodifiable(files));
      return;
    }
    handler(List.unmodifiable(files));
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
