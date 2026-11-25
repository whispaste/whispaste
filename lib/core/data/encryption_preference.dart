/// The user's choice "Encryption" in Settings → Privacy (#1022).
///
/// Encryption of the history (#1020) and of the recordings (#1021) is on by
/// default. The choice lives in a marker file next to the history database,
/// not in the database itself: it must be known before the database opens,
/// because the conversion runs before the first connection.
///
/// A change applies at the next start (maintainer decision on #1022): the
/// database stays open during a session, and converting it in place would
/// mean pausing every reader and writer. So the switch only records the
/// wish; the session keeps the state it started with
/// ([encryptionOnThisSession]) and Settings offers the restart. At the next
/// start the history is converted before it opens, the recordings right
/// after, both with the progress screen ([encryptionConversionProgress]).
///
/// Markers below the app data folder:
/// - `encryption-off`: present while the user switched encryption off.
/// - `encryption-switch-pending`: the choice changed and the recordings still
///   have to be converted with progress at the next start. Removed only after
///   that run went through, so a run cut off by a crash or a quit is repeated.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../services/path_service.dart' as paths;
import '../logging/app_logger.dart';

final _log = AppLogger('EncryptionPreference');

/// Present while encryption is switched off.
const encryptionOffMarkerName = 'encryption-off';

/// Present while a switch still has to convert the recordings.
const encryptionSwitchPendingMarkerName = 'encryption-switch-pending';

/// Reads and writes the markers in [appDataDir]. Never throws.
class EncryptionPreference {
  const EncryptionPreference(this.appDataDir);

  final String appDataDir;

  File get _off => File(p.join(appDataDir, encryptionOffMarkerName));
  File get _pending =>
      File(p.join(appDataDir, encryptionSwitchPendingMarkerName));

  /// Whether the user wants encryption (the default).
  bool get wanted => !_exists(_off);

  /// Whether the recordings still wait for the conversion of a switch.
  bool get switchPending => _exists(_pending);

  /// Records the choice and asks the next start to convert. False when the
  /// marker could not be written; the choice is unchanged then.
  bool setWanted(bool on) {
    try {
      Directory(appDataDir).createSync(recursive: true);
      if (on) {
        if (_off.existsSync()) _off.deleteSync();
      } else {
        _off.writeAsStringSync('');
      }
      _pending.writeAsStringSync('');
      return true;
    } on FileSystemException catch (e) {
      _log.warning('Encryption choice not saved: ${e.osError?.errorCode}');
      return false;
    }
  }

  /// The conversion of the recordings went through.
  void clearSwitchPending() {
    try {
      if (_pending.existsSync()) _pending.deleteSync();
    } on FileSystemException catch (e) {
      // The next start repeats the (then cheap) run.
      _log.debug('Switch marker not removed: ${e.osError?.errorCode}');
    }
  }

  static bool _exists(File file) {
    try {
      return file.existsSync();
    } on FileSystemException {
      return false;
    }
  }
}

bool? _onThisSession;

/// Whether this session encrypts: the choice as it was at the first read in
/// this process. The history database and the recordings both go by it, so
/// a switch during the session changes nothing until the restart.
bool encryptionOnThisSession([String? appDataDir]) => _onThisSession ??=
    EncryptionPreference(appDataDir ?? paths.appDataDir()).wanted;

/// Forgets the session value, so a test can start a new "session".
@visibleForTesting
void resetEncryptionSessionForTesting([bool? value]) => _onThisSession = value;

/// Which part a start-time conversion is working on.
enum EncryptionConversionStep { history, recordings }

/// Progress of the conversion at start, for the start screen.
@immutable
class EncryptionConversionProgress {
  const EncryptionConversionProgress({
    required this.toPlain,
    required this.step,
    this.done = 0,
    this.total = 0,
  });

  /// True while converting back to plain files (encryption switched off).
  final bool toPlain;
  final EncryptionConversionStep step;

  /// Recordings finished and to do; both 0 for the history step.
  final int done;
  final int total;

  /// 0..1, or null while the share is unknown (the history step).
  double? get fraction => total > 0 ? done / total : null;

  @override
  bool operator ==(Object other) =>
      other is EncryptionConversionProgress &&
      other.toPlain == toPlain &&
      other.step == step &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(toPlain, step, done, total);
}

/// Set while a start-time conversion runs, null otherwise. A plain notifier,
/// not a provider: the history open sets it from inside the database open.
final encryptionConversionProgress =
    ValueNotifier<EncryptionConversionProgress?>(null);

/// What Settings shows: the choice and the state this session runs with.
@immutable
class EncryptionSetting {
  const EncryptionSetting({required this.wanted, required this.onThisSession});

  final bool wanted;
  final bool onThisSession;

  /// The choice differs from the running state: a restart applies it.
  bool get restartNeeded => wanted != onThisSession;
}

/// The switch in Settings → Privacy.
class EncryptionSettingNotifier extends Notifier<EncryptionSetting> {
  EncryptionPreference get _preference =>
      EncryptionPreference(paths.appDataDir());

  @override
  EncryptionSetting build() => EncryptionSetting(
    wanted: _preference.wanted,
    onThisSession: encryptionOnThisSession(),
  );

  /// Records [on] for the next start. False when it could not be saved.
  bool setWanted(bool on) {
    if (on == state.wanted) return true;
    if (!_preference.setWanted(on)) return false;
    _log.info('Encryption switched ${on ? 'on' : 'off'}, applies at restart');
    state = EncryptionSetting(wanted: on, onThisSession: state.onThisSession);
    return true;
  }
}

final encryptionSettingProvider =
    NotifierProvider<EncryptionSettingNotifier, EncryptionSetting>(
      EncryptionSettingNotifier.new,
    );
