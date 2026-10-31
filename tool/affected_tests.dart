// Picks the test files a change can break, for the pre-push test lane
// (scripts/check.sh push). The full suite stays in CI and the integration
// round; this lane catches the breakage before the push.
//
// A test is affected when
//   1. it is a changed test file, or
//   2. it imports a changed Dart file, directly or transitively (import,
//      export and part, relative or package:whispaste/), or
//   3. it reads repo files at run time (a guard) and one of the paths it
//      names is, or contains, a changed path — e.g. Directory('lib') for any
//      change under lib/, or 'scripts/whisper-cpp.pin' for the pin itself.
// A change that can affect every test (pubspec, analysis options, the test
// helpers' config) selects the whole suite. Generated localizations do not
// pass a change on through imports: nearly every widget test imports them,
// the l10n and manual guards cover them, and real importers come in through
// the source that changed with them.
//
// Usage: dart run tool/affected_tests.dart [<git range>]   (default
//        origin/dev...HEAD); prints one test path per line, or `ALL`.
//        --stdin reads the changed paths from stdin instead of git;
//        --with-distance prefixes each test with its import distance.
//        Tests come nearest first (see [Selection.distances]); within one
//        distance, tests reached through a rarely imported change come
//        before the importers of hub files.
import 'dart:io';

/// Paths whose change can break any test: run everything.
const fullSuiteTriggers = <String>[
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
  'dart_test.yaml',
  'test/flutter_test_config.dart',
];

/// Files whose importers are not selected through them (see the header).
bool isImportHub(String path) => path.startsWith('lib/core/l10n/generated/');

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);
final _conditional = RegExp(r'''\bif\s*\([^)]*\)\s*['"]([^'"]+)['"]''');
final _fileAccess = RegExp(r'''\b(?:File|Directory)\(\s*['"]([^'"$]+)['"]''');
final _anyFileAccess = RegExp(r'\b(?:File|Directory)\(');
final _repoPathLiteral = RegExp(
  r'''['"]((?:lib|scripts|native|windows|linux|macos|packages|website|tool|installer|design-tokens|\.github|\.githooks|test)/[^'"$\s]*|[A-Za-z0-9_.-]+\.(?:yaml|yml|md|json|pin))['"]''',
);

/// The result of [selectTests]: either every test, or the listed ones.
class Selection {
  const Selection.all(this.reason) : tests = const [], distances = const {};
  const Selection.some(this.tests, {this.distances = const {}}) : reason = null;

  /// Set when the whole suite must run.
  final String? reason;

  /// Nearest first (see [distances]).
  final List<String> tests;

  /// Import distance from the change per test: 0 for a changed test or a
  /// guard over a changed path, 1 for a test importing a changed file, ...
  final Map<String, int> distances;

  bool get isAll => reason != null;
}

