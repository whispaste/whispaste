/// Tests for [detectDeployChannel] — real `Platform`/`kIsMasBuild` values
/// (no injection seam exists for either), so only the branch reachable in a
/// normal `flutter test` run is exercised: this suite runs on macOS without
/// the `WHISPASTE_MAS` dart-define, so `kIsMasBuild` is `false` at compile
/// time and the MAS branch cannot be toggled at runtime (same limitation
/// documented in `mas_ondevice_provider_gating_test.dart`).
library;

import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/build_config.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

void main() {
  group('detectDeployChannel', () {
    test(
      'returns portable on a non-MAS macOS build',
      () {
        expect(kIsMasBuild, isFalse);
        expect(detectDeployChannel(), DeployChannel.portable);
      },
      skip: Platform.isMacOS ? false : 'macOS-only branch',
    );

    test('deployChannelOverride short-circuits real detection', () {
      deployChannelOverride = DeployChannel.store;
      addTearDown(() => deployChannelOverride = null);

      expect(detectDeployChannel(), DeployChannel.store);
    });
  });
}
