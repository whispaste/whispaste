// Signature of the downloadable model catalog (#1792): a valid signature
// passes, any change to the bytes or a foreign key fails, malformed input
// never throws, and the app checks against the appcast key it ships.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/models/model_catalog_signature.dart';

void main() {
  final seed = base64.encode(List<int>.generate(32, (i) => i));
  final otherSeed = base64.encode(List<int>.generate(32, (i) => 255 - i));
  final publicKey = modelCatalogPublicKeyOf(seed);
  final bytes = Uint8List.fromList(utf8.encode('{"schemaVersion":1}'));

  test('a signature of the exact bytes verifies', () {
    final sig = signModelCatalog(bytes, seed);
    expect(
      verifyModelCatalogSignature(bytes, '$sig\n', publicKey: publicKey),
      isTrue,
    );
  });

  test('changed bytes, a foreign key or garbage fail closed', () {
    final sig = signModelCatalog(bytes, seed);
    final changed = Uint8List.fromList(bytes)..[0] ^= 1;
    expect(
      verifyModelCatalogSignature(changed, sig, publicKey: publicKey),
      isFalse,
    );
    expect(
      verifyModelCatalogSignature(
        bytes,
        signModelCatalog(bytes, otherSeed),
        publicKey: publicKey,
      ),
      isFalse,
    );
    expect(
      verifyModelCatalogSignature(bytes, 'not base64!', publicKey: publicKey),
      isFalse,
    );
    expect(
      verifyModelCatalogSignature(bytes, base64.encode([1, 2, 3])),
      isFalse,
    );
    expect(verifyModelCatalogSignature(bytes, sig, publicKey: 'AAAA'), isFalse);
  });

  test('the catalog key is the appcast key on macOS and Windows', () {
    for (final path in [
      'macos/Runner/Info.plist',
      'packages/auto_updater_windows/windows/auto_updater.h',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains(kModelCatalogPublicKey),
        reason: path,
      );
    }
  });
}
