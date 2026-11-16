/// Secure storage wrapper for API keys.
///
/// Uses platform-native secret stores (macOS Keychain, Linux libsecret, and
/// on Windows a DPAPI-encrypted file in the application-support folder) via
/// [FlutterSecureStorage].
/// All keys are namespaced with a `wp_` prefix.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../logging/app_logger.dart';
import 'linux_keyring_lock_probe.dart';
import 'secure_access_gate.dart';

export 'linux_keyring_lock_probe.dart' show KeyringAvailability;
export 'secure_access_gate.dart'
    show
        isSecretNeedsConsent,
        secretNeedsConsentCode,
        secureAccessGate,
        withSecureTrigger,
        withoutKeyringCreation;

final _log = AppLogger('SecureKeyStore');

/// Maps AppSettings field names to their secure-storage key names.
const apiKeyMapping = <String, String>{
  'openAiApiKey': 'wp_openai_api_key',
  'deepgramApiKey': 'wp_deepgram_api_key',
  'customEndpointApiKey': 'wp_custom_endpoint_api_key',
};

/// Restore token of the Linux RemoteDesktop portal (keyboard consent). A
/// secret, but no API key: never exported, erased with the API keys.
const linuxPortalRestoreTokenKey = 'wp_linux_portal_restore_token';

/// Every secure-storage key a reset erases.
final allSecureKeys = [...apiKeyMapping.values, linuxPortalRestoreTokenKey];

/// Legacy backend: the file-based login keychain on macOS (ignored
/// elsewhere). Every secret lived here before ADR 0036; builds without a
/// keychain access group (debug, ad-hoc) still use it, because
/// the data-protection keychain fails there with errSecMissingEntitlement
/// (-34018) and reads return null.
const legacySecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

/// macOS data-protection keychain in the app's default access group
/// `<TeamID>.de.whispaste.app`: the first `keychain-access-groups` entry
/// (Developer ID build) or the application identifier (Store build), both
/// backed by a provisioning profile. No password prompt, and items survive
/// updates, reinstalls and switching between a local build and the installed
/// one (ADR 0036).
const dataProtectionSecureStorage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: true),
);

/// The backends a [SecureKeyStore] uses: [primary] receives every write;
/// [legacy], when set, is a read fallback and is cleared on delete.
typedef SecureStorages = ({
  FlutterSecureStorage primary,
  FlutterSecureStorage? legacy,
});

/// Picks the backends for this build. Only a macOS build with the access
/// group moves to the data-protection keychain; it still reads the legacy
/// keychain as a fallback, so secrets stored before ADR 0036 stay readable
/// until they are moved (#1155), and deletes both so a reset leaves no old
/// value behind.
SecureStorages secureStoragesFor({
  required bool isMacOS,
  required bool hasAccessGroup,
}) => isMacOS && hasAccessGroup
    ? (primary: dataProtectionSecureStorage, legacy: legacySecureStorage)
    : (primary: legacySecureStorage, legacy: null);

const _keychainScopeChannel = MethodChannel('com.whispaste.keychain_scope');

