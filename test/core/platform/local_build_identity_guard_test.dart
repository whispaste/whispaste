// Guard: local macOS builds (Debug, Profile, the mac smoke's copy) run under
// their own bundle ids, so they never share privacy grants or preferences with
// an installed release or the local preview, and only the release identity
// adopts the legacy App Store id's state (macos/Runner/BundleIdMigrationHost.swift).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _localId = 'de.whispaste.direct.dev';
const _smokeId = 'de.whispaste.direct.smoke';
const _releaseId = 'de.whispaste.direct';
const _storeId = 'de.whispaste.app';

/// Bundle id per Runner build configuration (null: inherits AppInfo.xcconfig).
Map<String, String?> _runnerBundleIds() {
  final project = File(
    'macos/Runner.xcodeproj/project.pbxproj',
  ).readAsStringSync();
  final block = RegExp(
    r'\t\t\w+ /\* ([\w-]+) \*/ = \{\n\t\t\tisa = XCBuildConfiguration;(.*?)\n\t\t\};',
    dotAll: true,
  );
  return {
    for (final m in block.allMatches(project))
      if (m.group(2)!.contains('INFOPLIST_FILE = Runner/Info.plist;'))
        m.group(1)!: RegExp(
          r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
        ).firstMatch(m.group(2)!)?.group(1),
  };
}

void main() {
  test('Debug and Profile use the local id, Release and MAS their own', () {
    final ids = _runnerBundleIds();
    expect(ids['Debug'], _localId);
    expect(ids['Profile'], _localId);
    expect(ids['MAS'], _storeId);
    expect(ids.containsKey('Release'), isTrue);
    expect(ids['Release'], isNull, reason: 'Release inherits AppInfo.xcconfig');
    final appInfo = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    expect(appInfo, contains('PRODUCT_BUNDLE_IDENTIFIER = $_releaseId\n'));
  });

  test('only the release identity adopts the legacy state', () {
    final host = File(
      'macos/Runner/BundleIdMigrationHost.swift',
    ).readAsStringSync();
    expect(host, contains('static let releaseBundleId = "$_releaseId"'));
    expect(
      host,
      contains(
        'guard Bundle.main.bundleIdentifier == releaseBundleId else { return }',
      ),
    );
  });

  test('the mac smoke starts its copy under its own id', () {
    final smoke = File('scripts/mac-build-smoke.sh').readAsStringSync();
    expect(smoke, contains('SMOKE_ID=$_smokeId'));
    expect(smoke, contains(r'Set :CFBundleIdentifier $SMOKE_ID'));
  });
}
