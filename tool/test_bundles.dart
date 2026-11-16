// Bundles test files per area for the lab lanes (#1492): every test file
// costs its own compile and isolate start (about 2 s each on the lab guests,
// 41 min for 1,214 files), so the lane runs a few generated bundle files that
// import the test files as libraries and call each `main` inside a group
// named after the file. Failures still name the file through that group.
//
// A file with a library-level annotation (@Tags, @TestOn, @Timeout, @Skip,
// @OnPlatform) is not bundled: an import drops those annotations, so a golden
// or platform-bound file would run where it must not. An async main cannot
// be a group body either. A file that needs an isolate of its own says so
// with a line comment `// test_bundles: own run (<reason>)`. All of these
// run on their own.
//
// Usage: dart tool/test_bundles.dart <list file> <bundle dir under test/> <out>
//          [<max files per bundle> [<files per run>]]
//          With <files per run>, the list is split into guarded runs: a guest
//          that cannot run the full lane within one 3-minute run (#1412) runs
//          it as several, each within the limit (lab run 2848: win ran 4,561
//          of about 13,000 tests in 180 s). <out>.shards gets their number,
//          <out>.0, <out>.1, ... the paths of each run. Each run has its own
//          bundles in <bundle dir>/run_<i>, so it compiles only those: with
//          flutter test --total-shards every run loaded all 140 bundles and
//          ran a 36th of the tests (#1570, lab run 9638: 480 s of loading,
//          27 s of tests). Without it there is one run, <out>.0 = <out>.
//          <list file>: test files or directories, one per line (the output
//          of tool/lab_tests.dart). Writes the paths to hand to flutter test
//          to <out>, one per line: the bundle dir, then the files that run
//          on their own (a file, not stdout: PowerShell would re-encode it). The bundle dir
//          is wiped first; it must lie under test/ so flutter_test_config.dart
//          applies (lab.yml uses test/_lab_bundles, which git ignores).
import 'dart:io';

/// Default upper bound of files per bundle: keeps -j workers balanced and a
/// failing bundle's log readable. The lab guests pass 15: parallel bundle
/// processes of 40 widget-test files exhausted their memory (win 4 GB,
/// "Could not start thread", run 2845; ubu 6 GB, oom_kill, run 2849).
const maxFilesPerBundle = 40;

final _libraryAnnotation = RegExp(
  r'^@(Tags|TestOn|Timeout|Skip|OnPlatform)\b',
  multiLine: true,
);

final _asyncMain = RegExp(
  r'^(Future<void>|Future|FutureOr<void>)\s+main\s*\(|^\s*(void\s+)?main\s*\([^)]*\)\s*async\b',
  multiLine: true,
);
const ownRunMarker = '// test_bundles: own run';

/// Whether [source] must run as its own test file (see the header).
bool needsOwnRun(String source) =>
    _libraryAnnotation.hasMatch(source) ||
    _asyncMain.hasMatch(source) ||
    source.contains(ownRunMarker);

/// One guarded run: its bundles and the files that run on their own.
class Run {
  Run();
  final bundles = <Bundle>[];
  final own = <String>[];
  int get files => own.length + bundles.fold(0, (n, b) => n + b.files.length);
}

/// Splits [bundles] and the [own] files into runs of at most [perRun] test
/// files each (0: one run), in order; a bundle is never split, so a run
/// holds at least one entry even when that entry alone exceeds [perRun].
List<Run> planRuns(List<Bundle> bundles, List<String> own, int perRun) {
  final runs = [Run()];
  void fit(int size) {
    final last = runs.last;
    if (perRun > 0 && last.files > 0 && last.files + size > perRun) {
      runs.add(Run());
    }
  }

  for (final b in bundles) {
    fit(b.files.length);
    runs.last.bundles.add(b);
  }
  for (final f in own) {
    fit(1);
    runs.last.own.add(f);
  }
  return runs;
}

/// Area of a test file: `test/<top>/<sub>` for nested files
/// (test/features/history/...), `test/<top>` for a file directly in a top
/// folder, `test` for the files at the root.
String areaOf(String path) {
  final parts = path.split('/');
  if (parts.length <= 2) return 'test';
  if (parts.length == 3) return '${parts[0]}/${parts[1]}';
  return '${parts[0]}/${parts[1]}/${parts[2]}';
}

/// One bundle: its file name and the test files it runs.
class Bundle {
  const Bundle(this.name, this.files);
  final String name;
  final List<String> files;
}

