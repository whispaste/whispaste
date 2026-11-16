/// Keeps system key-store prompts behind an explanation (#1161).
///
/// On macOS every secret lives in the file-based login keychain, bound by an
/// ACL to the code signature that wrote it. A build signed differently (a
/// local Developer-ID build over the App Store install, or the other way
/// round) gets one system prompt per item and read. Such a prompt must never
/// appear before the app has said why it needs the key store.
///
/// - [secureAccessGate] starts closed on every launch. While it is closed,
///   [SecureKeyStore.readKey] reads through [QuietSecretReader], which never
///   shows a prompt: an item this build may not read without asking fails
///   with [secretNeedsConsentCode] instead.
/// - The gate opens on a deliberate tap after the data-key explanation
///   (`DataKeyAccessNotifier.request`). Listeners then read again what was
///   held back, together and once.
/// - [withSecureTrigger] names the caller of a read, so the log can say which
///   entry (name only, never the value) failed and who asked for it.
///
/// Writes and deletes are not routed through the gate: they only follow a
/// user action (saving a key, regenerating a token), never the start.
///
/// Windows and Linux follow the same rules without a quiet reader (#1164),
/// so [platformQuietReader] is null there:
/// - Windows stores secrets in a DPAPI-encrypted file bound to the user
///   account. Reading never shows a system dialog, whatever the gate says.
/// - Linux asks `probeLinuxKeyring` before every access. A locked (or
///   unreachable) default collection fails with `KeyringLocked` and the
///   plugin, which would show the unlock dialog, is never called. The user
///   unlocks the keyring outside the app and retries from the data-key
///   explanation, so the app never opens that dialog on its own.
/// Failures on all three systems are logged the same way: entry name and
/// trigger, never the value.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

final _log = AppLogger('SecureAccessGate');

/// [PlatformException.code] of a quiet read that would have needed a system
/// prompt. [PlatformException.details] is the entry's storage name.
const secretNeedsConsentCode = 'SecretNeedsConsent';

/// Whether [error] is a quiet read that was held back for a prompt.
bool isSecretNeedsConsent(Object error) =>
    error is PlatformException && error.code == secretNeedsConsentCode;

/// Whether the app may let the system key store prompt the user.
class SecureAccessGate {
  bool _open = false;
  final _listeners = <void Function()>[];

  /// False until the user deliberately allowed access after an explanation.
  bool get promptsAllowed => _open;

  /// Opens the gate for the rest of the session and tells every listener once.
  void allowPrompts(String reason) {
    if (_open) return;
    _open = true;
    _log.info('Key-store prompts allowed ($reason)');
    _notify();
  }

  /// Tells the listeners again although the gate is already open (#1217).
  ///
  /// The first listener run may have found the key store locked (Linux
  /// keyring). Once the user unlocked it and retries from the data-key
  /// explanation, what was held back is read again without a restart. Does
  /// nothing while the gate is closed: [allowPrompts] notifies then.
  void retryHeldBack(String reason) {
    if (!_open) return;
    _log.info('Re-reading held back secrets ($reason)');
    _notify();
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      try {
        listener();
      } on Object catch (e) {
        _log.warning('Gate listener failed: ${e.runtimeType}');
      }
    }
  }

  /// Calls [listener] when the gate opens. Returns the function that removes
  /// it again.
  void Function() addOpenListener(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @visibleForTesting
  void reset() {
    _open = false;
    _listeners.clear();
  }
}

/// The app's one gate.
final secureAccessGate = SecureAccessGate();

const _triggerZoneKey = #whispasteSecureTrigger;

/// Runs [body] with [trigger] as the name of whoever asked for the secrets
/// it reads, for the log.
Future<T> withSecureTrigger<T>(String trigger, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_triggerZoneKey: trigger});

/// The trigger set by the nearest [withSecureTrigger], or `unspecified`.
String currentSecureTrigger() =>
    Zone.current[_triggerZoneKey] as String? ?? 'unspecified';

const _noCollectionZoneKey = #whispasteNoKeyringCreate;

