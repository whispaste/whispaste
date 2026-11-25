// The encryption choice of Settings → Privacy (#1022): markers, the
// session value and the restart hint.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/core/data/encryption_preference.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('wp_encpref_');
    paths.appDataDirOverride = tmp.path;
    resetEncryptionSessionForTesting();
  });
  tearDown(() {
    paths.appDataDirOverride = null;
    resetEncryptionSessionForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('on by default, nothing pending', () {
    final preference = EncryptionPreference(tmp.path);
    expect(preference.wanted, isTrue);
    expect(preference.switchPending, isFalse);
    expect(encryptionOnThisSession(), isTrue);
  });

  test('a switch is stored and marks the conversion as pending', () {
    final preference = EncryptionPreference(tmp.path);
    expect(preference.setWanted(false), isTrue);
    expect(preference.wanted, isFalse);
    expect(preference.switchPending, isTrue);
    expect(File(p.join(tmp.path, encryptionOffMarkerName)).existsSync(), true);

    preference.clearSwitchPending();
    expect(preference.switchPending, isFalse);

    preference.setWanted(true);
    expect(preference.wanted, isTrue);
    expect(preference.switchPending, isTrue);
  });

  test('the session keeps the state it started with', () {
    expect(encryptionOnThisSession(), isTrue);
    EncryptionPreference(tmp.path).setWanted(false);
    expect(encryptionOnThisSession(), isTrue);
    resetEncryptionSessionForTesting();
    expect(encryptionOnThisSession(), isFalse);
  });

  test('the setting asks for a restart only while the choice differs', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(encryptionSettingProvider.notifier);

    expect(container.read(encryptionSettingProvider).restartNeeded, isFalse);
    expect(notifier.setWanted(false), isTrue);
    expect(container.read(encryptionSettingProvider).wanted, isFalse);
    expect(container.read(encryptionSettingProvider).restartNeeded, isTrue);
    notifier.setWanted(true);
    expect(container.read(encryptionSettingProvider).restartNeeded, isFalse);
  });

  test('a choice that cannot be written changes nothing', () {
    final blocked = File(p.join(tmp.path, 'not-a-dir'))..writeAsStringSync('');
    final preference = EncryptionPreference(blocked.path);
    expect(preference.setWanted(false), isFalse);
    expect(preference.wanted, isTrue);
  });
}
