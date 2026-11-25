/// Keeps retained recordings encrypted at rest (#1021, part of #591), and
/// the audio waiting for them: parked dictations (`PendingAudioQueue`) and
/// the decoded WAV of an import job (`AudioImportQueue`). Only the live
/// capture file of a running dictation stays plain until it ends.
///
/// A retained recording keeps its path and `.wav` name, so retention, the
/// attachment cap, deletion and recovery stay path-based and unchanged. Only
/// the content changes: [protect] replaces the plain WAV by a sealed one
/// (`recording_cipher.dart`). Readers go through [read], which opens sealed
/// files and passes plain ones (not yet protected) through.
///
/// Replacing never risks the recording: the sealed bytes go to
/// `<path>$protectTempSuffix` first, are read back and opened again, and
/// only then renamed over the original in one atomic step. An abort at any
/// point leaves the original plain WAV (and maybe a temp file that the next
/// [migrate] removes); an error deletes the temp file and keeps the original.
/// The temp file sits in the same private folder, so it gets the same
/// owner-only rights (#265).
///
/// Encryption and the read-back check run on a background isolate, and
/// [protect] is only called after the history save and paste, so the hotkey
/// path never waits for it.
///
/// Without the data key (#1019: unavailable, lost) a recording stays plain
/// and the next start tries again; a sealed recording then cannot be read
/// and [read] throws [RecordingLockedException].
///
/// With encryption switched off in Settings → Privacy (#1022) [protect]
/// leaves new recordings plain, and [migrate] with `toPlain` turns sealed
/// recordings back into plain WAVs ([unprotect]) with the same temp file,
/// read-back check and atomic swap. [read] keeps opening both forms, so a
/// recording not yet converted stays playable either way.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/data_key_access.dart';
import '../../../core/config/data_key_store.dart';
import '../../../core/data/encryption_preference.dart';
import '../../../core/logging/app_logger.dart';
import 'recording_cipher.dart';

final _log = AppLogger('RecordingVault');

/// Suffix of the temp file a [RecordingVault.protect] writes before the
/// atomic swap.
const protectTempSuffix = '.wpenc-tmp';

/// Result of [RecordingVault.protect].
enum ProtectOutcome {
  /// The file is now sealed.
  sealed,

  /// The file was sealed already; nothing was written.
  alreadySealed,

  /// The file does not exist (deleted or evicted meanwhile).
  missing,

  /// The data key is not available; the file stays plain.
  noKey,

  /// Sealing or opening failed; the original file is unchanged.
  failed,

  /// Encryption is switched off for this session (#1022); the file stays
  /// plain.
  encryptionOff,

  /// [RecordingVault.unprotect] replaced the sealed file by the plain WAV.
  unsealed,

  /// [RecordingVault.unprotect] found the file plain already.
  alreadyPlain,
}

/// A sealed recording that cannot be opened: no data key, or the file does
/// not authenticate under it.
final class RecordingLockedException implements Exception {
  const RecordingLockedException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'RecordingLockedException($reason: $path)';
}

/// Length of the plain WAV behind the file at [path], sealed or not, so a
/// length check (e.g. the slice manifest) holds across [RecordingVault.protect].
Future<int> recordingPlainLength(String path) async {
  final file = File(path);
  final length = await file.length();
  if (length < sealedOverhead) return length;
  final raf = await file.open();
  try {
    final head = await raf.read(recordingMagic.length);
    return isSealedRecording(head) ? length - sealedOverhead : length;
  } finally {
    await raf.close();
  }
}

/// Seals, reads and migrates retained recordings. See the library comment.
class RecordingVault {
  RecordingVault({
    required this._dataKey,
    bool Function()? encryptionOn,
    @visibleForTesting
    Future<void> Function(File temp, Uint8List bytes)? writeTemp,
  }) : _encryptionOn = encryptionOn ?? _alwaysOn,
       _writeTemp = writeTemp ?? _defaultWriteTemp;

  final Future<List<int>?> Function() _dataKey;