/// Splits [files] (repo-relative, `/`) into bundles per area, at most
/// [maxFilesPerBundle] each, in a stable order.
List<Bundle> planBundles(
  Iterable<String> files, {
  int maxFiles = maxFilesPerBundle,
}) {
  final byArea = <String, List<String>>{};
  for (final f in files) {
    byArea.putIfAbsent(areaOf(f), () => []).add(f);
  }
  final bundles = <Bundle>[];
  for (final area in byArea.keys.toList()..sort()) {
    final list = byArea[area]!..sort();
    final base = area.replaceAll('/', '_');
    for (var i = 0; i * maxFiles < list.length; i++) {
      final end = (i + 1) * maxFiles;
      bundles.add(
        Bundle(
          '${base}_${i + 1}_test.dart',
          list.sublist(i * maxFiles, end < list.length ? end : list.length),
        ),
      );
    }
  }
  return bundles;
}

/// Source of a bundle that lives in [bundleDir] (repo-relative).
String bundleSource(Bundle bundle, String bundleDir) {
  // Relative to test/, so the import stays inside the test folder.
  final up = '../' * (bundleDir.split('/').length - 1);
  final b = StringBuffer()
    ..writeln('// Generated by tool/test_bundles.dart; do not edit or commit.')
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln();
  for (var i = 0; i < bundle.files.length; i++) {
    final inTest = bundle.files[i].substring('test/'.length);
    b.writeln("import '$up$inTest' as t$i;");
  }
  b
    ..writeln()
    ..writeln('void main() {');
  for (var i = 0; i < bundle.files.length; i++) {
    final name = bundle.files[i].substring('test/'.length);
    b.writeln("  group('$name', t$i.main);");
  }
  b.writeln('}');
  return b.toString();
}

void main(List<String> args) {
  final maxFiles = args.length >= 4 ? int.tryParse(args[3]) : maxFilesPerBundle;
  final perRun = args.length == 5 ? int.tryParse(args[4]) : 0;
  if (args.length < 3 ||
      args.length > 5 ||
      perRun == null ||
      perRun < 0 ||
      !args[1].startsWith('test/') ||
      maxFiles == null ||
      maxFiles < 1) {
    stderr.writeln(
      'usage: test_bundles.dart <list file> <bundle dir under test/> <out> '
      '[<max files per bundle> [<files per run>]]',
    );
    exit(2);
  }
  final bundleDir = args[1].endsWith('/')
      ? args[1].substring(0, args[1].length - 1)
      : args[1];
  final out = Directory(bundleDir);
  if (out.existsSync()) out.deleteSync(recursive: true);

  final files = <String>{};
  for (final line in File(args[0]).readAsLinesSync()) {
    final entry = line.trim().replaceAll(r'\', '/');
    if (entry.isEmpty) continue;
    if (FileSystemEntity.isDirectorySync(entry)) {
      for (final f in Directory(entry).listSync(recursive: true)) {
        final path = f.path.replaceAll(r'\', '/');
        if (f is File && path.endsWith('_test.dart')) files.add(path);
      }
    } else if (entry.endsWith('_test.dart') && File(entry).existsSync()) {
      files.add(entry);
    }
  }

  final own = <String>[];
  final bundled = <String>[];
  for (final f in files) {
    (needsOwnRun(File(f).readAsStringSync()) ? own : bundled).add(f);
  }
  final bundles = planBundles(bundled, maxFiles: maxFiles);
  final runs = planRuns(bundles, own..sort(), perRun);
  final split = runs.length > 1;
  final all = <String>[];
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    final dir = split ? '$bundleDir/run_$i' : bundleDir;
    if (run.bundles.isNotEmpty) Directory(dir).createSync(recursive: true);
    for (final bundle in run.bundles) {
      File('$dir/${bundle.name}').writeAsStringSync(bundleSource(bundle, dir));
    }
    // The run's bundle dir as one path, not each bundle: the win command
    // line goes through cmd.exe (8,191 characters; 275 test paths failed,
    // run 2841).
    final paths = [if (run.bundles.isNotEmpty) dir, ...run.own];
    File('${args[2]}.$i').writeAsStringSync(paths.map((r) => '$r\n').join());
    if (!split) all.addAll(paths);
  }
  if (split) {
    all.addAll([if (bundles.isNotEmpty) bundleDir, ...own]);
  }
  File(args[2]).writeAsStringSync(all.map((r) => '$r\n').join());
  File('${args[2]}.shards').writeAsStringSync('${runs.length}\n');
  // stdout: PowerShell reports every stderr line as a NativeCommandError.
  stdout.writeln(
    'test_bundles: ${bundled.length} files in ${bundles.length} bundles, '
    '${own.length} on their own, ${runs.length} guarded run(s)',
  );
}
