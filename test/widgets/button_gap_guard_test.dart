// Static guard (#1687): two buttons with a visible box never sit flush in a
// Row. Side by side they go through `WpButtonGroup` or a `Wrap` with
// `WpSpacing.buttonGap`, or keep an explicit spacer between them.
//
// Ghost icon buttons and row actions are exempt: they show no box at rest.
// Line-based on purpose (formatted Dart, one sibling per indent level); it
// catches the pattern of the bug, not every conceivable layout.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _boxed = RegExp(
  r'^(\s*)(?:const\s+)?(WpIconButton|WpButton|WpHeroButton)\(',
);

int _indent(String line) => line.length - line.trimLeft().length;

/// `file:line` of every boxed button that directly follows another boxed
/// button inside the children of a `Row(`.
List<String> flushButtonsInRows(String path, List<String> lines) {
  final hits = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final m = _boxed.firstMatch(lines[i]);
    if (m == null) continue;
    final ind = m.group(1)!.length;

    // The line before must close the previous sibling at the same indent.
    var j = i - 1;
    while (j >= 0 &&
        (lines[j].trim().isEmpty || lines[j].trim().startsWith('//'))) {
      j--;
    }
    if (j < 0 ||
        _indent(lines[j]) != ind ||
        !lines[j].trimRight().endsWith(',')) {
      continue;
    }
    // Start of that sibling: the last line at the same indent.
    var k = j;
    if (_boxed.firstMatch(lines[j]) == null) {
      k = j - 1;
      while (k >= 0 && (lines[k].trim().isEmpty || _indent(lines[k]) > ind)) {
        k--;
      }
    }
    if (k < 0 ||
        _indent(lines[k]) != ind ||
        _boxed.firstMatch(lines[k]) == null) {
      continue;
    }

    // The children list and the widget that owns it.
    var c = k;
    while (c >= 0 &&
        !(_indent(lines[c]) < ind && lines[c].contains('children'))) {
      c--;
    }
    if (c < 0) continue;
    // The widget that owns the list: the next line above with less indent.
    var owner = c - 1;
    while (owner >= 0 &&
        (lines[owner].trim().isEmpty ||
            _indent(lines[owner]) >= _indent(lines[c]))) {
      owner--;
    }
    if (owner >= 0 && RegExp(r'\bRow\(').hasMatch(lines[owner])) {
      hits.add('$path:${i + 1}');
    }
  }
  return hits;
}

void main() {
  test('the guard flags flush boxed buttons in a Row and spares the rest', () {
    const flush = '''
Row(
  children: [
    WpIconButton(
      onPressed: a,
    ),
    WpIconButton(
      onPressed: b,
    ),
  ],
)''';
    const spaced = '''
Row(
  children: [
    WpIconButton(
      onPressed: a,
    ),
    const SizedBox(width: WpSpacing.buttonGap),
    WpIconButton(
      onPressed: b,
    ),
  ],
)''';
    const wrapped = '''
Wrap(
  spacing: WpSpacing.buttonGap,
  children: [
    WpButton(
      onPressed: a,
    ),
    WpButton(
      onPressed: b,
    ),
  ],
)''';
    const ghosts = '''
Row(
  children: [
    WpIconButton.ghost(
      onPressed: a,
    ),
    WpIconButton.ghost(
      onPressed: b,
    ),
  ],
)''';
    expect(flushButtonsInRows('x', flush.split('\n')), ['x:6']);
    expect(flushButtonsInRows('x', spaced.split('\n')), isEmpty);
    expect(flushButtonsInRows('x', wrapped.split('\n')), isEmpty);
    expect(flushButtonsInRows('x', ghosts.split('\n')), isEmpty);
  });

  test('no Row in lib/ puts two boxed buttons flush side by side', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.contains('/generated/')) continue;
      hits.addAll(flushButtonsInRows(f.path, f.readAsLinesSync()));
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Buttons side by side need WpButtonGroup or WpSpacing.buttonGap '
          '(#1687).',
    );
  });
}
