/// History privacy gate + optional PIN lock state.
///
/// [historyRevealedProvider] is the single "may the history be shown right
/// now" switch. Without a PIN it is the plain "Show history" gate; with a
/// PIN, [HistoryRevealedNotifier.unlockWithPin] is the only way to flip it,
/// and [historyContentHiddenProvider] additionally blanks the secondary
/// surfaces (side panel, floating-button menu, Automation API).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/config/settings_sections.dart';
import '../../../core/data/database.dart';
import '../../../core/data/note_asset_storage.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/app_identity/app_identity_service.dart';
import '../../../services/audio/retention/pending_wipe.dart';
import '../../../services/path_service.dart';
import 'history_pin.dart';

final _log = AppLogger('HistoryLock');

/// Wall clock for the PIN throttle — a seam so tests can pin "now".
final historyLockClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

/// What a forgot-PIN wipe left behind.
class HistoryWipeOutcome {
  const HistoryWipeOutcome({
    required this.leftovers,
    required this.queued,
    required this.folder,
    this.migrationCopyLeft,
  });

  /// Files or folders that could not be removed, at least one when the
  /// folders could not be listed at all.
  final int leftovers;

  /// True when every leftover file is queued for removal at the next start.
  final bool queued;

  /// The audio folders that hold the leftovers, for the user to find them.
  /// Empty when nothing was left behind.
  final String folder;

  /// Full path of the pre-migration database copy when it could not be
  /// removed. It is not audio, so it is never queued and not counted in
  /// [leftovers]; the user is told its path instead.
  final String? migrationCopyLeft;
}

/// Permanently deletes every history entry and the audio folders — the
/// "Forgot PIN?" path. Each entry is attempted on its own, so one locked entry
/// does not keep the others. Leftover files are queued for the next start. A
/// folder that cannot be removed contributes its files, not the folder. A
/// folder that cannot be listed queues nothing. A seam so tests do not need a
/// database.
final historyWiperProvider = Provider<Future<HistoryWipeOutcome> Function()>((
  ref,
) {
  return () async {
    final leftovers = <String>[];
    String? unlistedRoot;
    final database = ref.read(historyDatabaseProvider);
    final files = await database.deleteAllHistory();
    for (final path in files) {
      if (!await _deleteQuietly(File(path))) leftovers.add(path);
    }
    // Notes go too: the PIN covers them, so a reset must not leave them behind.
    await database.deleteAllNotes();
    await _wipeNoteAssetFiles(appDataDir(), leftovers);
    // The icon cache tells which apps were dictated into.
    try {
      await ref.read(appIdentityServiceProvider).clear();
    } catch (e, st) {
      _log.warning('wipe: could not delete the app icon cache', e, st);
    }
    ref.invalidate(appIdentityProvider);
    // Plaintext copy of the old history, left by a database migration.
    final preMigration = File(p.join(appDataDir(), 'history.db.pre-migration'));
    final String? migrationCopyLeft = await _deleteQuietly(preMigration)
        ? null
        : preMigration.path;
    for (final root in userAudioDirectories()) {
      if (!await _wipeFolder(Directory(root), leftovers)) {
        unlistedRoot ??= root;
      }
    }
    if (unlistedRoot != null) {
      return HistoryWipeOutcome(
        leftovers: leftovers.length + 1,
        queued: false,
        folder: unlistedRoot,
        migrationCopyLeft: migrationCopyLeft,
      );
    }
    final queued = await recordPendingWipe(leftovers);
    return HistoryWipeOutcome(
      leftovers: leftovers.length,
      queued: queued,
      folder: _leftoverFolder(leftovers),
      migrationCopyLeft: migrationCopyLeft,
    );
  };
});

/// The audio folders that hold the leftovers, comma-separated. Never their
/// common parent: that also holds the database, settings and models, which a
/// user told to delete by hand must not touch.
String _leftoverFolder(List<String> leftovers) {
  final roots = userAudioDirectories();
  final folders = {
    for (final path in leftovers)
      roots.firstWhere(
        (root) => p.isWithin(root, path),
        orElse: () => p.dirname(path),
      ),
  };
  return folders.join(', ');
}

