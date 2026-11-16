/// WhisPaste's own data key (#1019, part of #591).
///
/// A random 256-bit key that later protects the history database (#1020) and
/// the recordings (#1021). It lives in the system's secret store:
///
/// - macOS (direct and Mac App Store build): login keychain,
/// - Windows: `flutter_secure_storage_windows` keeps it in a DPAPI-encrypted
///   file (`flutter_secure_storage.dat` in the application-support folder,
///   i.e. next to the data), readable only by the user's Windows account;
///   the Credential Manager is just its legacy path (#1130),
/// - Linux: Secret Service (libsecret).
///
/// All three go through [SecureKeyStore], the same storage the API keys use;
/// there is no second keychain path (#993: a dev build with its own bundle ID
/// and data folder simply gets its own marker and, if needed, its own key).
///
/// ## Marker
///
/// Next to the data, in the app-data folder, a small marker file records
/// that a key was created, where it lives and a SHA-256 fingerprint of it.
/// The fingerprint reveals nothing about the key, but it lets [obtain] tell
/// "never created" from "created, now missing or replaced". Only the first
/// case creates a key; the second is reported as [DataKeyLost], never
/// papered over with a fresh key (which would make existing data unreadable
/// without anyone noticing).
///
/// ## Linux without Secret Service
///
/// When no Secret Service answers (or libsecret is missing), the key goes
/// into a file readable by the owner only (0600) in the app-data folder, and
/// [DataKeyReady.usesFileFallback] tells the caller to show
/// `dataKeyFileFallbackHint`. Once the fallback is chosen it sticks: the
/// marker says "file", so a Secret Service that appears later does not split
/// the key in two. A merely *locked* keyring never triggers the fallback; it
/// is reported as [DataKeyUnavailable] so the user can unlock it.
///
/// ## Restoring and replacing (#1167)
///
/// [restore] puts a key from a recovery code or backup file back where the
/// marker says it lives (or, on a fresh data folder, where a first need would
/// put it). A backup whose fingerprint differs from the marker is refused, so
/// a wrong backup never replaces anything. A different key already sitting in
/// the store or the fallback file is set aside under an archive name first,
/// never overwritten.
///
/// [replaceLostKey] is the deliberate way out of [DataKeyLost]: the marker
/// and the fallback file are renamed (kept, not deleted), then a first need
/// runs as on a fresh install. Recordings sealed with the lost key stay as
/// they are and stay unreadable until that key is restored.
///
/// ## Secrecy
///
/// The key bytes are only reachable through [DataKey.bytes]. Its
/// `toString` is redacted, nothing here logs a key, and the storage name is
/// not part of [allSecureKeys] or [apiKeyMapping], so neither the settings
/// export nor a reset of the API keys touches it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:path/path.dart' as p;

import '../../services/path_service.dart' as paths;
import '../logging/app_logger.dart';
import '../platform/posix_native.dart';
import 'secure_key_store.dart';

/// The one [DataKeyStore] of the app (its queue serialises first needs, its
/// cache keeps a found key for the session). The recordings use it too: a
/// second instance would ask the system store a second time (#1161).
/// Lives here, not in `data_key_access.dart`, so the history database
/// (#1020) can read it without an import cycle through the settings.
final dataKeyStoreProvider = Provider<DataKeyStore>(
  (ref) => DataKeyStore(ref.watch(secureKeyStoreProvider)),
);

final _log = AppLogger('DataKeyStore');

/// Secure-storage name of the data key.
const dataKeyStorageName = 'wp_data_key';

/// Marker file in the app-data folder (no secret inside).
const dataKeyMarkerFileName = 'data_key.json';

/// Fallback key file in the app-data folder (Linux without Secret Service).
const dataKeyFallbackFileName = 'data_key.secret';

/// Secure-storage name prefix for a key set aside by [DataKeyStore.restore]
/// (followed by a UTC timestamp). Never read by the app again; kept so no key
/// is destroyed by a restore.
const dataKeySetAsidePrefix = 'wp_data_key.set_aside.';

/// Key length in bytes (AES-256 / XChaCha20).
const dataKeyLength = 32;

const _ownerOnlyFile = 0x180; // 0600
const _markerVersion = 1;

