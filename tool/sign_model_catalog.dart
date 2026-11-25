// Checks and signs the downloadable model catalog (#1792).
//
// Reads the source tool/model-catalog.json, refuses it unless it is a valid
// catalog whose entries either are new models or match the bundled catalog
// exactly, signs its exact bytes with the appcast Ed25519 key and writes
//   <out>/model-catalog.json      (byte-identical copy of the source)
//   <out>/model-catalog.json.sig  (base64 Ed25519 signature)
// The key must belong to kModelCatalogPublicKey, otherwise the app would
// reject the file; the tool checks that before it writes anything.
//
// Key: env WHISPASTE_CATALOG_SIGNING_KEY (32-byte base64 seed) or
// --key-file=<path> (default ~/.config/whispaste-sparkle/sparkle_private.pem,
// see internal-notes). The key is never printed.
//
// Usage: dart run tool/sign_model_catalog.dart [--in=tool/model-catalog.json]
//        [--out=build/model-catalog] [--key-file=<path>] [--check-only]
// --check-only validates the source without a key (used by the test).
// Publishing: scripts/publish-model-catalog.sh.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:whispaste/core/models/model_catalog_source_check.dart';
import 'package:whispaste/core/models/model_catalog_signature.dart';

Future<void> main(List<String> args) async {
  var input = 'tool/model-catalog.json';
  var out = 'build/model-catalog';
  final home = Platform.environment['HOME'] ?? '';
  var keyFile = '$home/.config/whispaste-sparkle/sparkle_private.pem';
  var checkOnly = false;
  for (final a in args) {
    if (a.startsWith('--in=')) {
      input = a.substring(5);
    } else if (a.startsWith('--out=')) {
      out = a.substring(6);
    } else if (a.startsWith('--key-file=')) {
      keyFile = a.substring(11);
    } else if (a == '--check-only') {
      checkOnly = true;
    } else {
      stderr.writeln('unknown argument: $a');
      exit(2);
    }
  }

  final bytes = Uint8List.fromList(File(input).readAsBytesSync());
  final problems = modelCatalogSourceProblems(bytes);
  if (problems.isNotEmpty) {
    stderr.writeln('$input is not publishable:');
    for (final problem in problems) {
      stderr.writeln('  - $problem');
    }
    exit(1);
  }
  if (checkOnly) {
    stdout.writeln('$input: ok');
    return;
  }

  final key =
      Platform.environment['WHISPASTE_CATALOG_SIGNING_KEY'] ??
      (File(keyFile).existsSync() ? File(keyFile).readAsStringSync() : null);
  if (key == null || key.trim().isEmpty) {
    stderr.writeln(
      'no signing key: set WHISPASTE_CATALOG_SIGNING_KEY or --key-file',
    );
    exit(3);
  }
  final String publicKey;
  try {
    publicKey = modelCatalogPublicKeyOf(key);
  } on Object {
    stderr.writeln('the signing key is not a 32-byte base64 Ed25519 seed');
    exit(3);
  }
  if (publicKey != kModelCatalogPublicKey) {
    stderr.writeln(
      'the signing key does not belong to kModelCatalogPublicKey; '
      'the app would reject the file',
    );
    exit(3);
  }
  final signature = signModelCatalog(bytes, key);
  if (!verifyModelCatalogSignature(bytes, signature)) {
    stderr.writeln('signature does not verify, nothing written');
    exit(1);
  }

  Directory(out).createSync(recursive: true);
  File('$out/model-catalog.json').writeAsBytesSync(bytes);
  File('$out/model-catalog.json.sig').writeAsStringSync('$signature\n');
  final revision = (jsonDecode(utf8.decode(bytes)) as Map)['revision'];
  stdout.writeln('signed revision $revision -> $out');
}