/// [sources] maps every Dart file under lib/ and test/ (repo-relative, `/`
/// separators) to its content; [changed] lists the changed repo paths.
Selection selectTests(Map<String, String> sources, Iterable<String> changed) {
  final changedSet = changed.toSet();
  for (final path in changedSet) {
    if (fullSuiteTriggers.contains(path)) return Selection.all(path);
  }

  // Reverse import graph: file -> files that import it.
  final importers = <String, Set<String>>{};
  sources.forEach((file, content) {
    for (final target in _imports(file, content)) {
      importers.putIfAbsent(target, () => <String>{}).add(file);
    }
  });

  // Breadth-first from each changed file, so each test gets its shortest
  // import distance from a change (0 for a changed file, 1 for a direct
  // importer, ...) and, per distance, the smallest reach of a change that
  // gets there: a test reached through a change few tests depend on is the
  // likelier one to break.
  final selected = <String, int>{};
  final reach = <String, int>{};
  for (final seed in changedSet) {
    if (!seed.endsWith('.dart') || isImportHub(seed)) continue;
    final distance = <String, int>{};
    var frontier = [seed];
    for (var d = 0; frontier.isNotEmpty; d++) {
      final next = <String>[];
      for (final file in frontier) {
        if (distance.containsKey(file)) continue;
        distance[file] = d;
        next.addAll(importers[file] ?? const <String>{});
      }
      frontier = next;
    }
    final tests = {
      for (final e in distance.entries)
        if (_isTest(e.key) && sources.containsKey(e.key)) e.key: e.value,
    };
    tests.forEach((test, d) {
      final best = selected[test];
      if (best == null || d < best) {
        selected[test] = d;
        reach[test] = tests.length;
      } else if (d == best && tests.length < reach[test]!) {
        reach[test] = tests.length;
      }
    });
  }

  sources.forEach((file, content) {
    if (!_isTest(file) || selected[file] == 0) return;
    // A guard may pass its paths through a variable (File(path)), so any
    // file access counts; the repo paths it names decide.
    if (!_anyFileAccess.hasMatch(content)) return;
    final named = {
      for (final m in _fileAccess.allMatches(content)) _trim(m.group(1)!),
      for (final m in _repoPathLiteral.allMatches(content)) _trim(m.group(1)!),
    };
    for (final path in changedSet) {
      if (named.any((n) => n.isNotEmpty && _covers(n, path))) {
        selected[file] = 0;
        reach[file] = 0;
        return;
      }
    }
  });

  // Nearest first: changed tests and guards, then direct importers, then the
  // far end of the import graph. A time-capped run covers the near end.
  final ordered = selected.keys.toList()
    ..sort((a, b) {
      final byDistance = selected[a]!.compareTo(selected[b]!);
      if (byDistance != 0) return byDistance;
      final byReach = reach[a]!.compareTo(reach[b]!);
      return byReach != 0 ? byReach : a.compareTo(b);
    });
  return Selection.some(ordered, distances: selected);
}

bool _isTest(String path) =>
    path.startsWith('test/') && path.endsWith('_test.dart');

String _trim(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

/// Whether the repo path [named] by a guard is [changed] or a directory
/// containing it.
bool _covers(String named, String changed) =>
    changed == named || changed.startsWith('$named/');

Iterable<String> _imports(String file, String content) sync* {
  final uris = [
    for (final m in _directive.allMatches(content)) m.group(1)!,
    for (final m in _conditional.allMatches(content)) m.group(1)!,
  ];
  for (final uri in uris) {
    if (uri.startsWith('package:whispaste/')) {
      yield 'lib/${uri.substring('package:whispaste/'.length)}';
    } else if (!uri.contains(':')) {
      yield _normalize('${_dirname(file)}/$uri');
    }
  }
}

String _dirname(String path) {
  final i = path.lastIndexOf('/');
  return i < 0 ? '.' : path.substring(0, i);
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (out.isNotEmpty) out.removeLast();
    } else {
      out.add(part);
    }
  }
  return out.join('/');
}

void main(List<String> args) {
  final withDistance = args.contains('--with-distance');
  args = [
    for (final a in args)
      if (a != '--with-distance') a,
  ];
  final String listing;
  if (args.contains('--stdin')) {
    final lines = <String>[];
    String? line;
    while ((line = stdin.readLineSync()) != null) {
      lines.add(line!);
    }
    listing = lines.join('\n');
  } else {
    final range = args.isEmpty ? 'origin/dev...HEAD' : args.first;
    final diff = Process.runSync('git', [
      'diff',
      '--name-only',
      '--no-renames',
      range,
    ]);
    if (diff.exitCode != 0) {
      stderr.write(diff.stderr);
      exit(2);
    }
    listing = diff.stdout as String;
  }
  final changed = listing.split('\n').where((l) => l.isNotEmpty);

  final sources = <String, String>{};
  for (final root in ['lib', 'test']) {
    final dir = Directory(root);
    if (!dir.existsSync()) continue;
    for (final f in dir.listSync(recursive: true)) {
      if (f is File && f.path.endsWith('.dart')) {
        sources[f.path.replaceAll(r'\', '/')] = f.readAsStringSync();
      }
    }
  }

  final selection = selectTests(sources, changed);
  if (selection.isAll) {
    stdout.writeln('ALL');
    stderr.writeln('affected_tests: ${selection.reason} changed: full suite');
  } else {
    for (final test in selection.tests) {
      stdout.writeln(
        withDistance ? '${selection.distances[test]}\t$test' : test,
      );
    }
  }
}
