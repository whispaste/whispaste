/// Skipped-test ratchet: the number of skip markers in the test sources may
/// only fall.
///
/// Counted per line (comments ignored): Dart `skip:` arguments that are not
/// `null`/`false`, `markTestSkipped(`, `@Skip(`, and TS `test|it|describe`
/// `.skip(` / `.fixme(`. The ceiling lives in `tool/skipped_tests_baseline.json`
/// (`{"max": N}`). More markers than the ceiling is red; fewer is red too until
/// the ceiling is lowered (`dart tool/check_skipped_tests.dart --update`), so a
/// closed gap cannot reopen. Every remaining marker is a condition of the
/// environment (platform, hardware, opt-in run), never an unconditional skip.
///
/// Run from the repo root (pre-commit hook does):
///   dart tool/check_skipped_tests.dart [--update]
library;

import 'dart:convert';
import 'dart:io';

const defaultBaselinePath = 'tool/skipped_tests_baseline.json';
const defaultRoots = [
  'test',
  'integration_test',
  'generators',
  'benchmarks',
  'website/tests',
  'website/src',
];

final _dartMarker = RegExp(
  r'\bskip:\s*(?!null\b|false\b)\S|\bmarkTestSkipped\(|@Skip\(',
);
final _tsMarker = RegExp(r'\b(?:test|it|describe)\.(?:skip|fixme)\(');

/// Number of skip markers in [source] of a file named [name].
int countSkipMarkers(String name, String source) {
  final marker = name.endsWith('.dart') ? _dartMarker : _tsMarker;
  var count = 0;
  for (final line in const LineSplitter().convert(source)) {
    if (line.trimLeft().startsWith('//')) continue;
    count += marker.allMatches(line).length;
  }
  return count;
}

bool _isTestFile(String path) =>
    path.endsWith('_test.dart') ||
    path.endsWith('.test.ts') ||
    path.endsWith('.spec.ts') ||
    path.endsWith('.test.mjs');

/// Marker count per test file under [roots] (files without markers omitted).
Map<String, int> scanSkipMarkers(List<String> roots) {
  final result = <String, int>{};
  for (final root in roots) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      final path = entity.path.replaceAll(r'\', '/');
      if (entity is! File || path.contains('node_modules/')) continue;
      if (!_isTestFile(path)) continue;
      final n = countSkipMarkers(path, entity.readAsStringSync());
      if (n > 0) result[path] = n;
    }
  }
  return result;
}

/// One error per violation; empty means the gate passes.
List<String> checkSkipCeiling({required int count, required int max}) {
  if (count > max) {
    return [
      'skipped tests rose to $count (ceiling $max): repair, delete or do not '
          'add the skip',
    ];
  }
  if (count < max) {
    return [
      'skipped tests fell to $count (ceiling $max): lower the ceiling with '
          '`dart tool/check_skipped_tests.dart --update`',
    ];
  }
  return const [];
}

int readCeiling(String baselinePath) {
  final file = File(baselinePath);
  if (!file.existsSync()) return 0;
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json['max'] as int;
}

void main(List<String> args) {
  final count = scanSkipMarkers(
    defaultRoots,
  ).values.fold<int>(0, (a, b) => a + b);
  if (args.contains('--update')) {
    File(defaultBaselinePath).writeAsStringSync('{"max": $count}\n');
    stdout.writeln('skipped-test ceiling set to $count');
    return;
  }
  final errors = checkSkipCeiling(
    count: count,
    max: readCeiling(defaultBaselinePath),
  );
  if (errors.isEmpty) {
    stdout.writeln('Skipped tests: $count (ceiling holds)');
    return;
  }
  errors.forEach(stderr.writeln);
  exitCode = 1;
}
