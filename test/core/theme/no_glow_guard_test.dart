/// UIA-VIS-12 — the no-glow guard.
///
/// Maintainer rule, 2026-10-19: nothing in the app glows. No glow, no halo,
/// no bloom, no neon, in any style, token, widget or comment. Light is never a
/// depth or state cue here; focus, selection and recording are carried by
/// solid outlines, flat fills, a check mark, or a pulse in form and opacity.
///
/// This test reads the source of `lib/` and fails when it finds
///  1. the words glow / bloom / neon / halo in identifiers or comments,
///  2. a `BoxShadow` or `Shadow` whose colour comes from an accent or brand
///     colour (a coloured shadow at any offset is a glow in disguise),
///  3. `MaskFilter.blur` outside the allowlist below. Each allowlisted file
///     paints only neutral, dark drop shadows or legibility shadows, never a
///     coloured light source.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Words that name the forbidden light effects. `halo` is matched only when
/// it is not the start of a longer lower-case word (`withaloud`), but it still
/// matches camel-case identifiers such as `glassSpecularHaloOffset`.
final List<RegExp> _forbiddenWords = [
  RegExp(r'glow|bloom|neon', caseSensitive: false),
  RegExp(r'[Hh]alo(?![a-z])'),
];

/// Accent and brand colour names. A shadow that reads one of these is coloured
/// light, not a neutral shadow.
final RegExp _accentColour = RegExp(
  r'accent|brand|cyan|teal|amber|violet|primary|highlight|recording|focus|glow',
  caseSensitive: false,
);

final RegExp _shadowCtor = RegExp(r'\b(BoxShadow|Shadow)\(');
final RegExp _maskBlur = RegExp(r'MaskFilter\.blur');

/// Files allowed to use `MaskFilter.blur`. Each one paints only neutral dark
/// shadows: the capsule and floating-button drop shadow (depth, ADR 0002) and
/// the glyph legibility shadow over the white close/stop/status glyphs. Adding
/// a file here needs a reason that is not "it looks nicer".
const Map<String, String> _maskBlurAllowlist = {
  'lib/widgets/floating_button/floating_button_painter.dart':
      'neutral dark drop shadow under the disc (depth only)',
  'lib/widgets/floating_overlay/overlay_painter.dart':
      'neutral dark drop shadow under the capsule and dark legibility shadow under the white glyphs',
};

List<File> _dartSources() {
  final root = Directory('lib');
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Repo-relative path with forward slashes, e.g. `lib/widgets/wp_focus_ring.dart`.
String _relative(File f) => f.path.replaceAll('\\', '/');

/// The text of one `BoxShadow(` / `Shadow(` constructor call, from its opening
/// parenthesis to the matching closing one.
String _constructorArgs(String source, int openParen) {
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

void main() {
  final sources = _dartSources();

  test('lib/ contains Dart sources to scan', () {
    expect(sources, isNotEmpty);
  });

  test('no glow, bloom, neon or halo words in identifiers or comments', () {
    final hits = <String>[];
    for (final f in sources) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_forbiddenWords.any((re) => re.hasMatch(lines[i]))) {
          hits.add('${_relative(f)}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'UIA-VIS-12: the app has no glow. Replace with a solid outline, a flat '
          'fill, a check mark or a pulse in form and opacity.\n${hits.join('\n')}',
    );
  });

  test('no BoxShadow or Shadow coloured with an accent or brand colour', () {
    final hits = <String>[];
    for (final f in sources) {
      final source = f.readAsStringSync();
      for (final m in _shadowCtor.allMatches(source)) {
        final args = _constructorArgs(source, m.end - 1);
        if (_accentColour.hasMatch(args)) {
          final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
          hits.add('${_relative(f)}:$line: ${m.group(1)} with accent colour');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'UIA-VIS-12: a coloured shadow is a glow.\n${hits.join('\n')}',
    );
  });

  test('MaskFilter.blur only in the allowlisted neutral-shadow files', () {
    final hits = <String>[];
    for (final f in sources) {
      final path = _relative(f);
      if (_maskBlurAllowlist.containsKey(path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_maskBlur.hasMatch(lines[i])) {
          hits.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'UIA-VIS-12: a blurred mask is a glow unless it is a neutral shadow in '
          'an allowlisted file. Use a crisp outline instead.\n${hits.join('\n')}',
    );
  });

  test(
    'every allowlisted file still exists and still uses MaskFilter.blur',
    () {
      for (final entry in _maskBlurAllowlist.entries) {
        final f = File(entry.key);
        expect(
          f.existsSync(),
          isTrue,
          reason: '${entry.key} is gone; drop it from the allowlist',
        );
        expect(
          _maskBlur.hasMatch(f.readAsStringSync()),
          isTrue,
          reason: '${entry.key} no longer blurs; drop it from the allowlist',
        );
      }
    },
  );
}
