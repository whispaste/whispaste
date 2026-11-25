import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the hand-set `switchNamesRow` flag: forgotten, a screen reader hears
/// the name twice; set without a switch, the row has no name at all.
///
/// Rows that decide at runtime (`switchNamesRow: enabled`) pass a prebuilt
/// switch and are left to their own review.
void main() {
  test('toggle rows and switchNamesRow go together', () {
    final row = RegExp(r'(?<![\w.])(SettingRow|WpSettingsRow)\(');
    final problems = <String>[];
    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    for (final file in sources) {
      final source = file.readAsStringSync();
      // A switch built beforehand into a local (e.g. shown next to a restart
      // button) still names the row when the call passes that local.
      final prebuilt = RegExp(
        r'(?:final|var)\s+(\w+)\s*=\s*settingsToggle\(',
      ).allMatches(source).map((m) => m.group(1)!).toList();
      for (final match in row.allMatches(source)) {
        final call = _callAt(source, match.end);
        final hasSwitch =
            call.contains('settingsToggle(') ||
            prebuilt.any((n) => RegExp('\\b$n\\b').hasMatch(call));
        final line = '\n'.allMatches(source.substring(0, match.start)).length;
        final where = '${file.path}:${line + 1}';
        if (hasSwitch && !call.contains('switchNamesRow:')) {
          problems.add('$where: switch without switchNamesRow');
        }
        if (!hasSwitch && call.contains('switchNamesRow: true')) {
          problems.add('$where: switchNamesRow without a switch');
        }
      }
    }

    expect(problems, isEmpty);
  });
}

/// The argument list that starts at [start], just after its opening bracket.
String _callAt(String source, int start) {
  var depth = 1;
  var i = start;
  while (depth > 0 && i < source.length) {
    final char = source[i++];
    if (char == '(') depth++;
    if (char == ')') depth--;
  }
  return source.substring(start, i);
}