/// Removes everything in [dir]. Returns false when [dir] cannot be listed, or
/// when a subfolder cannot be removed and its files cannot be listed either.
Future<bool> _wipeFolder(Directory dir, List<String> leftovers) async {
  if (!dir.existsSync()) return true;
  final List<FileSystemEntity> entries;
  try {
    entries = await dir.list().toList();
  } catch (e, st) {
    _log.warning('wipe: could not list ${dir.path}', e, st);
    return false;
  }
  var listed = true;
  for (final entity in entries) {
    if (entity is File) {
      if (!await _deleteQuietly(entity)) leftovers.add(entity.path);
      continue;
    }
    if (entity is! Directory) continue;
    try {
      // The recovery journal lives in a subfolder; it describes the
      // recordings just removed and must not outlive them.
      await entity.delete(recursive: true);
    } catch (e, st) {
      _log.warning('wipe: could not delete ${entity.path}', e, st);
      final files = await filesUnder(entity.path);
      if (files == null) {
        listed = false;
      } else {
        leftovers.addAll(files);
      }
    }
  }
  return listed;
}

/// True when the file is gone afterwards.
/// Removes every file of the note image folder under [dir]. A file that cannot
/// be removed is added to [leftovers] and queued like audio leftovers.
Future<void> _wipeNoteAssetFiles(String dir, List<String> leftovers) async {
  final root = Directory(p.join(dir, noteAssetFolderName));
  if (!await root.exists()) return;
  try {
    await for (final entity in root.list(recursive: true)) {
      if (entity is File && !await _deleteQuietly(entity)) {
        leftovers.add(entity.path);
      }
    }
    await root.delete(recursive: true);
  } catch (e, st) {
    _log.warning('wipe: could not clear the note image folder', e, st);
    leftovers.add(root.path);
  }
}

Future<bool> _deleteQuietly(File file) async {
  try {
    if (file.existsSync()) await file.delete();
    return true;
  } catch (e, st) {
    _log.warning('wipe: could not delete ${file.path}', e, st);
    return false;
  }
}

enum HistoryPinOutcome { ok, wrong, lockedOut }

class HistoryPinResult {
  const HistoryPinResult(this.outcome, [this.retryAfter = Duration.zero]);

  final HistoryPinOutcome outcome;

  /// Remaining lockout; only non-zero for [HistoryPinOutcome.lockedOut].
  final Duration retryAfter;
}

/// Whether the History page has been revealed past its privacy gate.
///
/// Starts concealed on every app start; hiding the main window conceals it
/// again, and so does `HistorySettings.historyAutoLockMinutes` of
/// inactivity ([registerActivity] restarts that countdown).
class HistoryRevealedNotifier extends Notifier<bool> {
  Timer? _autoLock;

  @override
  bool build() {
    ref.onDispose(() => _autoLock?.cancel());
    return false;
  }

  HistorySettings get _history =>
      (ref.read(settingsProvider).value ?? AppSettings.defaults).history;

  /// Reveals without a PIN — only honoured while no PIN is set.
  void reveal() {
    if (_history.historyPin.isNotEmpty) return;
    _setRevealed();
  }

  void conceal() {
    _autoLock?.cancel();
    state = false;
  }

  /// Restarts the auto-lock countdown; call on user activity while revealed.
  void registerActivity() {
    if (state) _armAutoLock();
  }

