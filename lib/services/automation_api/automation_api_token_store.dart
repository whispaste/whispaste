/// Bearer-token storage for the local automation API (ticket 03,
/// `.scratch/local-automation-api/`).
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

class AutomationApiTokenStore {
  AutomationApiTokenStore(this._store);

  final SecureKeyStore _store;

  /// Reads the currently valid token, or `null` if none has been generated
  /// (or it was revoked).
  Future<String?> readToken() => _store.readKey(automationApiTokenKey);

  /// Generates a new cryptographically random token, persists it, and
  /// returns it. Overwrites — and thus immediately invalidates — any
  /// previous token, satisfying the ticket's "regenerate revokes the old
  /// token instantly" requirement.
  Future<String> regenerate() async {
    final token = _generateToken();
    await _store.writeKey(automationApiTokenKey, token);
    return token;
  }

  /// Deletes the token. After this, [readToken] returns `null` and every
  /// request is rejected (no token can ever match `null`).
  Future<void> revoke() => _store.deleteKey(automationApiTokenKey);
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
