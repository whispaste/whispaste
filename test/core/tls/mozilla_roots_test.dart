import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/tls/mozilla_roots.dart';
import 'package:whispaste/core/tls/mozilla_roots_loader.dart';

const _beginMarker = '-----BEGIN CERTIFICATE-----';

Uint8List _bundleBytes() =>
    File('assets/tls/mozilla-cacert.pem').readAsBytesSync();

int _countBlocks(Uint8List bytes) =>
    _beginMarker.allMatches(utf8.decode(bytes)).length;

/// Serves a fixed asset payload and reports any other key as missing.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._payloads);

  final Map<String, Uint8List> _payloads;

  @override
  Future<ByteData> load(String key) async {
    final payload = _payloads[key];
    if (payload == null) throw StateError('asset not found: $key');
    return ByteData.sublistView(payload);
  }
}

void main() {
  test('installs every certificate of the bundled store', () {
    final bytes = _bundleBytes();

    final result = installMozillaRoots(SecurityContext(), bytes);

    expect(result.added, _countBlocks(bytes));
    expect(result.rejected, 0);
  });

  test('a refused block does not hide the certificates after it', () {
    final good = utf8.decode(_bundleBytes());
    final firstBlock = good.substring(
      good.indexOf(_beginMarker),
      good.indexOf('-----END CERTIFICATE-----') +
          '-----END CERTIFICATE-----'.length,
    );
    const damaged = '$_beginMarker\nAAAA\n-----END CERTIFICATE-----\n';
    final pem = Uint8List.fromList(utf8.encode('$damaged\n$firstBlock\n'));

    final result = installMozillaRoots(SecurityContext(), pem);

    expect(result.rejected, 1);
    expect(result.added, 1);
  });

  test('input without certificates installs nothing and does not throw', () {
    final result = installMozillaRoots(
      SecurityContext(),
      Uint8List.fromList(utf8.encode('not a pem file at all')),
    );

    expect(result.added, 0);
    expect(result.rejected, 0);
  });

  test('loader installs the bundled roots on Windows', () async {
    final bytes = _bundleBytes();
    final result = await installBundledMozillaRoots(
      bundle: _FakeBundle({mozillaRootsAssetKey: bytes}),
      context: SecurityContext(),
      isWindows: true,
    );

    expect(result, isNotNull);
    expect(result!.added, _countBlocks(bytes));
  });

  test('loader does nothing outside Windows', () async {
    final result = await installBundledMozillaRoots(
      bundle: _FakeBundle({mozillaRootsAssetKey: _bundleBytes()}),
      context: SecurityContext(),
      isWindows: false,
    );

    expect(result, isNull);
  });

  test('a damaged asset does not crash the start', () async {
    final result = await installBundledMozillaRoots(
      bundle: _FakeBundle({
        mozillaRootsAssetKey: Uint8List.fromList(utf8.encode('garbage')),
      }),
      context: SecurityContext(),
      isWindows: true,
    );

    expect(result, isNotNull);
    expect(result!.added, 0);
  });

  test('a missing asset does not crash the start', () async {
    final result = await installBundledMozillaRoots(
      bundle: _FakeBundle({}),
      context: SecurityContext(),
      isWindows: true,
    );

    expect(result, isNull);
  });
}