/// Where the data key is kept.
enum DataKeyBackend {
  /// Keychain, Credential Manager or Secret Service.
  systemKeyStore,

  /// Owner-only file in the app-data folder (Linux fallback).
  file,
}

/// Why the key cannot be used right now (it is not lost).
enum DataKeyUnavailableReason {
  /// The Linux keyring is locked; unlocking it makes the key available.
  keyringLocked,

  /// The Secret Service holding the key does not answer right now.
  keyringUnreachable,

  /// The secret store or the app-data folder failed (or the marker is
  /// unreadable). Retrying later may help; nothing was overwritten.
  storageFailed,
}

/// The data key. Never printed: [toString] is redacted.
final class DataKey {
  DataKey._(List<int> bytes) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  /// A copy of the raw key bytes.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'DataKey(<redacted>)';
}

/// Result of [DataKeyStore.obtain].
sealed class DataKeyResult {
  const DataKeyResult();
}

/// The key is available.
final class DataKeyReady extends DataKeyResult {
  const DataKeyReady(this.key, this.backend, {required this.created});

  final DataKey key;
  final DataKeyBackend backend;

  /// True when this call created the key (first need).
  final bool created;

  /// True on the Linux file fallback: show `dataKeyFileFallbackHint`.
  bool get usesFileFallback => backend == DataKeyBackend.file;

  @override
  String toString() => 'DataKeyReady($backend, created: $created)';
}

/// A key was created earlier, but it is missing or no longer the same key.
/// No new key was created; data protected with the old key cannot be read.
final class DataKeyLost extends DataKeyResult {
  const DataKeyLost(this.backend);

  /// Where the lost key was kept.
  final DataKeyBackend backend;

  @override
  String toString() => 'DataKeyLost($backend)';
}

/// The key cannot be read right now; see [reason].
final class DataKeyUnavailable extends DataKeyResult {
  const DataKeyUnavailable(this.reason);

  final DataKeyUnavailableReason reason;

  @override
  String toString() => 'DataKeyUnavailable($reason)';
}

/// Why [DataKeyStore.restore] did not restore the key. Nothing was
/// overwritten in any of these cases.
enum DataKeyRestoreFailure {
  /// The backup holds a different key than the one this data folder was
  /// protected with (the marker's fingerprint).
  otherKey,

  /// The Linux keyring is locked; unlock it and try again.
  keyringLocked,

  /// The secret store or the data folder failed. Retrying may help.
  storageFailed,
}

/// Result of [DataKeyStore.restore].
sealed class DataKeyRestoreResult {
  const DataKeyRestoreResult();
}

/// The key is back and usable.
final class DataKeyRestored extends DataKeyRestoreResult {
  const DataKeyRestored(this.ready);

  final DataKeyReady ready;

  @override
  String toString() => 'DataKeyRestored(${ready.backend})';
}

/// The key was not restored; see [failure].
final class DataKeyRestoreFailed extends DataKeyRestoreResult {
  const DataKeyRestoreFailed(this.failure);

  final DataKeyRestoreFailure failure;

  @override
  String toString() => 'DataKeyRestoreFailed($failure)';
}

/// Creates, stores and reads back the data key. See the library comment.
class DataKeyStore {
  DataKeyStore(
    this._secureStore, {
    String Function()? dataDir,
    bool? isLinux,
    bool? posix,
    Random? random,
  }) : _dataDir = dataDir ?? paths.appDataDir,
       _isLinux = isLinux ?? Platform.isLinux,
       _posix = posix ?? !Platform.isWindows,
       _random = random ?? Random.secure();

  final SecureKeyStore _secureStore;
  final String Function() _dataDir;
  final bool _isLinux;
  final bool _posix;
  final Random _random;

  /// Calls run one after another, so two first needs cannot create two keys.
  Future<void> _queue = Future<void>.value();

  /// The key once a call found it, so later needs in the same session do
  /// not ask the system store again (on macOS each read of an item written
  /// under another signature is one more prompt, #1161).
  DataKeyReady? _ready;

