/// Cross-platform smoke test for `flutter_secure_storage`.
///
/// Verifies write / read / overwrite / delete against the real native
/// backend on every desktop platform WhisPaste ships to:
///   - Windows: Credential Manager
///   - macOS:   Keychain
///   - Linux:   libsecret (Secret Service via gnome-keyring)
///
/// Uses a per-run unique key namespace (`wp_itest_*`) so it never
/// touches the production items (`wp_openai_api_key`,
/// `wp_deepgram_api_key`) and a previous failed run cannot leak
/// residue into the next one — no `deleteAll()` is ever called, which
/// would also wipe a developer's real API keys if the test were ever
/// executed against a local install.
///
/// Run locally:
///   flutter test integration_test/secure_storage_test.dart -d windows
///   flutter test integration_test/secure_storage_test.dart -d macos
///   flutter test integration_test/secure_storage_test.dart -d linux
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// The default `useDataProtectionKeyChain: true` on macOS requires a
// signed bundle with a registered Bundle ID, which the
// `flutter test integration_test` runner binary does not have
// (errSecMissingEntitlement, -34018). The production app ships with
// `app-sandbox: false` and a real bundle ID, so it uses the default
// data-protection keychain. We pin the test to the classic login
// keychain so the smoke test exercises the native backend without
// dragging entitlement plumbing into the CI image.
const _storage = FlutterSecureStorage(
  mOptions: MacOsOptions(usesDataProtectionKeychain: false),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final ns = 'wp_itest_${DateTime.now().microsecondsSinceEpoch}';
  final keyA = '${ns}_a';
  final keyB = '${ns}_b';

  Future<void> cleanup() async {
    for (final k in [keyA, keyB]) {
      try {
        await _storage.delete(key: k);
      } catch (_) {
        // best-effort teardown
      }
    }
  }

  tearDown(cleanup);
  tearDownAll(cleanup);

  testWidgets('write then read returns the same value', (_) async {
    await _storage.write(key: keyA, value: 'hello');
    expect(await _storage.read(key: keyA), equals('hello'));
  });

  testWidgets('read of unknown key returns null', (_) async {
    expect(await _storage.read(key: keyA), isNull);
  });

  testWidgets('overwrite replaces the previous value', (_) async {
    await _storage.write(key: keyA, value: 'first');
    await _storage.write(key: keyA, value: 'second');
    expect(await _storage.read(key: keyA), equals('second'));
  });

  testWidgets('delete removes the value', (_) async {
    await _storage.write(key: keyA, value: 'to-go');
    await _storage.delete(key: keyA);
    expect(await _storage.read(key: keyA), isNull);
  });

  testWidgets('distinct keys do not interfere', (_) async {
    await _storage.write(key: keyA, value: 'A');
    await _storage.write(key: keyB, value: 'B');
    expect(await _storage.read(key: keyA), equals('A'));
    expect(await _storage.read(key: keyB), equals('B'));
  });
}
