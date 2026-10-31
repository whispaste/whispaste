import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the bundled Mozilla root store (assets/tls/). The three roots are
/// the ones the Windows download fix depends on (see assets/tls/NOTICE.md).
void main() {
  const assetPath = 'assets/tls/mozilla-cacert.pem';
  const requiredRoots = [
    'Amazon Root CA 1',
    'Starfield Services Root Certificate Authority - G2',
    'ISRG Root X1',
  ];

  test('bundle is readable and carries the required roots', () {
    final file = File(assetPath);
    expect(file.existsSync(), isTrue, reason: 'run from the project root');

    final text = file.readAsStringSync();
    expect(
      RegExp('-----BEGIN CERTIFICATE-----').allMatches(text).length,
      greaterThan(100),
    );
    for (final root in requiredRoots) {
      expect(
        text.split('\n').contains(root),
        isTrue,
        reason: 'missing root: $root',
      );
    }
  });

  test('NOTICE records the SHA-256 of the bundled file', () {
    final digest = sha256.convert(File(assetPath).readAsBytesSync()).toString();
    final notice = File('assets/tls/NOTICE.md').readAsStringSync();

    expect(notice, contains(digest));
  });
}
