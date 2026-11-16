/// XP-6-06 guard: the block list needs the target app on every desktop
/// platform. Each native paste host must answer `getTargetBundleId`, otherwise
/// the list silently never matches there.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _nativeHosts = [
  'macos/Runner/DesktopPasteHost.swift',
  'windows/runner/desktop_paste_host.cpp',
  'linux/runner/desktop_paste_host.cc',
];

void main() {
  for (final path in _nativeHosts) {
    test('$path answers getTargetBundleId for the block list', () {
      final source = File(path).readAsStringSync();
      expect(source, contains('getTargetBundleId'));
    });
  }
}
