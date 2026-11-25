/// Ed25519 signature of a downloadable model catalog file (#1792).
///
/// The catalog file is signed with the same key pair that signs the
/// appcast for app updates (`internal-notes`), so no second key
/// exists. The signature is a detached file next to the catalog
/// (`model-catalog.json.sig`): the base64 Ed25519 signature of the exact
/// bytes of `model-catalog.json`. Pure Dart, so `tool/` can use it too.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// The Ed25519 public key (base64) that checks a catalog file. The same
/// key as `SUPublicEDKey` in `macos/Runner/Info.plist` and WinSparkle
/// (`packages/auto_updater_windows/windows/auto_updater.h`); guard test
/// `test/core/models/model_catalog_signature_test.dart`.
const String kModelCatalogPublicKey =
    'Ek8FS/co3CPMeZt7ss9XMDkga7jIG6RWNWbefZhtRck=';

/// Whether [signature] (base64, surrounding whitespace allowed) is a valid
/// Ed25519 signature of [bytes] under [publicKey] (base64). Never throws:
/// any malformed input is simply not valid.
bool verifyModelCatalogSignature(
  Uint8List bytes,
  String signature, {
  String publicKey = kModelCatalogPublicKey,
}) {
  try {
    final key = base64.decode(publicKey.trim());
    final sig = base64.decode(signature.trim());
    if (key.length != ed.PublicKeySize || sig.length != ed.SignatureSize) {
      return false;
    }
    return ed.verify(ed.PublicKey(key), bytes, sig);
  } on FormatException {
    return false;
  } on ArgumentError {
    return false;
  }
}

/// Signs [bytes] with the 32-byte Ed25519 seed [seedBase64] (the format
/// Sparkle's `generate_keys -x` exports) and returns the base64 signature.
/// For `tool/sign_model_catalog.dart` and tests; the app never signs.
String signModelCatalog(Uint8List bytes, String seedBase64) {
  final seed = base64.decode(seedBase64.trim());
  if (seed.length != ed.SeedSize) {
    throw ArgumentError('the signing key must be a 32-byte base64 seed');
  }
  final key = ed.newKeyFromSeed(Uint8List.fromList(seed));
  return base64.encode(ed.sign(key, bytes));
}

/// The base64 public key of the 32-byte seed [seedBase64].
String modelCatalogPublicKeyOf(String seedBase64) {
  final seed = base64.decode(seedBase64.trim());
  final key = ed.newKeyFromSeed(Uint8List.fromList(seed));
  return base64.encode(ed.public(key).bytes);
}