  /// Whether this session encrypts (#1022); read on every [protect].
  final bool Function() _encryptionOn;
  final Future<void> Function(File temp, Uint8List bytes) _writeTemp;

  Uint8List? _key;

  /// Writes run one after another: a migration and a new recording never
  /// swap the same file at once.
  Future<void> _queue = Future<void>.value();

  /// Replaces the plain WAV at [path] by a sealed one, unless encryption is
  /// switched off ([ProtectOutcome.encryptionOff]). Never throws.
  Future<ProtectOutcome> protect(String path) => _enqueue(
    () async =>
        _encryptionOn() ? await _protect(path) : ProtectOutcome.encryptionOff,
  );

  /// Replaces the sealed recording at [path] by its plain WAV (#1022).
  /// Never throws; on any failure the sealed file stays as it is.
  Future<ProtectOutcome> unprotect(String path) =>
      _enqueue(() => _unprotect(path));

  /// Seals every plain recording in [paths], once, or with [toPlain] opens
  /// every sealed one back into a plain WAV. Removes temp files an aborted
  /// earlier run left in [directories] first. Safe to repeat: files already
  /// in the wanted form only cost a header read. [onProgress] hears after
  /// each file how many of all are done. Never throws.
  Future<Map<ProtectOutcome, int>> migrate(
    Iterable<String> paths, {
    Iterable<String> directories = const [],
    bool toPlain = false,
    void Function(int done, int total)? onProgress,
  }) async {
    await _enqueue(() => _sweepTemps(directories));
    final all = paths.toList();
    final counts = <ProtectOutcome, int>{};
    for (var i = 0; i < all.length; i++) {
      final outcome = toPlain
          ? await unprotect(all[i])
          : await _enqueue(() => _protect(all[i]));
      counts[outcome] = (counts[outcome] ?? 0) + 1;
      onProgress?.call(i + 1, all.length);
    }
    if ((counts[ProtectOutcome.sealed] ?? 0) > 0 ||
        (counts[ProtectOutcome.unsealed] ?? 0) > 0 ||
        (counts[ProtectOutcome.failed] ?? 0) > 0) {
      _log.info('Recording migration: $counts');
    }
    return counts;
  }

