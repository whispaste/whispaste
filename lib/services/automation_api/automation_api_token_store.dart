/// Bearer-token storage for the local automation API.
///
/// Reuses [SecureKeyStore] — the same platform-native secure storage
/// (Keychain/Credential Manager/libsecret) already used for the OpenAI and
/// Deepgram API keys — rather than introducing a second storage mechanism.
/// The token is namespaced under its own `wp_` key, never mixed into the
/// flat `AppSettings` map: only the enabled/disabled switch lives there
/// (see `AutomationApiSettings`).
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/secure_key_store.dart';

/// Secure-storage key for the automation API bearer token.
const automationApiTokenKey = 'wp_automation_api_token';

/// Secure-storage key for the separate write-scope token (#255, ADR 0015
/// D17). Only this token may start a write job; it opens no other route.
const automationWriteTokenKey = 'wp_automation_write_token';

class AutomationApiTokenStore {
  AutomationApiTokenStore(this._store, {this.key = automationApiTokenKey});

  final SecureKeyStore _store;

  /// The secure-storage entry this store manages.
  final String key;

  /// The token once read or written. The auth middleware asks for it on every
  /// request; without the cache each request would touch the key store (and,
  /// for a build signed differently, could prompt; #1161).
  String? _cached;

  /// Reads the currently valid token, or `null` if none has been generated
  /// (or it was revoked). Throws [secretNeedsConsentCode] while the entry is
  /// held back before the data-key explanation.
  Future<String?> readToken() async {
    final cached = _cached;
    if (cached != null) return cached;
    return _cached = await _store.readKey(key);
  }

  /// Generates a new cryptographically random token, persists it, and
  /// returns it. Overwrites — and thus immediately invalidates — any
  /// previous token, satisfying the ticket's "regenerate revokes the old
  /// token instantly" requirement.
  Future<String> regenerate() async {
    final token = _generateToken();
    await _store.writeKey(key, token);
    return _cached = token;
  }

  /// Deletes the token. After this, [readToken] returns `null` and every
  /// request is rejected (no token can ever match `null`).
  Future<void> revoke() async {
    _cached = null;
    await _store.deleteKey(key);
  }
}

/// Generates a 32-byte (64 hex char) cryptographically random token —
/// deliberately longer than [telemetry_service.dart]'s 16-byte session
/// visitor id, since this one is a real bearer credential rather than a
/// non-secret analytics grouping value.
String _generateToken() {
  final random = Random.secure();
  return List.generate(
    32,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Riverpod provider for the automation API token store.
final automationApiTokenStoreProvider = Provider<AutomationApiTokenStore>(
  (ref) => AutomationApiTokenStore(ref.read(secureKeyStoreProvider)),
);

/// Store of the write-scope token (`wp_automation_write_token`).
final automationWriteTokenStoreProvider = Provider<AutomationApiTokenStore>(
  (ref) => AutomationApiTokenStore(
    ref.read(secureKeyStoreProvider),
    key: automationWriteTokenKey,
  ),
);