  /// Time left before [unlockWithPin] accepts another attempt.
  Duration lockoutRemaining() {
    final until = DateTime.fromMillisecondsSinceEpoch(
      _history.historyPinLockedUntil,
    );
    final left = until.difference(ref.read(historyLockClockProvider)());
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks [pin] against the stored hash, counting misses and applying the
  /// [historyPinLockout] throttle. Also used to confirm the current PIN
  /// before it is changed or removed.
  Future<HistoryPinResult> unlockWithPin(String pin) async {
    final remaining = lockoutRemaining();
    if (remaining > Duration.zero) {
      return HistoryPinResult(HistoryPinOutcome.lockedOut, remaining);
    }
    final history = _history;
    final stored = history.historyPin;
    if (await Isolate.run(() => verifyHistoryPin(pin, stored))) {
      if (history.historyPinFailedAttempts != 0 ||
          history.historyPinLockedUntil != 0) {
        await _updateHistory(
          (h) =>
              h.copyWith(historyPinFailedAttempts: 0, historyPinLockedUntil: 0),
        );
      }
      _setRevealed();
      return const HistoryPinResult(HistoryPinOutcome.ok);
    }
    final failed = history.historyPinFailedAttempts + 1;
    final lockout = historyPinLockout(failed);
    final now = ref.read(historyLockClockProvider)();
    await _updateHistory(
      (h) => h.copyWith(
        historyPinFailedAttempts: failed,
        historyPinLockedUntil: lockout == Duration.zero
            ? 0
            : now.add(lockout).millisecondsSinceEpoch,
      ),
    );
    return lockout == Duration.zero
        ? const HistoryPinResult(HistoryPinOutcome.wrong)
        : HistoryPinResult(HistoryPinOutcome.lockedOut, lockout);
  }

  /// Stores a fresh hash of [pin] (caller validated it with
  /// [isValidHistoryPin]); a PIN implies the gate, so it is switched on.
  Future<void> setPin(String pin) async {
    final hash = await Isolate.run(() => hashHistoryPin(pin));
    await _updateHistory(
      (h) => h.copyWith(
        historyHideOnOpen: true,
        historyPin: hash,
        historyPinFailedAttempts: 0,
        historyPinLockedUntil: 0,
      ),
    );
  }

  Future<void> removePin() => _updateHistory(
    (h) => h.copyWith(
      historyPin: '',
      historyPinFailedAttempts: 0,
      historyPinLockedUntil: 0,
    ),
  );

  /// "Forgot PIN?": deletes the whole history, drops the PIN and reveals the
  /// (now empty) page. The gate itself stays on. Returns what the wipe left
  /// behind, so the caller can tell the user whether it was queued.
  Future<HistoryWipeOutcome> resetForgottenPin() async {
    final outcome = await ref.read(historyWiperProvider)();
    await removePin();
    _setRevealed();
    return outcome;
  }

  void _setRevealed() {
    state = true;
    _armAutoLock();
  }

  void _armAutoLock() {
    _autoLock?.cancel();
    final minutes = _history.historyAutoLockMinutes;
    if (minutes <= 0) return;
    _autoLock = Timer(Duration(minutes: minutes), conceal);
  }

  Future<void> _updateHistory(HistorySettings Function(HistorySettings) f) =>
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWithSections(history: f(s.history)));
}

final historyRevealedProvider = NotifierProvider<HistoryRevealedNotifier, bool>(
  HistoryRevealedNotifier.new,
);

/// Whether history text must be withheld from every surface: true only when a
/// PIN is actually set and the history has not been unlocked. The lock never
/// claims a PIN it does not know of: while the settings are still loading
/// there is no PIN state yet, so nothing is withheld (every surface is only
/// started from loaded settings). Only a settings load that failed without
/// any previous value fails closed, because a PIN cannot be ruled out then.
/// The PIN-less gate only covers the History page itself, so it does not
/// count here.
final historyContentHiddenProvider = Provider<bool>((ref) {
  final failedWithoutValue = ref.watch(
    settingsProvider.select((s) => s.hasError && !s.hasValue),
  );
  if (failedWithoutValue) return true;
  final hasPin = ref.watch(
    settingsProvider.select(
      (s) => s.value?.history.historyPin.isNotEmpty ?? false,
    ),
  );
  return hasPin && !ref.watch(historyRevealedProvider);
});
