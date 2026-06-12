import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/secure_key_store.dart';

void main() {
  group('SecureKeyStore default storage', () {
    test('avoids the macOS data-protection keychain', () {
      // Regression: with usesDataProtectionKeychain=true (plugin default)
      // every keychain write fails with errSecMissingEntitlement (-34018)
      // because the non-sandboxed Runner has no keychain-access-groups
      // entitlement — API keys silently never persist and reads return
      // null, breaking all cloud STT providers on macOS.
      final mOptions = defaultSecureStorage.mOptions;

      expect(mOptions, isA<MacOsOptions>());
      expect(
        (mOptions as MacOsOptions).usesDataProtectionKeychain,
        isFalse,
        reason:
            'The data-protection keychain requires a keychain-access-groups '
            'entitlement that the WhisPaste Runner does not ship with.',
      );
    });
  });
}
