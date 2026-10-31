/// UIA-FND-10 — icon sizes come from the `WpIconSize` scale only.
///
/// This test reads the source of `lib/` and fails when it finds a numeric
/// literal used as an icon size:
///  1. `size: <number>` inside an `Icon(`, `FaIcon(` or `IconThemeData(` call,
///  2. `iconSize: <number>` anywhere.
/// Expressions that start from a named step (`WpIconSize.sm * 0.8`) are fine.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/tokens.dart';

final RegExp _iconCtor = RegExp(r'\b(Icon|FaIcon|IconThemeData)\(');
final RegExp _sizeLiteral = RegExp(r'\bsize:\s*\d');
final RegExp _iconSizeLiteral = RegExp(r'\biconSize:\s*\d');

List<File> _dartSources() {
  return Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// The text of one constructor call, from its opening parenthesis to the
/// matching closing one.
String _callArgs(String source, int openParen) {
  var depth = 0;
  for (var i = openParen; i < source.length; i++) {
    final c = source[i];
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return source.substring(openParen, i + 1);
    }
  }
  return source.substring(openParen);
}

int _lineOf(String source, int offset) =>
    '\n'.allMatches(source.substring(0, offset)).length + 1;

void main() {
  test('UIA-FND-10: no numeric literal icon size outside WpIconSize', () {
    final offenders = <String>[];
    for (final file in _dartSources()) {
      final path = file.path.replaceAll('\\', '/');
      final source = file.readAsStringSync();

      for (final call in _iconCtor.allMatches(source)) {
        final args = _callArgs(source, call.end - 1);
        if (_sizeLiteral.hasMatch(args)) {
          offenders.add('$path:${_lineOf(source, call.start)} size literal');
        }
      }
      for (final m in _iconSizeLiteral.allMatches(source)) {
        offenders.add('$path:${_lineOf(source, m.start)} iconSize literal');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use a WpIconSize step instead of a number:\n${offenders.join('\n')}',
    );
  });

  test('UIA-FND-10: WpIconSize steps include 12 and 18 and stay ascending', () {
    final values = [
      WpIconSize.xxs,
      WpIconSize.xs,
      WpIconSize.sm,
      WpIconSize.smMd,
      WpIconSize.md,
      WpIconSize.lg,
      WpIconSize.xl,
      WpIconSize.xxl,
    ];
    expect(values, [12, 14, 16, 18, 20, 24, 32, 48]);
  });
}
