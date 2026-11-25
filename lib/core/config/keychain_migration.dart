/// One-time move of the old login-keychain entries into the data-protection
/// keychain (#1163, part of #1155, ADR 0036).
///
/// Before ADR 0036 every secret lived in the file-based login keychain, bound
/// by an ACL to the signature that wrote it. A differently signed build gets
/// one system dialog per entry there. The data-protection keychain asks
/// nothing, so the entries move once, announced beforehand:
///
/// 1. [scan] reads every known entry quietly (never a dialog). What this build
///    may read without asking moves at once ([KeychainScan.movedQuietly]);
///    what would need consent stays in [KeychainScan.pending].
/// 2. After the user agreed, [migratePending] reads the pending entries (one
///    `readAll`, else one by one; a system dialog each) and moves them.
///
/// A move copies first, reads the copy back and only then deletes the old
/// entry, so an abort at any point loses nothing. A value that already exists
/// in the new keychain wins and is never overwritten; when it differs from the
/// old one, the old entry is kept (it may be the only copy of the right
/// value, #1461). An optional verifier ([KeychainMigration.verify]) can veto a
/// move: then nothing is written and the old entry stays. After the delete the
/// old keychain is read again; a surviving entry is logged and never moved
/// over a different value. Entries gone from the old keychain are not looked
/// at again, so a restart migrates nothing twice. Logs name entries and
/// outcomes only, never values.
///
/// On macOS the old keychain is read and cleared only through [OldKeychain]
/// and the quiet reader, both confined to the file-based keychains (#1674):
/// the plugin storage with `usesDataProtectionKeychain: false` also reaches
/// the data-protection item in a sandboxed build with an access group, so a
/// "move" deleted the new entry it had just confirmed. As a second guard the
/// new entry is read once more after the old one was deleted; a move only
/// counts when it is still there.
library;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';
import 'data_key_store.dart' show dataKeySetAsidePrefix;
import 'secure_access_gate.dart';

final _log = AppLogger('KeychainMigration');

/// How a [KeychainMigration.migratePending] run ended.
enum KeychainMigrationOutcome {
  /// Everything pending is in the new keychain; the old entries are gone.
  done,

  /// The user declined or cancelled the system dialog. Nothing changed.
  declined,

  /// The keychain failed otherwise. Nothing was deleted that was not copied.
  failed,
}

/// Result of the quiet pass.
class KeychainScan {
  const KeychainScan({this.movedQuietly = const [], this.pending = const []});

  /// Entries that were readable without a dialog and are moved already.
  final List<String> movedQuietly;

  /// Entries whose reading needs the system dialog: the announced step moves
  /// them.
  final List<String> pending;
}

enum _Move { moved, kept, failed }

class KeychainMigration {
  KeychainMigration({
    required this.legacy,
    required this.primary,
    required this.quietReader,
    required this.keys,
    this.verify,
    this.repairKeys = const {},
    this.oldKeychain,
  });

  /// The old file-based login keychain, as the plugin addresses it. Used
  /// only where [oldKeychain] is null (tests of the plugin hand-off).
  final FlutterSecureStorage legacy;

  /// The old keychain through the native file-keychain query (macOS). When
  /// set, every read after consent and every delete of an old entry goes
  /// here, never through [legacy].
  final OldKeychain? oldKeychain;

  /// The data-protection keychain.
  final FlutterSecureStorage primary;

  /// Reads one old entry without ever showing a dialog.
  final QuietSecretReader quietReader;

  /// Storage names of the entries that move.
  final List<String> keys;

  /// Optional check of an old value before it is copied (e.g. the data key
  /// against its marker fingerprint). False: nothing is written, the old
  /// entry stays. Must never log the value.
  final bool Function(String key, String value)? verify;

  /// Entries (the data key) whose new-keychain value is replaced by the old
  /// one when [verify] rejects the new value and accepts the old one. The
  /// replaced value is set aside under [dataKeySetAsidePrefix], never lost.
  final Set<String> repairKeys;

