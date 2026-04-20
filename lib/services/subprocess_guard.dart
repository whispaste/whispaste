/// Subprocess lifecycle guard — prevents orphaned native processes.
///
/// Manages PID files for long-lived subprocesses (whisper-server)
/// and kills orphans from previous runs on app startup.
/// WhisPaste is a single-instance app, so any pre-existing subprocess
/// from a previous session is guaranteed to be an orphan.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/logging/app_logger.dart';
import 'path_service.dart' as paths;

/// Names of managed subprocesses whose orphans should be cleaned up.
const _managedProcesses = ['whisper-server'];

final _log = AppLogger('SubprocessGuard');

// ---------------------------------------------------------------------------
// PID file management
// ---------------------------------------------------------------------------

/// Writes a PID file for [processName] so the next app launch can detect it.
void writePid(String processName, int pid) {
  try {
    final file = File(_pidPath(processName));
    file.writeAsStringSync('$pid');
  } catch (e) {
    _log.debug('Failed to write PID file for $processName: $e');
  }
}

/// Removes the PID file for [processName] (called on graceful stop).
void deletePid(String processName) {
  try {
    final file = File(_pidPath(processName));
    if (file.existsSync()) file.deleteSync();
  } catch (e) {
    _log.debug('Failed to delete PID file for $processName: $e');
  }
}

String _pidPath(String processName) =>
    p.join(paths.appDataDir(), '.$processName.pid');

// ---------------------------------------------------------------------------
// Orphan cleanup (called once on app startup)
// ---------------------------------------------------------------------------

/// Kills orphaned subprocesses from previous app runs.
///
/// Two-phase approach:
/// 1. **PID file**: Read PID files left by the previous session and kill
///    matching processes (verified by image name to avoid killing unrelated
///    processes that reused the PID).
/// 2. **Process scan**: Find any remaining managed processes by name. Since
///    WhisPaste is single-instance, any pre-existing whisper-server
///    MUST be an orphan.
Future<void> cleanupOrphans() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

  var killed = 0;

  // Phase 1: PID files from previous session.
  for (final name in _managedProcesses) {
    killed += await _cleanupFromPidFile(name);
  }

  // Phase 2: Process scan for any remaining orphans.
  killed += await _scanAndKillByName();

  if (killed > 0) {
    _log.info('Cleaned up $killed orphaned subprocess(es)');
  }
}

/// Reads a PID file, verifies the process, kills it, deletes the file.
Future<int> _cleanupFromPidFile(String processName) async {
  final file = File(_pidPath(processName));
  if (!file.existsSync()) return 0;

  try {
    final pidStr = file.readAsStringSync().trim();
    final pid = int.tryParse(pidStr);
    file.deleteSync();

    if (pid == null || pid <= 0) return 0;

    if (await _isProcessAlive(pid, processName)) {
      Process.killPid(pid);
      _log.info('Killed orphaned $processName (PID $pid) via PID file');
      return 1;
    }
  } catch (e) {
    _log.debug('PID file cleanup for $processName failed: $e');
  }
  return 0;
}

/// Scans running processes for any managed subprocess and kills them.
Future<int> _scanAndKillByName() async {
  var killed = 0;
  for (final name in _managedProcesses) {
    final pids = await _findProcessesByName(name);
    for (final pid in pids) {
      try {
        Process.killPid(pid);
        _log.info('Killed orphaned $name (PID $pid) via process scan');
        killed++;
      } catch (_) {}
    }
  }
  return killed;
}

// ---------------------------------------------------------------------------
// Platform-specific process queries
// ---------------------------------------------------------------------------

/// Checks if [pid] is alive AND matches [expectedName].
Future<bool> _isProcessAlive(int pid, String expectedName) async {
  try {
    if (Platform.isWindows) {
      final exeName = '$expectedName.exe';
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FI',
        'IMAGENAME eq $exeName',
        '/NH',
        '/FO',
        'CSV',
      ]);
      return result.stdout.toString().contains(exeName);
    }
    // macOS / Linux
    final result = await Process.run('ps', ['-p', '$pid', '-o', 'comm=']);
    return result.stdout.toString().trim().contains(expectedName);
  } catch (_) {
    return false;
  }
}

/// Returns PIDs of all running processes matching [name].
@visibleForTesting
Future<List<int>> findProcessesByName(String name) =>
    _findProcessesByName(name);

Future<List<int>> _findProcessesByName(String name) async {
  final pids = <int>[];
  try {
    if (Platform.isWindows) {
      final exeName = '$name.exe';
      final result = await Process.run('tasklist', [
        '/FI',
        'IMAGENAME eq $exeName',
        '/NH',
        '/FO',
        'CSV',
      ]);
      // CSV format: "whisper-server.exe","12345","Console","1","123,456 K"
      for (final line in result.stdout.toString().split('\n')) {
        if (!line.contains(exeName)) continue;
        final parts = line.split('","');
        if (parts.length >= 2) {
          final pid = int.tryParse(parts[1].replaceAll('"', '').trim());
          if (pid != null && pid > 0) pids.add(pid);
        }
      }
    } else {
      // macOS / Linux
      final result = await Process.run('pgrep', ['-x', name]);
      for (final line in result.stdout.toString().split('\n')) {
        final pid = int.tryParse(line.trim());
        if (pid != null && pid > 0) pids.add(pid);
      }
    }
  } catch (_) {
    // pgrep/tasklist not available — best effort.
  }
  return pids;
}