  /// Returns the data key, creating it on first need. Never throws.
  Future<DataKeyResult> obtain() {
    final result = _queue.then((_) async {
      final cached = _ready;
      if (cached != null) return cached;
      final fresh = await _obtain();
      if (fresh is DataKeyReady) {
        _ready = DataKeyReady(fresh.key, fresh.backend, created: false);
      }
      return fresh;
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Where an earlier first need put the key, from the marker alone, or null
  /// when no key was created yet (or the marker is unreadable). Touches no
  /// secret store, so it never triggers a system prompt (#1071).
  DataKeyBackend? recordedBackend() {
    try {
      return _readMarker()?.backend;
    } on Object catch (e) {
      _log.warning('Data key marker unreadable: ${e.runtimeType}');
      return null;
    }
  }

  /// Removes the key, the Linux fallback file and the marker. Only the
  /// factory reset calls this, and only after history and recordings were
  /// deleted (#1165): there is no way to drop the key and keep the data it
  /// protects. Throws when the key could not be removed from the store; the
  /// marker then stays, so the remaining key is never orphaned silently.
  Future<void> eraseForReset() {
    final result = _queue.then((_) async {
      await _secureStore.deleteKey(dataKeyStorageName);
      final fallback = File(_fallbackPath);
      if (fallback.existsSync()) fallback.deleteSync();
      final marker = File(_markerPath);
      if (marker.existsSync()) marker.deleteSync();
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// When the key was last backed up as recovery code or file (#1166), from
  /// the marker alone, or null when it never was. Creating or adopting a key
  /// writes a fresh marker, so a new key always starts as not backed up.
  DateTime? recordedBackupAt() {
    try {
      return _readMarker()?.backedUpAt;
    } on Object catch (e) {
      _log.warning('Data key marker unreadable: ${e.runtimeType}');
      return null;
    }
  }

  /// Notes in the marker that [key] was backed up at [at]. Does nothing and
  /// returns false when the marker belongs to a different key, so a backup
  /// of an old key never shows the current one as backed up.
  Future<bool> recordBackup(DataKey key, DateTime at) {
    final result = _queue.then((_) {
      try {
        final marker = _readMarker();
        final bytes = key._bytes;
        if (marker == null || _fingerprint(bytes) != marker.fingerprint) {
          return false;
        }
        _writeMarker(marker.backend, bytes, backedUpAt: at);
        return true;
      } on Object catch (e) {
        _log.warning('Data key backup not recorded: ${e.runtimeType}');
        return false;
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Restores the key [bytes] from a recovery code or backup file (#1167).
  /// Never throws and never overwrites a different key; see the library
  /// comment.
  Future<DataKeyRestoreResult> restore(List<int> bytes) {
    final copy = List<int>.of(bytes);
    final result = _queue.then((_) => _restore(copy));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Leaves a lost key behind and creates (or adopts) a new one (#1167).
  /// Only acts in the lost state; otherwise it returns what [obtain] would.
  /// The old marker and fallback file are renamed, never deleted.
  Future<DataKeyResult> replaceLostKey({DateTime? now}) {
    final result = _queue.then((_) => _replaceLost(now ?? DateTime.now()));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Whether [encoded] (the stored base64 form) is the key the marker
  /// fingerprints. True when no marker exists yet (nothing to compare);
  /// false for an unreadable marker or a malformed value. Touches no secret
  /// store. Logs 8-character fingerprint prefixes only.
  bool matchesMarker(String encoded) {
    try {
      final marker = _readMarker();
      if (marker == null) return true;
      final bytes = _decode(encoded);
      final ok = bytes != null && _fingerprint(bytes) == marker.fingerprint;
      if (!ok) {
        _log.warning(
          'Value does not match the data key marker: '
          'read=${bytes == null ? 'none' : _shortFingerprint(bytes)} '
          'marker=${_short(marker.fingerprint)}',
        );
      }
      return ok;
    } on Object catch (e) {
      _log.warning('Data key marker unreadable: ${e.runtimeType}');
      return false;
    }
  }

  String get _markerPath => p.join(_dataDir(), dataKeyMarkerFileName);
  String get _fallbackPath => p.join(_dataDir(), dataKeyFallbackFileName);

  Future<DataKeyResult> _obtain() async {
    final _Marker? marker;
    try {
      marker = _readMarker();
    } on Object catch (e) {
      _log.warning('Data key marker unreadable: ${e.runtimeType}');
      return const DataKeyUnavailable(DataKeyUnavailableReason.storageFailed);
    }
    try {
      if (marker == null) return await _firstNeed();
      return switch (marker.backend) {
        DataKeyBackend.file => _readFromFile(marker),
        DataKeyBackend.systemKeyStore => await _readFromSystemStore(marker),
      };
    } on Object catch (e) {
      _log.warning('Data key storage failed: ${_describe(e)}');
      return const DataKeyUnavailable(DataKeyUnavailableReason.storageFailed);
    }
  }

  Future<DataKeyResult> _readFromSystemStore(_Marker marker) async {
    final String? encoded;
    try {
      encoded = await _secureStore.readKey(dataKeyStorageName);
    } on PlatformException catch (e) {
      if (e.code == keyringLockedCode) {
        return DataKeyUnavailable(
          isKeyringUnreachable(e)
              ? DataKeyUnavailableReason.keyringUnreachable
              : DataKeyUnavailableReason.keyringLocked,
        );
      }
      rethrow;
    }
    return _check(_decode(encoded), marker);
  }

  DataKeyResult _readFromFile(_Marker marker) {
    final file = File(_fallbackPath);
    final bytes = file.existsSync() ? _decode(file.readAsStringSync()) : null;
    return _check(bytes, marker);
  }

  DataKeyResult _check(List<int>? bytes, _Marker marker) {
    if (bytes == null || _fingerprint(bytes) != marker.fingerprint) {
      _log.warning(
        'Data key lost (${marker.backend.name}): '
        'read=${bytes == null ? 'none' : _shortFingerprint(bytes)} '
        'marker=${_short(marker.fingerprint)}',
      );
      return DataKeyLost(marker.backend);
    }
    return DataKeyReady(DataKey._(bytes), marker.backend, created: false);
  }

  Future<DataKeyResult> _firstNeed() async {
    // A key without marker is left over from an interrupted first need:
    // adopt it rather than replacing it.
    if (_isLinux) {
      final leftover = File(_fallbackPath);
      if (leftover.existsSync()) {
        final bytes = _decode(leftover.readAsStringSync());
        if (bytes != null) return _adopt(bytes, DataKeyBackend.file);
      }
    }
    try {
      final existing = _decode(await _secureStore.readKey(dataKeyStorageName));
      if (existing != null) {
        return _adopt(existing, DataKeyBackend.systemKeyStore);
      }
      final bytes = _generate();
      await _secureStore.writeKey(dataKeyStorageName, _encode(bytes));
      // Read back: a store that accepts writes but keeps nothing (macOS
      // -34018, a broken Linux backend) must not leave us with a marker.
      final stored = _decode(await _secureStore.readKey(dataKeyStorageName));
      if (stored == null || !listEquals(stored, bytes)) {
        throw const _NotPersisted();
      }
      _writeMarker(DataKeyBackend.systemKeyStore, bytes);
      return DataKeyReady(
        DataKey._(bytes),
        DataKeyBackend.systemKeyStore,
        created: true,
      );
    } on Object catch (e) {
      if (e is PlatformException &&
          e.code == keyringLockedCode &&
          !isKeyringUnreachable(e)) {
        return const DataKeyUnavailable(DataKeyUnavailableReason.keyringLocked);
      }
      if (!_isLinux) rethrow;
      _log.warning(
        'No usable Secret Service (${_describe(e)}); '
        'keeping the data key in an owner-only file',
      );
      return _createFileKey();
    }
  }

  DataKeyResult _adopt(List<int> bytes, DataKeyBackend backend) {
    _writeMarker(backend, bytes);
    return DataKeyReady(DataKey._(bytes), backend, created: false);
  }

  DataKeyResult _createFileKey() {
    final bytes = _generate();
    _writeFileKey(bytes);
    _writeMarker(DataKeyBackend.file, bytes);
    return DataKeyReady(DataKey._(bytes), DataKeyBackend.file, created: true);
  }

  void _writeFileKey(List<int> bytes) {
    Directory(_dataDir()).createSync(recursive: true);
    final file = File(_fallbackPath);
    // Owner-only before the key goes in.
    file.writeAsStringSync('', flush: true);
    if (_posix && !nativeChmod(file.path, _ownerOnlyFile)) {
      file.deleteSync();
      throw const FileSystemException('chmod 0600 failed for data key file');
    }
    file.writeAsStringSync(_encode(bytes), flush: true);
  }

  Future<DataKeyRestoreResult> _restore(List<int> bytes) async {
    if (bytes.length != dataKeyLength) {
      return const DataKeyRestoreFailed(DataKeyRestoreFailure.storageFailed);
    }
    final _Marker? marker;
    try {
      marker = _readMarker();
    } on Object catch (e) {
      // An unreadable marker is not replaced by a guess.
      _log.warning('Data key marker unreadable: ${e.runtimeType}');
      return const DataKeyRestoreFailed(DataKeyRestoreFailure.storageFailed);
    }
    if (marker != null && marker.fingerprint != _fingerprint(bytes)) {
      _log.warning('Data key restore refused: backup holds another key');
      return const DataKeyRestoreFailed(DataKeyRestoreFailure.otherKey);
    }
    final stamp = _stamp(DateTime.now());
    try {
      final DataKeyBackend backend;
      if (marker?.backend == DataKeyBackend.file) {
        _putFileKey(bytes, stamp);
        backend = DataKeyBackend.file;
      } else {
        backend = await _putSystemKey(bytes, stamp);
      }
      // A matching marker keeps its backup date; a fresh folder or a backend
      // switch writes one. Restored from a backup means a backup exists.
      if (marker == null || marker.backend != backend) {
        _writeMarker(
          backend,
          bytes,
          backedUpAt: marker?.backedUpAt ?? DateTime.now(),
        );
      }
      _log.info('Data key restored (${backend.name})');
      return DataKeyRestored(
        DataKeyReady(DataKey._(bytes), backend, created: false),
      );
    } on _KeyringLocked {
      return const DataKeyRestoreFailed(DataKeyRestoreFailure.keyringLocked);
    } on Object catch (e) {
      _log.warning('Data key restore failed: ${_describe(e)}');
      return const DataKeyRestoreFailed(DataKeyRestoreFailure.storageFailed);
    }
  }

  /// Writes [bytes] to the system store (a different key there is set aside
  /// first), falling back to the owner-only file on Linux like a first need.
  Future<DataKeyBackend> _putSystemKey(List<int> bytes, String stamp) async {
    try {
      final existing = await _secureStore.readKey(dataKeyStorageName);
      final decoded = _decode(existing);
      if (decoded != null && listEquals(decoded, bytes)) {
        return DataKeyBackend.systemKeyStore;
      }
      if (existing != null && existing.trim().isNotEmpty) {
        await _secureStore.writeKey('$dataKeySetAsidePrefix$stamp', existing);
      }
      await _secureStore.writeKey(dataKeyStorageName, _encode(bytes));
      final stored = _decode(await _secureStore.readKey(dataKeyStorageName));
      if (stored == null || !listEquals(stored, bytes)) {
        throw const _NotPersisted();
      }
      return DataKeyBackend.systemKeyStore;
    } on Object catch (e) {
      if (e is PlatformException &&
          e.code == keyringLockedCode &&
          !isKeyringUnreachable(e)) {
        throw const _KeyringLocked();
      }
      if (!_isLinux) rethrow;
      _log.warning(
        'No usable Secret Service (${_describe(e)}); '
        'restoring the data key into an owner-only file',
      );
      _putFileKey(bytes, stamp);
      return DataKeyBackend.file;
    }
  }

  /// Writes [bytes] to the owner-only fallback file. A file holding anything
  /// else is renamed first.
  void _putFileKey(List<int> bytes, String stamp) {
    final file = File(_fallbackPath);
    if (file.existsSync()) {
      final current = _decode(file.readAsStringSync());
      if (current != null && listEquals(current, bytes)) return;
      file.renameSync(_archivePath(dataKeyFallbackFileName, stamp));
    }
    _writeFileKey(bytes);
  }

  Future<DataKeyResult> _replaceLost(DateTime now) async {
    final current = await _obtain();
    if (current is! DataKeyLost) return current;
    try {
      final stamp = _stamp(now);
      File(_markerPath).renameSync(_archivePath(dataKeyMarkerFileName, stamp));
      final fallback = File(_fallbackPath);
      if (fallback.existsSync()) {
        fallback.renameSync(_archivePath(dataKeyFallbackFileName, stamp));
      }
      _log.info('Lost data key left behind; creating a new one');
      return await _firstNeed();
    } on Object catch (e) {
      _log.warning('Data key not replaced: ${_describe(e)}');
      return const DataKeyUnavailable(DataKeyUnavailableReason.storageFailed);
    }
  }

  /// `data_key.json` → `data_key.<stamp>.lost.json`.
  String _archivePath(String name, String stamp) {
    final ext = p.extension(name);
    return p.join(
      _dataDir(),
      '${p.basenameWithoutExtension(name)}.$stamp.lost$ext',
    );
  }

  List<int> _generate() =>
      List<int>.generate(dataKeyLength, (_) => _random.nextInt(256));

  _Marker? _readMarker() {
    final file = File(_markerPath);
    if (!file.existsSync()) return null;
    return _Marker.parse(file.readAsStringSync());
  }

  void _writeMarker(
    DataKeyBackend backend,
    List<int> bytes, {
    DateTime? backedUpAt,
  }) {
    Directory(_dataDir()).createSync(recursive: true);
    final target = File(_markerPath);
    final tmp = File('${target.path}.tmp');
    tmp.writeAsStringSync(
      jsonEncode({
        'version': _markerVersion,
        'backend': backend.name,
        'fingerprint': _fingerprint(bytes),
        if (backedUpAt != null)
          'backedUpAt': backedUpAt.toUtc().toIso8601String(),
      }),
      flush: true,
    );
    tmp.renameSync(target.path);
  }
}

/// Base64 of the key, the form kept in the store and the fallback file.
String _encode(List<int> bytes) => base64Encode(bytes);

/// Null for a missing, empty or malformed value.
List<int>? _decode(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  try {
    final bytes = base64Decode(value.trim());
    return bytes.length == dataKeyLength ? bytes : null;
  } on FormatException {
    return null;
  }
}

String _fingerprint(List<int> bytes) => sha256.convert(bytes).toString();

/// First 8 hex characters of a fingerprint: enough to tell keys apart in a
/// log, useless as a secret.
String _short(String fingerprint) =>
    fingerprint.length <= 8 ? fingerprint : fingerprint.substring(0, 8);

String _shortFingerprint(List<int> bytes) => _short(_fingerprint(bytes));

/// Error type and code only, so no stored value can reach the log.
String _describe(Object e) => e is PlatformException
    ? 'PlatformException(${e.code})'
    : '${e.runtimeType}';

class _NotPersisted implements Exception {
  const _NotPersisted();
}

class _KeyringLocked implements Exception {
  const _KeyringLocked();
}

/// UTC timestamp safe for file and storage names, e.g. `20261110T142301Z`.
String _stamp(DateTime at) {
  final u = at.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

final class _Marker {
  const _Marker(this.backend, this.fingerprint, this.backedUpAt);

  final DataKeyBackend backend;
  final String fingerprint;

  /// Last backup as recovery code or file (#1166); null when none.
  final DateTime? backedUpAt;

  /// Throws [FormatException] on anything it does not understand.
  static _Marker parse(String raw) {
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) throw const FormatException('marker');
    final backend = DataKeyBackend.values.where(
      (b) => b.name == json['backend'],
    );
    final fingerprint = json['fingerprint'];
    if (backend.isEmpty || fingerprint is! String || fingerprint.isEmpty) {
      throw const FormatException('marker');
    }
    final backedUpAt = json['backedUpAt'];
    return _Marker(
      backend.single,
      fingerprint,
      backedUpAt is String ? DateTime.tryParse(backedUpAt) : null,
    );
  }
}

/// SHA-256 fingerprint as stored in the marker, for tests.
@visibleForTesting
String dataKeyFingerprint(List<int> bytes) => _fingerprint(bytes);
