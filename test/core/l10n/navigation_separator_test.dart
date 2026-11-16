import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Navigation paths in UI texts ("Settings → Keyboard shortcuts",
/// "System Settings → Privacy & Security") use one separator, "→", in every
/// app language. The same arrow also stands for "becomes" in the replacement
/// examples, which is why no second separator was added for paths.
///
/// Forbidden in any ARB value: "›" (the one-off variant), ">" surrounded by
/// spaces (the ASCII variant) and "->" (typed-out arrow). Languages are read
/// from the directory, not from a hard-coded list.
void main() {
  final arbFiles = Directory('lib/core/l10n')
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'app_[a-z_]+\.arb$').hasMatch(f.path))
      .toList();

  test('the ARB directory holds at least one app language', () {
    expect(arbFiles, isNotEmpty);
  });

  for (final file in arbFiles) {
    final name = file.uri.pathSegments.last;
    test('$name uses only "→" as navigation separator', () {
      final arb = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      final offenders = <String>[];
      for (final MapEntry(:key, :value) in arb.entries) {
        if (key.startsWith('@') || value is! String) continue;
        for (final forbidden in const ['›', ' > ', '->']) {
          if (value.contains(forbidden)) {
            offenders.add('$key contains "$forbidden"');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use "→" between path steps (e.g. "Settings → Appearance"), '
            'see the navigation separator note in this file.',
      );
    });
  }
}
