/// Test IDs in the Dictionary (replacements) and Snippets areas (UIA-DIC-11,
/// UIA-SNP-06).
///
/// Every interactive constructor in these areas carries a `key:` or a
/// `testId:`, so UI flows and agent checks can address it by a stable id
/// rather than by a localised label. The scan is a text check on the source;
/// it is deliberately simple: it finds each constructor call and looks for
/// `key:` or `testId:` inside its brackets.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _areas = [
  'lib/features/replacements',
  'lib/features/dictionary',
  'lib/features/snippets',
];

const _interactive = [
  'WpButton',
  'IconButton',
  'WpTextField',
  'WpSearchField',
  'WpRowAction',
  'WpMarkdownToolbar',
  'WpTextEditor',
  'WpTagInput',
  'WpFilterChip',
  'WpSegmentedSelector',
  'TextField',
  'TextButton',
  'OutlinedButton',
  'FilledButton',
  'InkWell',
  'Switch',
  'Checkbox',
];

final _call = RegExp('\\b(${_interactive.join('|')})\\(');

/// Returns `file:line` for every interactive call without a `key:`.
List<String> _missingKeys() {
  final offenders = <String>[];
  for (final area in _areas) {
    final files = Directory(area)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'));
    for (final file in files) {
      final src = file.readAsStringSync();
      for (final m in _call.allMatches(src)) {
        var depth = 0;
        var end = m.end - 1;
        for (; end < src.length; end++) {
          final c = src[end];
          if (c == '(') depth++;
          if (c == ')' && --depth == 0) break;
        }
        final body = src.substring(m.start, end);
        // `testId:` counts too: WpButton and WpFilterChip derive their key
        // and semantics identifier from it.
        if (!RegExp(r'\b(key|testId):').hasMatch(body)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${file.path}:$line ${m.group(1)}');
        }
      }
    }
  }
  return offenders;
}

void main() {
  test('every interactive element in Dictionary and Snippets has a key', () {
    final offenders = _missingKeys();
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
