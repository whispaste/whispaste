/// Platform decisions in UI code go through the seam `defaultTargetPlatform`
/// (#198), so a test can pin any desktop OS with `TargetPlatformVariant` or
/// `debugDefaultTargetPlatformOverride` and behaves the same on every host.
/// `dart:io` `Platform.isMacOS/isWindows/isLinux` asks the host instead and
/// cannot be pinned, so it has no place in `lib/features` and `lib/widgets`.
/// Real OS resources (files, paths, processes, FFI) stay in `lib/services` and
/// `lib/core`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that may still ask the host, with the reason. Target: empty.
const Map<String, String> _allowlist = {};

const _roots = ['lib/features', 'lib/widgets'];

final _hostCheck = RegExp(r'Platform\.is(MacOS|Windows|Linux)\b');

/// Hits per file as `path:line`, comment lines skipped.
Map<String, List<String>> _hostChecks() {
  final hits = <String, List<String>>{};
  for (final root in _roots) {
    final files = Directory(root)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final path = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (_hostCheck.hasMatch(line)) {
          (hits[path] ??= []).add('$path:${i + 1}');
        }
      }
    }
  }
  return hits;
}

void main() {
  test('UI code reads the platform seam, not the host OS', () {
    final offenders = [
      for (final entry in _hostChecks().entries)
        if (!_allowlist.containsKey(entry.key)) ...entry.value,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'use defaultTargetPlatform instead of Platform.is* in UI code '
          '(#198)',
    );
  });

  test('every allowlist entry still asks the host', () {
    final hits = _hostChecks();
    final stale = [
      for (final path in _allowlist.keys)
        if (!hits.containsKey(path)) path,
    ];
    expect(stale, isEmpty, reason: 'remove stale allowlist entries');
  });
}
