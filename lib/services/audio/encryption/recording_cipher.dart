/// The at-rest format of a retained recording (#1021, part of #591).
///
/// A sealed recording is one AES-256-GCM message:
///
/// ```
/// magic "WPAENC01" (8) | nonce (12) | ciphertext | tag (16)
/// ```
///
/// The magic doubles as the version and as associated data, so a file cut or
/// patched anywhere fails to open instead of playing noise. A file without
/// the magic is a plain WAV from before the migration; readers pass it
/// through unchanged.
///
/// The recording key is not the data key itself: it is
/// HMAC-SHA256(data key, [recordingDerivationLabel]), so the recordings and the
/// history database (#1020) never share a key, even though both come from
/// the one data key of #1019.
///
/// Everything here is synchronous and pure, so it can run on a background
/// isolate (see `RecordingVault`).
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// First bytes of every sealed recording.
final Uint8List recordingMagic = Uint8List.fromList(ascii.encode('WPAENC01'));

/// Domain-separation label for deriving the recording key.
/// Public by design, not a secret.
const recordingDerivationLabel = 'whispaste/recordings/v1';

const _nonceLength = 12;
const _tagBits = 128;

/// Bytes a sealed recording adds to the plain WAV.
const sealedOverhead = 8 + _nonceLength + _tagBits ~/ 8;

/// A sealed recording that does not open: wrong key, cut or altered.
final class RecordingCipherException implements Exception {
  const RecordingCipherException(this.message);

  final String message;

  @override
  String toString() => 'RecordingCipherException($message)';
}

/// The 32-byte recording key, derived from the data key.
Uint8List deriveRecordingKey(List<int> dataKey) => Uint8List.fromList(
  Hmac(sha256, dataKey).convert(utf8.encode(recordingDerivationLabel)).bytes,
);

/// True when [head] (at least the first 8 bytes of a file) starts a sealed
/// recording.
bool isSealedRecording(List<int> head) {
  if (head.length < recordingMagic.length) return false;
  for (var i = 0; i < recordingMagic.length; i++) {
    if (head[i] != recordingMagic[i]) return false;
  }
  return true;
}

/// Seals [plain] with [key]. [nonce] is for tests only; in the app a fresh
/// random nonce is drawn for every file.
Uint8List sealRecording(Uint8List plain, Uint8List key, {Uint8List? nonce}) {
  final iv = nonce ?? _randomNonce();
  final cipher = _gcm(forEncryption: true, key: key, nonce: iv);
  final body = cipher.process(plain);
  return Uint8List(recordingMagic.length + iv.length + body.length)
    ..setRange(0, recordingMagic.length, recordingMagic)
    ..setRange(recordingMagic.length, recordingMagic.length + iv.length, iv)
    ..setAll(recordingMagic.length + iv.length, body);
}

/// Opens a sealed recording. Throws [RecordingCipherException] when [sealed]
/// is not a sealed recording or does not authenticate under [key].
Uint8List openRecording(Uint8List sealed, Uint8List key) {
  if (!isSealedRecording(sealed) || sealed.length < sealedOverhead) {
    throw const RecordingCipherException('not a sealed recording');
  }
  final start = recordingMagic.length;
  final nonce = Uint8List.sublistView(sealed, start, start + _nonceLength);
  final body = Uint8List.sublistView(sealed, start + _nonceLength);
  final cipher = _gcm(forEncryption: false, key: key, nonce: nonce);
  try {
    return cipher.process(body);
  } on InvalidCipherTextException {
    throw const RecordingCipherException('authentication failed');
  }
}

GCMBlockCipher _gcm({
  required bool forEncryption,
  required Uint8List key,
  required Uint8List nonce,
}) {
  if (key.length != 32) {
    throw const RecordingCipherException('recording key must be 32 bytes');
  }
  return GCMBlockCipher(AESEngine())..init(
    forEncryption,
    AEADParameters(KeyParameter(key), _tagBits, nonce, recordingMagic),
  );
}

final _random = Random.secure();

Uint8List _randomNonce() => Uint8List.fromList(
  List<int>.generate(_nonceLength, (_) => _random.nextInt(256)),
);