  /// Moves what reads quietly and reports what still needs the dialog. Never
  /// shows a system dialog, so it may run at every start.
  Future<KeychainScan> scan() async {
    final moved = <String>[];
    final pending = <String>[];
    final kept = <String>[];
    for (final key in keys) {
      final QuietReadResult result;
      try {
        result = await quietReader(key);
      } on Object catch (e) {
        _log.warning('Quiet read of "$key" failed: ${e.runtimeType}');
        continue;
      }
      switch (result.status) {
        case QuietReadStatus.ok:
          final value = result.value;
          if (value == null) continue;
          switch (await _moveOne(key, value)) {
            case _Move.moved:
              moved.add(key);
            case _Move.kept:
              kept.add(key);
            case _Move.failed:
              break;
          }
        case QuietReadStatus.needsConsent:
          pending.add(key);
        case QuietReadStatus.missing:
          break;
        case QuietReadStatus.error:
          _log.warning('Quiet read of "$key" failed (${result.code})');
      }
    }
    if (moved.isNotEmpty || pending.isNotEmpty || kept.isNotEmpty) {
      _log.info(
        'Old keychain scan: moved [${moved.join(', ')}] quietly, '
        'kept [${kept.join(', ')}], pending [${pending.join(', ')}]',
      );
    }
    return KeychainScan(movedQuietly: moved, pending: pending);
  }

  /// Moves [pending]. Call only after the announcement was confirmed: this
  /// shows the system dialog.
  ///
  /// First one `readAll` of the old keychain (one dialog for all entries).
  /// The file-based macOS keychain refuses that query outright with
  /// errSecParam (-50) and no dialog (#1461), so when it fails for any reason
  /// but a "no" from the user, the pending entries are read one by one: each
  /// single read may show its own dialog ("Always Allow" ends them).
  Future<KeychainMigrationOutcome> migratePending(List<String> pending) async {
    if (pending.isEmpty) return KeychainMigrationOutcome.done;
    Map<String, String>? all;
    // The native old keychain reads one by one: a readAll of the file-based
    // keychain fails with -50 anyway (#1461), and the plugin's readAll is
    // not confined to it (#1674).
    if (oldKeychain == null) {
      try {
        all = await legacy.readAll();
      } on PlatformException catch (e) {
        _log.info('Old keychain readAll failed: ${_describeError(e)}');
        if (_isDeclined(e)) return KeychainMigrationOutcome.declined;
      } on Object catch (e) {
        _log.warning('Old keychain readAll failed: ${e.runtimeType}');
      }
    }
    var failed = false;
    final moved = <String>[];
    final kept = <String>[];
    final failedKeys = <String>[];
    _log.info('Old keychain move starts: pending [${pending.join(', ')}]');
    for (final key in pending) {
      final String? value;
      if (all != null) {
        value = all[key];
      } else {
        try {
          value = await _readOld(key);
        } on PlatformException catch (e) {
          _log.info('Old entry "$key" not read: ${_describeError(e)}');
          if (_isDeclined(e)) return KeychainMigrationOutcome.declined;
          failed = true;
          failedKeys.add(key);
          continue;
        } on Object catch (e) {
          _log.warning('Old entry "$key" not read: ${e.runtimeType}');
          failed = true;
          failedKeys.add(key);
          continue;
        }
      }
      if (value == null) continue; // gone meanwhile, nothing to move
      switch (await _moveOne(key, value)) {
        case _Move.moved:
          moved.add(key);
        case _Move.kept:
          kept.add(key);
        case _Move.failed:
          failed = true;
          failedKeys.add(key);
      }
    }
    final outcome = failed
        ? KeychainMigrationOutcome.failed
        : KeychainMigrationOutcome.done;
    _log.info(
      'Old keychain moved: ${outcome.name}; moved [${moved.join(', ')}], '
      'kept [${kept.join(', ')}], failed [${failedKeys.join(', ')}]',
    );
    return outcome;
  }

  /// Copies [key] to the new keychain unless it has a value there, checks the
  /// copy and only then removes the old entry.
  ///
  /// - [_Move.moved]: the new keychain holds the value, the old entry is gone.
  /// - [_Move.kept]: the old entry stays on purpose (the new keychain holds a
  ///   different value, or [verify] vetoed the old one); nothing was written.
  /// - [_Move.failed]: a step failed; the old entry stays (unless deleting
  ///   it also removed the new one, which is then written again).
  Future<_Move> _moveOne(String key, String value) async {
    try {
      final existing = await primary.read(key: key);
      if (existing != null && existing != value) {
        if (await _repair(key, existing, value)) {
          return await _deleteOldAndConfirm(key, value);
        }
        _log.warning(
          'Entry "$key" differs between old and new keychain; '
          'old entry kept, new one not overwritten',
        );
        return _Move.kept;
      }
      if (existing == null) {
        final verifier = verify;
        if (verifier != null && !verifier(key, value)) {
          _log.warning('Old entry "$key" failed verification; not moved, kept');
          return _Move.kept;
        }
        await primary.write(key: key, value: value);
        if (await primary.read(key: key) != value) {
          _log.warning('Copy of "$key" not confirmed; old entry kept');
          return _Move.failed;
        }
      }
      return await _deleteOldAndConfirm(key, value);
    } on Object catch (e) {
      _log.warning('Move of "$key" failed: ${_describe(e)}; old entry kept');
      return _Move.failed;
    }
  }