/// Whether this macOS build has a keychain access group, from
/// `keychain-access-groups` or the application identifier (native
/// `KeychainScopeHost`). Null when the host could not answer.
Future<bool?> _hasKeychainAccessGroup() async {
  try {
    return await _keychainScopeChannel.invokeMethod<bool>('hasAccessGroup');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

SecureStorages? _resolvedDefaultStorages;

/// The backends of this process, resolved once. An unanswered entitlement
/// query falls back to the legacy keychain for that call and is asked again
/// next time, so an early call cannot pin the wrong keychain.
Future<SecureStorages> resolveDefaultSecureStorages() async {
  final resolved = _resolvedDefaultStorages;
  if (resolved != null) return resolved;
  if (!Platform.isMacOS) {
    return _resolvedDefaultStorages = secureStoragesFor(
      isMacOS: false,
      hasAccessGroup: false,
    );
  }
  final hasGroup = await _hasKeychainAccessGroup();
  final storages = secureStoragesFor(
    isMacOS: true,
    hasAccessGroup: hasGroup ?? false,
  );
  if (hasGroup != null) _resolvedDefaultStorages = storages;
  return storages;
}

/// Thrown when one or more API keys could not be removed from secure storage.
/// [keys] holds the storage names only, never the values.
class SecureKeysNotRemovedException implements Exception {
  const SecureKeysNotRemovedException(this.keys);

  final List<String> keys;

  @override
  String toString() => 'SecureKeysNotRemovedException(${keys.join(', ')})';
}

/// [PlatformException.code] of a skipped call to a locked or unreachable
/// keyring. [PlatformException.details] is `'locked'` or `'unreachable'`.
const keyringLockedCode = 'KeyringLocked';

/// Whether [error] means "no Secret Service on this machine right now", as
/// opposed to a keyring that is merely locked.
bool isKeyringUnreachable(Object error) =>
    error is PlatformException &&
    error.code == keyringLockedCode &&
    error.details == 'unreachable';

class SecureKeyStore {
  /// [quietReader] reads while [gate] holds prompts back (#1161). Without an
  /// injected [storage] the platform's quiet reader is used; a store built
  /// on an injected storage (tests) reads that storage directly.
  SecureKeyStore([
    FlutterSecureStorage? storage,
    Future<KeyringAvailability> Function()? probeKeyring,
    DateTime Function()? clock,
    QuietSecretReader? quietReader,
    SecureAccessGate? gate,
  ]) : _storages = storage == null
           ? resolveDefaultSecureStorages
           : (() async => (primary: storage, legacy: null)),
       _probeKeyring = probeKeyring ?? probeLinuxKeyring,
       _clock = clock ?? DateTime.now,
       _quietReader =
           quietReader ?? (storage == null ? platformQuietReader() : null),
       _gate = gate ?? secureAccessGate;

  /// A store over explicit backends: writes go to [primary], reads fall back
  /// to [legacy], deletes clear both (see [secureStoragesFor]).
  SecureKeyStore.layered({
    required FlutterSecureStorage primary,
    FlutterSecureStorage? legacy,
    Future<KeyringAvailability> Function()? probeKeyring,
    DateTime Function()? clock,
    this._quietReader,
    SecureAccessGate? gate,
  }) : _storages = (() async => (primary: primary, legacy: legacy)),
       _probeKeyring = probeKeyring ?? probeLinuxKeyring,
       _clock = clock ?? DateTime.now,
       _gate = gate ?? secureAccessGate;

  final Future<SecureStorages> Function() _storages;
  final Future<KeyringAvailability> Function() _probeKeyring;
  final DateTime Function() _clock;
  QuietSecretReader? _quietReader;
  final SecureAccessGate _gate;

  /// How long an unreachable Secret Service stays marked before it is probed
  /// again. A service that starts late (gnome-keyring after login) must not
  /// disable the keys for the whole session; within the window each call
  /// fails at once, so a factory reset does not wait once per key.
  static const unreachableRetryAfter = Duration(seconds: 30);

  /// When the Secret Service was last found unreachable, or null. A locked
  /// keyring is probed again on every call: that answer is instant, and the
  /// user may unlock it meanwhile.
  DateTime? _unreachableSince;

  /// Never hand a locked or unreachable keyring to the plugin: on Linux it
  /// would unlock it, or wait for the Secret Service, synchronously on the
  /// GTK main thread and freeze the app, before its window appears (GitHub
  /// #151) or during a recording (XP-7-01). Callers already treat
  /// `KeyringLocked` as "keys unavailable for now".
  ///
  /// A write under [withoutKeyringCreation] (start-time work such as the
  /// plaintext key migration) is also refused while no default collection
  /// exists and the gate is closed: the plugin would create it and the system
  /// would ask for a password before the app explained anything (#1164).
  /// Reads are unaffected.
  Future<void> _ensureKeyringUnlocked({bool isWrite = false}) async {
    final since = _unreachableSince;
    if (since != null && _clock().difference(since) < unreachableRetryAfter) {
      throw _keyringUnavailable('unreachable');
    }
    switch (await _probeKeyring()) {
      case KeyringAvailability.usable:
        _unreachableSince = null;
        return;
      case KeyringAvailability.missing:
        _unreachableSince = null;
        if (!isWrite || _gate.promptsAllowed || !keyringCreationForbidden()) {
          return;
        }
        throw _keyringUnavailable('missing');
      case KeyringAvailability.locked:
        _unreachableSince = null;
        throw _keyringUnavailable('locked');
      case KeyringAvailability.unreachable:
        _unreachableSince = _clock();
        throw _keyringUnavailable('unreachable');
    }
  }

  static PlatformException _keyringUnavailable(String state) =>
      PlatformException(
        code: keyringLockedCode,
        message: 'Default keyring is $state; not calling it from the UI thread',
        details: state,
      );

  Future<String?> readKey(String key) => _logged('read', key, () async {
    await _ensureKeyringUnlocked();
    final storages = await _storages();
    final quiet = _quietReader;
    if (quiet != null && !_gate.promptsAllowed) {
      // Only the file-based login keychain can prompt. With the
      // data-protection keychain as primary (ADR 0036) that is the legacy
      // fallback: the primary is read as usual, the fallback quietly.
      final legacy = storages.legacy;
      if (legacy != null) {
        final value = await storages.primary.read(key: key);
        if (value != null) return value;
      }
      final value = await _readQuietly(quiet, key);
      if (value != _useStorage) return value as String?;
    }
    return _read(storages, key);
  });

  static Future<String?> _read(SecureStorages storages, String key) async {
    final value = await storages.primary.read(key: key);
    if (value != null) return value;
    return storages.legacy?.read(key: key);
  }

  Future<void> writeKey(String key, String value) =>
      _logged('write', key, () async {
        await _ensureKeyringUnlocked(isWrite: true);
        await (await _storages()).primary.write(key: key, value: value);
      });

  Future<void> deleteKey(String key) => _logged('delete', key, () async {
    await _ensureKeyringUnlocked();
    final storages = await _storages();
    await storages.primary.delete(key: key);
    await storages.legacy?.delete(key: key);
  });

  /// Reads all API keys and returns a map of secure-storage key → value.
  /// A key held back for a prompt (#1161) is left out; the caller reads
  /// again once [SecureAccessGate.allowPrompts] ran.
  Future<Map<String, String>> readAllApiKeys() async {
    // Named by its entries so a locked or unreachable keyring (Linux) shows
    // which secrets stayed unread, not just "api keys" (#1164).
    await _logged(
      'read',
      apiKeyMapping.values.join(', '),
      _ensureKeyringUnlocked,
    );
    final result = <String, String>{};
    for (final secureKey in apiKeyMapping.values) {
      final String? value;
      try {
        value = await readKey(secureKey);
      } on PlatformException catch (e) {
        if (isSecretNeedsConsent(e)) continue;
        rethrow;
      }
      if (value != null && value.isNotEmpty) {
        result[secureKey] = value;
      }
    }
    return result;
  }

  /// Marker for "the quiet path is not available, read the storage".
  static const Object _useStorage = Object();

  Future<Object?> _readQuietly(QuietSecretReader quiet, String key) async {
    final QuietReadResult result;
    try {
      result = await quiet(key);
    } on MissingPluginException {
      // A host without the native channel (tests, an old runner): the quiet
      // path cannot help here, the storage behaves as before.
      _quietReader = null;
      return _useStorage;
    }
    switch (result.status) {
      case QuietReadStatus.ok:
        return result.value;
      case QuietReadStatus.missing:
        return null;
      case QuietReadStatus.needsConsent:
        throw PlatformException(
          code: secretNeedsConsentCode,
          message: 'Reading needs a system prompt; held back until explained',
          details: key,
        );
      case QuietReadStatus.error:
        throw PlatformException(
          code: 'QuietReadFailed',
          message: 'Quiet key-store read failed (${result.code})',
          details: key,
        );
    }
  }

  /// Runs [body] and logs a failure with the entry's storage name and the
  /// trigger that asked for it — never the value (#1161).
  Future<T> _logged<T>(
    String operation,
    String key,
    Future<T> Function() body,
  ) async {
    try {
      return await body();
    } on Object catch (e) {
      final reason = e is PlatformException
          ? '${e.code}${e.details is String && e.details != key ? ' ${e.details}' : ''}'
          : e.runtimeType.toString();
      final line =
          'Key store $operation of "$key" failed: $reason '
          '(trigger: ${currentSecureTrigger()})';
      if (e is PlatformException &&
          (e.code == keyringLockedCode || isSecretNeedsConsent(e))) {
        _log.info(line);
      } else {
        _log.warning(line);
      }
      rethrow;
    }
  }
}

/// Deletes every API key and the other secrets in [allSecureKeys], trying
/// all of them even after a failure. Returns the storage names that could
/// not be removed (never the values). A free function so the
/// [SecureKeyStore] interface stays unchanged for fakes.
Future<List<String>> deleteAllApiKeys(SecureKeyStore store) async {
  final failed = <String>[];
  for (final secureKey in allSecureKeys) {
    try {
      await store.deleteKey(secureKey);
    } catch (_) {
      failed.add(secureKey);
    }
  }
  return failed;
}

/// Riverpod provider for the secure key store.
final secureKeyStoreProvider = Provider<SecureKeyStore>(
  (ref) => SecureKeyStore(),
);
