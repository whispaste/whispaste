// A local build (debug or profile) keeps its data, autostart entry and Linux
// application ID apart from an installed release, so it never reads, locks or
// migrates the release's history database or settings.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/path_service.dart';

void main() {
  test('a release uses the folder name it always had', () {
    expect(appDataFolderName(linux: false, localBuild: false), 'WhisPaste');
    expect(appDataFolderName(linux: true, localBuild: false), 'whispaste');
  });

  test('a local build uses a folder of its own', () {
    expect(appDataFolderName(linux: false, localBuild: true), 'WhisPaste Dev');
    expect(appDataFolderName(linux: true, localBuild: true), 'whispaste-dev');
  });

  test('a test run counts as a local build and resolves to its folder', () {
    expect(isLocalBuild, isTrue);
    // flutter_test_config points the folder at a sandbox; lift it to read the
    // real derivation, then put it back.
    final sandbox = appDataDirOverride;
    appDataDirOverride = null;
    addTearDown(() => appDataDirOverride = sandbox);
    expect(
      appDataDir(),
      endsWith(appDataFolderName(linux: Platform.isLinux, localBuild: true)),
    );
  });

  test('autostart and the Linux app ID follow the same split', () {
    final autostart = File(
      'lib/services/autostart_service.dart',
    ).readAsStringSync();
    expect(
      autostart,
      contains("appName: isLocalBuild ? 'WhisPaste Dev' : 'WhisPaste'"),
    );
    final cmake = File('linux/CMakeLists.txt').readAsStringSync();
    expect(cmake, contains('if(NOT CMAKE_BUILD_TYPE STREQUAL "Release")'));
    expect(cmake, contains(r'set(APPLICATION_ID "${APPLICATION_ID}.dev")'));
  });
}
