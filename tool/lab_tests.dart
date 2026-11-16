// Picks the test files of the fast lab lane (lab.yml, lab/ubu and lab/win):
// after a merge only the tests the change can break run (#1493); the full
// suite stays in lab-full.yml and the integration round.
//
// The change is measured against the tree of the last green fast-lab run of
// this guest, not against the push's before SHA: a queued push can be
// superseded without being tested, and a red run must not move the baseline
// (its broken tests run again next time). The baseline is the file listing
// of `git ls-tree -r HEAD`, so no history or fetch is needed (shallow
// checkout after a guest reset). Without a recorded baseline (first run, guest
// reset) the parent commit's tree stands in when the checkout has it.
// Selection itself is tool/affected_tests.dart.
//
// Usage: dart tool/lab_tests.dart select <cache dir> <out file>
//          writes one test path per line; an empty file means no test is
//          affected. LAB_FULL=true (manual run) forces the full lane.
//        dart tool/lab_tests.dart record <cache dir>
//          after a green test step: the current tree becomes the baseline.
import 'dart:io';

import 'affected_tests.dart';

/// Changes that can break any test without an import: the full lane runs.
/// The lane's own tools are not on this list: their tests come in through
/// imports, and a full lane over the 3-minute limit would never turn green
/// and so never record a baseline.
const laneTriggers = <String>['.flutter-version'];

/// File name of the baseline inside the cache directory.
const baselineName = 'flutter-tests-tree';

/// What the fast lane runs: [tests] (full lane when [reason] is set).
class LabPlan {
  const LabPlan.full(this.reason, this.tests);
  const LabPlan.some(this.tests) : reason = null;

  /// Why the full lane runs; null for a selection.
  final String? reason;
  final List<String> tests;

  bool get isFull => reason != null;
}

/// Paths whose entry (mode, type, blob or presence) differs between two
/// `git ls-tree -r` listings.
Set<String> changedPaths(String baseline, String current) {
  Map<String, String> parse(String listing) => {
    for (final line in listing.split('\n'))
      if (line.contains('\t'))
        line.substring(line.indexOf('\t') + 1): line.substring(
          0,
          line.indexOf('\t'),
        ),
  };
  final a = parse(baseline), b = parse(current);
  return {
    for (final path in {...a.keys, ...b.keys})
      if (a[path] != b[path]) path,
  };
}

/// The fast lane's full test list: every test directory except the journeys
/// (lab-full.yml runs them) and the top-level test files, as the lane ran
/// before #1493.
List<String> fullLane(Iterable<String> testEntries) =>
    testEntries.where((e) => e != 'test/journeys').toList()..sort();

/// Decides the lane. [baseline] is null without a green run on record. A
/// selected test that is gone from [sources] (deleted) is dropped.
LabPlan planLab({
  required String? baseline,
  required String current,
  required Map<String, String> sources,
  required List<String> full,
  bool forceFull = false,
}) {
  if (forceFull) return LabPlan.full('full run requested', full);
  if (baseline == null) {
    return LabPlan.full('no green fast-lab run on record', full);
  }
  final changed = changedPaths(baseline, current);
  for (final trigger in laneTriggers) {
    if (changed.contains(trigger)) {
      return LabPlan.full('$trigger changed', full);
    }
  }
  final selection = selectTests(sources, changed);
  if (selection.isAll) return LabPlan.full('${selection.reason} changed', full);
  return LabPlan.some(
    [
      for (final t in selection.tests)
        if (!t.startsWith('test/journeys/') && sources.containsKey(t)) t,
    ]..sort(),
  );
}

String _git(List<String> args) {
  final r = Process.runSync('git', args);
  if (r.exitCode != 0) {
    stderr.write(r.stderr);
    exit(2);
  }
  return r.stdout as String;
}

void main(List<String> args) {
  if (args.length < 2 || !{'select', 'record'}.contains(args.first)) {
    stderr.writeln('usage: lab_tests.dart select <cache dir> <out file>');
    stderr.writeln('       lab_tests.dart record <cache dir>');
    exit(2);
  }
  final baselineFile = File('${args[1]}/$baselineName');
  final current = _git(['ls-tree', '-r', 'HEAD']);
  if (args.first == 'record') {
    baselineFile.parent.createSync(recursive: true);
    final tmp = File('${baselineFile.path}.tmp')..writeAsStringSync(current);
    tmp.renameSync(baselineFile.path);
    return;
  }
  if (args.length < 3) {
    stderr.writeln('usage: lab_tests.dart select <cache dir> <out file>');
    exit(2);
  }

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
  final full = fullLane([
    for (final e in Directory('test').listSync())
      if (e is Directory || e.path.endsWith('_test.dart'))
        e.path.replaceAll(r'\', '/'),
  ]);
  String? baseline;
  try {
    baseline = baselineFile.readAsStringSync();
  } on FileSystemException {
    final parent = Process.runSync('git', ['ls-tree', '-r', 'HEAD^']);
    if (parent.exitCode == 0) {
      baseline = parent.stdout as String;
      stdout.writeln('LAB-TESTS no green run on record: compared with HEAD^');
    }
  }
  final plan = planLab(
    baseline: baseline,
    current: current,
    sources: sources,
    full: full,
    forceFull: Platform.environment['LAB_FULL'] == 'true',
  );
  File(args[2])
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(plan.tests.map((t) => '$t\n').join());
  if (plan.isFull) {
    stdout.writeln('LAB-TESTS full lane: ${plan.reason}');
  } else if (plan.tests.isEmpty) {
    stdout.writeln(
      'LAB-SKIP flutter test: no test affected since the last green run',
    );
  } else {
    stdout.writeln(
      'LAB-TESTS ${plan.tests.length} affected test file(s) since the last green run:',
    );
    for (final t in plan.tests) {
      stdout.writeln('  $t');
    }
  }
}