/// Runs [body] (start-time work, not a user action) so that a key-store
/// write may not create the Linux default collection: the system would show
/// a "create keyring" dialog before the app explained anything (#1164). A
/// write that would do so fails with `KeyringLocked` instead while the gate
/// is closed.
Future<T> withoutKeyringCreation<T>(Future<T> Function() body) =>
    runZoned(body, zoneValues: {_noCollectionZoneKey: true});

/// Whether the current call chain runs under [withoutKeyringCreation].
bool keyringCreationForbidden() =>
    Zone.current[_noCollectionZoneKey] as bool? ?? false;

/// Outcome of a quiet read.
enum QuietReadStatus {
  /// The value was read without a prompt.
  ok,

  /// No such entry.
  missing,

  /// The entry exists, but reading it would need a system prompt.
  needsConsent,

  /// Anything else; [QuietReadResult.code] has the platform status.
  error,
}

class QuietReadResult {
  const QuietReadResult(this.status, {this.value, this.code});

  final QuietReadStatus status;
  final String? value;
  final int? code;
}

/// Reads one secret by storage name without ever showing a system prompt.
typedef QuietSecretReader = Future<QuietReadResult> Function(String key);

/// Service name `flutter_secure_storage_darwin` stores every item under.
const _darwinStorageService = 'flutter_secure_storage_service';

const _quietChannel = MethodChannel('com.whispaste.quiet_keychain');

/// The platform's quiet reader, or null where reads never prompt (Windows
/// keeps the secrets in a DPAPI file) or where the keyring probe already
/// keeps prompts out (Linux).
QuietSecretReader? platformQuietReader() =>
    Platform.isMacOS ? _readMacKeychainQuietly : null;

Future<QuietReadResult> _readMacKeychainQuietly(String key) async {
  final raw = await _quietChannel.invokeMapMethod<String, Object?>('read', {
    'service': _darwinStorageService,
    'account': key,
  });
  final code = raw?['code'] as int?;
  return switch (raw?['status']) {
    'ok' => QuietReadResult(
      QuietReadStatus.ok,
      value: raw?['value'] as String?,
      code: code,
    ),
    'missing' => QuietReadResult(QuietReadStatus.missing, code: code),
    'needsConsent' => QuietReadResult(QuietReadStatus.needsConsent, code: code),
    _ => QuietReadResult(QuietReadStatus.error, code: code),
  };
}

/// The old file-based macOS login keychain, addressed only through the
/// native host's file-keychain query, the same one the quiet reader uses
/// (#1674). The plugin storage with `usesDataProtectionKeychain: false` is
/// not confined to it: in a sandboxed build with a keychain access group its
/// read and delete reach the data-protection item too, so a move "out of the
/// old keychain" deleted the new entry.
abstract interface class OldKeychain {
  /// Reads [key]; the system may show its "allow access" dialog. Null when
  /// there is no such entry. Throws a [PlatformException] whose code is the
  /// OSStatus (-128 when the user cancelled).
  Future<String?> read(String key);

  /// Deletes [key] from the old keychain only. Throws a [PlatformException]
  /// with the OSStatus when that failed.
  Future<void> delete(String key);
}

/// The macOS old keychain, or null on other platforms.
OldKeychain? platformOldKeychain() =>
    Platform.isMacOS ? const _MacOldKeychain() : null;

class _MacOldKeychain implements OldKeychain {
  const _MacOldKeychain();

  @override
  Future<String?> read(String key) async {
    final raw = await _quietChannel.invokeMapMethod<String, Object?>(
      'readAllowingPrompt',
      {'service': _darwinStorageService, 'account': key},
    );
    return switch (raw?['status']) {
      'ok' => raw?['value'] as String?,
      'missing' => null,
      _ => throw _osStatusError('read', key, raw?['code']),
    };
  }

  @override
  Future<void> delete(String key) async {
    final raw = await _quietChannel.invokeMapMethod<String, Object?>('delete', {
      'service': _darwinStorageService,
      'account': key,
    });
    if (raw?['status'] != 'ok') {
      throw _osStatusError('delete', key, raw?['code']);
    }
  }

  static PlatformException _osStatusError(
    String operation,
    String key,
    Object? code,
  ) => PlatformException(
    code: '$code',
    message: 'Old keychain $operation failed (OSStatus $code)',
    details: key,
  );
}