  /// Deletes the old entry once the new keychain holds [value], then reads
  /// the new entry again: only when it is still there the move counts. A
  /// delete that took the new entry with it (old and new keychain answered
  /// with the same item, #1674) is undone by writing [value] again. The check
  /// runs after the duplicate cleanup of [_afterDelete] (#1841).
  Future<_Move> _deleteOldAndConfirm(String key, String value) async {
    await _deleteOld(key);
    // Duplicate cleanup first: its extra delete may take the new entry too
    // (#1841), so the final check comes after every delete.
    await _afterDelete(key, value);
    if (await primary.read(key: key) != value) {
      _log.warning(
        'Deleting the old entry "$key" removed the new one too; '
        'new entry written again, not counted as moved',
      );
      await primary.write(key: key, value: value);
      if (await primary.read(key: key) != value) {
        _log.warning('New entry "$key" could not be written again');
      }
      return _Move.failed;
    }
    return _Move.moved;
  }

  Future<String?> _readOld(String key) {
    final old = oldKeychain;
    return old != null ? old.read(key) : legacy.read(key: key);
  }

  Future<void> _deleteOld(String key) {
    final old = oldKeychain;
    return old != null ? old.delete(key) : legacy.delete(key: key);
  }

  /// Replaces a wrong [existing] value in the new keychain by the verified old
  /// [value]. The wrong one is set aside first. False when not applicable or
  /// when a step failed (nothing is deleted then).
  Future<bool> _repair(String key, String existing, String value) async {
    final verifier = verify;
    if (verifier == null || !repairKeys.contains(key)) return false;
    if (verifier(key, existing) || !verifier(key, value)) return false;
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[-:.]'),
      '',
    );
    final asideKey = '$dataKeySetAsidePrefix$stamp';
    await primary.write(key: asideKey, value: existing);
    await primary.write(key: key, value: value);
    if (await primary.read(key: key) != value) {
      _log.warning('Repair of "$key" not confirmed; old entry kept');
      return false;
    }
    _log.warning(
      'Entry "$key" in the new keychain did not match its marker; '
      'replaced by the verified old entry, wrong one set aside',
    );
    return true;
  }

  /// Reads the old entry again, quietly (never a dialog). A leftover equal
  /// to the copied value (a duplicate item) is deleted once more; a
  /// different or unreadable one is only logged and stays, because it was
  /// never copied.
  Future<void> _afterDelete(String key, String copied) async {
    try {
      final left = await quietReader(key);
      switch (left.status) {
        case QuietReadStatus.missing:
          return;
        case QuietReadStatus.ok when left.value == copied:
          _log.warning('Old entry "$key" still present after delete; retrying');
          await _deleteOld(key);
          if ((await quietReader(key)).status != QuietReadStatus.missing) {
            _log.warning('Old entry "$key" survives a second delete');
          }
        case QuietReadStatus.ok:
        case QuietReadStatus.needsConsent:
          _log.warning('Old keychain holds another value for "$key"; kept');
        case QuietReadStatus.error:
          _log.info('Old entry "$key" not re-read (${left.code})');
      }
    } on Object catch (e) {
      _log.info('Old entry "$key" not re-read: ${e.runtimeType}');
    }
  }

  /// Type and platform status of a failure, never a value.
  static String _describe(Object e) => e is PlatformException
      ? '${e.runtimeType}(code=${e.code} message=${e.message})'
      : e.runtimeType.toString();

  /// Code and details of a platform error, never a value.
  static String _describeError(PlatformException e) =>
      'code=${e.code} message=${e.message} details=${e.details}';

  /// errSecUserCanceled (-128) and errSecAuthFailed (-25293) mean the user
  /// said no in the dialog.
  static bool _isDeclined(PlatformException e) {
    final text = '${e.code} ${e.message}';
    return text.contains('-128') ||
        text.contains('-25293') ||
        text.toLowerCase().contains('cancel');
  }
}