  /// The plain WAV bytes of the recording at [path], sealed or not.
  /// Throws [FileSystemException] when it cannot be read and
  /// [RecordingLockedException] when it is sealed but cannot be opened.
  Future<Uint8List> read(String path) async {
    final bytes = await File(path).readAsBytes();
    if (!isSealedRecording(bytes)) return bytes;
    final key = await _recordingKey();
    if (key == null) {
      throw RecordingLockedException(path, 'data key not available');
    }
    try {
      return await _openOff(bytes, key);
    } on RecordingCipherException catch (e) {
      throw RecordingLockedException(path, e.message);
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<ProtectOutcome> _protect(String path) async {
    final file = File(path);
    final temp = File('$path$protectTempSuffix');
    try {
      if (!await file.exists()) return ProtectOutcome.missing;
      if (isSealedRecording(await _head(file))) {
        return ProtectOutcome.alreadySealed;
      }
      final key = await _recordingKey();
      if (key == null) return ProtectOutcome.noKey;

      final plain = await file.readAsBytes();
      final sealed = await _sealOff(plain, key);
      await _writeTemp(temp, sealed);
      final written = await temp.readAsBytes();
      if (!await _verifyOff(written, plain, key)) {
        throw const FileSystemException('read-back mismatch');
      }

      // The recording may have been evicted or replaced while sealing.
      if (!await file.exists() || await file.length() != plain.length) {
        await _deleteQuietly(temp);
        return ProtectOutcome.missing;
      }
      await temp.rename(path);
      return ProtectOutcome.sealed;
    } on Object catch (e) {
      _log.warning('Recording could not be sealed, kept as it is: $e');
      await _deleteQuietly(temp);
      return ProtectOutcome.failed;
    }
  }

  Future<ProtectOutcome> _unprotect(String path) async {
    final file = File(path);
    final temp = File('$path$protectTempSuffix');
    try {
      if (!await file.exists()) return ProtectOutcome.missing;
      if (!isSealedRecording(await _head(file))) {
        return ProtectOutcome.alreadyPlain;
      }
      final key = await _recordingKey();
      if (key == null) return ProtectOutcome.noKey;

      final sealed = await file.readAsBytes();
      final plain = await _openOff(sealed, key);
      await _writeTemp(temp, plain);
      final written = await temp.readAsBytes();
      if (!await _sameOff(written, plain)) {
        throw const FileSystemException('read-back mismatch');
      }

      // The recording may have been evicted or replaced meanwhile.
      if (!await file.exists() || await file.length() != sealed.length) {
        await _deleteQuietly(temp);
        return ProtectOutcome.missing;
      }
      await temp.rename(path);
      return ProtectOutcome.unsealed;
    } on Object catch (e) {
      _log.warning('Recording could not be opened back, kept sealed: $e');
      await _deleteQuietly(temp);
      return ProtectOutcome.failed;
    }
  }

  Future<void> _sweepTemps(Iterable<String> directories) async {
    for (final dir in directories) {
      try {
        final d = Directory(dir);
        if (!await d.exists()) continue;
        await for (final entity in d.list(followLinks: false)) {
          if (entity is File && entity.path.endsWith(protectTempSuffix)) {
            await _deleteQuietly(entity);
          }
        }
      } on Object catch (e) {
        _log.warning('Leftover temp files could not be removed: $e');
      }
    }
  }

  Future<Uint8List?> _recordingKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final List<int>? dataKey;
    try {
      dataKey = await _dataKey();
    } on Object catch (e) {
      _log.warning('Data key could not be read: $e');
      return null;
    }
    if (dataKey == null) return null;
    return _key = deriveRecordingKey(dataKey);
  }

  // Static, so the isolate closures capture only their arguments.
  static Future<Uint8List> _sealOff(Uint8List plain, Uint8List key) =>
      Isolate.run(() => sealRecording(plain, key));

  static Future<Uint8List> _openOff(Uint8List sealed, Uint8List key) =>
      Isolate.run(() => openRecording(sealed, key));

  static Future<bool> _verifyOff(
    Uint8List written,
    Uint8List plain,
    Uint8List key,
  ) => Isolate.run(() {
    try {
      return listEquals(openRecording(written, key), plain);
    } on RecordingCipherException {
      return false;
    }
  });

  static Future<bool> _sameOff(Uint8List a, Uint8List b) =>
      Isolate.run(() => listEquals(a, b));

  static bool _alwaysOn() => true;

  static Future<Uint8List> _head(File file) async {
    final raf = await file.open();
    try {
      return await raf.read(recordingMagic.length);
    } finally {
      await raf.close();
    }
  }

  static Future<void> _defaultWriteTemp(File temp, Uint8List bytes) =>
      temp.writeAsBytes(bytes, flush: true);

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      // A leftover temp file is removed by the next migration.
      _log.debug('Temp file not removed yet: $e');
    }
  }
}

/// The app-wide vault. Its key comes through the data-key consent flow
/// ([DataKeyAccessNotifier.obtainForUse]) and its one [DataKeyStore].
final recordingVaultProvider = Provider<RecordingVault>((ref) {
  final access = ref.read(dataKeyAccessProvider.notifier);
  var fallbackLogged = false;
  var missingLogged = false;
  return RecordingVault(
    encryptionOn: encryptionOnThisSession,
    dataKey: () async {
      final result = await access.obtainForUse('recordings');
      switch (result) {
        case DataKeyReady():
          if (result.usesFileFallback && !fallbackLogged) {
            fallbackLogged = true;
            _log.info('Recordings use the data key from the file fallback');
          }
          return result.key.bytes;
        case DataKeyLost() || DataKeyUnavailable():
          if (!missingLogged) {
            missingLogged = true;
            _log.warning('Recordings stay unencrypted for now: $result');
          }
          return null;
      }
    },
  );
});
