/// Pure primitives behind the History PIN lock: format rule, salted hash,
/// constant-time verification and the wrong-PIN throttle schedule.
///
/// The PIN is a visibility lock against casual snooping on a shared OS
/// account, not encryption — the history itself stays a plain SQLite file.
/// That is why a forgotten PIN is resolved by deleting the history rather
/// than by any recovery path (`.scratch/history-pin-lock/PRD.md`).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2 work factor. A 4-digit PIN has only 10 000 values, so the hash is
/// no defence against offline brute force of the settings file; the cost
/// only has to stay cheap enough for an off-isolate check while not being
/// free — the persisted wrong-PIN throttle is the real brake.
const kHistoryPinIterations = 20000;

const _scheme = 'pbkdf2-sha256';
const _saltBytes = 16;

final _pinPattern = RegExp(r'^[0-9]{4,8}$');

/// Whether [pin] is 4–8 ASCII digits.
bool isValidHistoryPin(String pin) => _pinPattern.hasMatch(pin);

/// Encodes a salted hash of [pin] as `pbkdf2-sha256$<iterations>$<salt>$<hash>`.
String hashHistoryPin(
  String pin, {
  int iterations = kHistoryPinIterations,
  Random? random,
}) {
  final rng = random ?? Random.secure();
  final salt = Uint8List.fromList([
    for (var i = 0; i < _saltBytes; i++) rng.nextInt(256),
  ]);
  final hash = pbkdf2HmacSha256(utf8.encode(pin), salt, iterations);
  return [
    _scheme,
    '$iterations',
    base64Encode(salt),
    base64Encode(hash),
  ].join(r'$');
}

/// Whether [pin] matches the [stored] value from [hashHistoryPin]. A missing
/// or malformed [stored] value never matches.
bool verifyHistoryPin(String pin, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 4 || parts[0] != _scheme) return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final List<int> salt;
  final List<int> expected;
  try {
    salt = base64Decode(parts[2]);
    expected = base64Decode(parts[3]);
  } on FormatException {
    return false;
  }
  final actual = pbkdf2HmacSha256(utf8.encode(pin), salt, iterations);
  if (actual.length != expected.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}

/// PBKDF2-HMAC-SHA256 with a single 32-byte output block (RFC 8018 §5.2).
Uint8List pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations) {
  final hmac = Hmac(sha256, password);
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

/// How long unlocking is refused after [failedAttempts] consecutive wrong
/// PINs: free for the first four, then 30 s doubling per miss, capped at
/// 15 minutes.
Duration historyPinLockout(int failedAttempts) {
  if (failedAttempts < 5) return Duration.zero;
  const cap = Duration(minutes: 15);
  final exponent = failedAttempts - 5;
  if (exponent >= 5) return cap;
  final lockout = Duration(seconds: 30 * (1 << exponent));
  return lockout > cap ? cap : lockout;
}
