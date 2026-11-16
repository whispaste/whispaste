// Runs `flutter test` under the hard limits of the test strategy and turns a
// breach into a red run that names the test:
//   - a passing test over the test limit counts as failed,
//   - silence (no reporter event) ends the run and names the running tests,
//   - the run limit ends the run on the spot and names the running tests; the
//     results up to then stay visible (failures print as they happen).
// The output is short: failures as they happen, a progress line, the slowest
// tests at the end. The full reporter stream goes to --report.
//
// Usage: dart tool/test_guard.dart [--test-limit=10] [--stall=20]
//          [--startup=120] [--run-limit=180] [--report=<file>]
//          [--shuffle[=<seed>]] -- <flutter test arguments>
// --shuffle runs the tests of each file in random order (random seed unless
// given); a red run names the seed and the command that replays the order.
// Limits are seconds. Exit 0 only for a green run within all limits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class Limits {
  const Limits({
    this.test = const Duration(seconds: 10),
    this.stall = const Duration(seconds: 20),
    this.startup = const Duration(seconds: 120),
    this.run = const Duration(seconds: 180),
  });

  final Duration test;
  final Duration stall;
  final Duration startup;
  final Duration run;
}

class Timing {
  const Timing(this.label, this.duration);

  final String label;
  final Duration duration;

  @override
  String toString() =>
      '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s  $label';
}

class _Running {
  _Running(this.label, this.startMs);

  final String label;
  final int startMs;
}

/// Reads the events of the JSON reporter and judges the run.
class TestGuard {
  TestGuard([this.limits = const Limits()]);

  final Limits limits;
  final failures = <String>[];
  final slow = <Timing>[];
  final _timings = <Timing>[];
  final _suites = <int, String>{};
  final _running = <int, _Running>{};
  final _errors = <int, StringBuffer>{};

  /// Tests that already reported a passing result, by id: an error event
  /// for one of them is a failure after completion (pending async work).
  final _finished = <int, String>{};
  int passed = 0;
  int failed = 0;
  int skipped = 0;

  /// True once a real test reported a result: from then on the short
  /// silence limit applies instead of the startup limit.
  bool sawResult = false;

  /// Feeds one reporter event; returns lines worth printing right away.
  List<String> add(Map<String, Object?> event) {
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'];
        if (suite is Map && suite['id'] is int) {
          _suites[suite['id'] as int] = '${suite['path'] ?? '?'}';
        }
      case 'testStart':
        final test = event['test'];
        if (test is Map && test['id'] is int) {
          final path = _suites[test['suiteID']] ?? '?';
          _running[test['id'] as int] = _Running(
            '$path | ${test['name']}',
            _ms(event['time']),
          );
        }
      case 'error':
        final id = event['testID'];
        final late = _finished.remove(id);
        if (late != null) {
          passed--;
          failed++;
          failures.add(late);
          return [
            'FAILED AFTER COMPLETION  $late',
            ..._head('${event['error']}', 20),
          ];
        }
        if (id is int) {
          (_errors[id] ??= StringBuffer())
            ..writeln(event['error'])
            ..writeln(event['stackTrace']);
        }
      case 'testDone':
        return _done(event);
    }
    return const [];
  }

  List<String> _done(Map<String, Object?> event) {
    final test = _running.remove(event['testID']);
    final error = _errors.remove(event['testID']);
    if (test == null) return const [];
    // Hidden entries are the "loading <file>" pseudo tests and the setUpAll
    // and tearDownAll hooks: a failure there still counts, a duration not.
    final hidden = event['hidden'] == true;
    final ok = event['result'] == 'success';
    if (ok && hidden) return const [];
    sawResult = sawResult || !hidden;
    if (event['skipped'] == true) {
      skipped++;
      return const [];
    }
    final timing = Timing(
      test.label,
      Duration(milliseconds: _ms(event['time']) - test.startMs),
    );
    if (!hidden) _timings.add(timing);
    if (!ok) {
      failed++;
      failures.add(test.label);
      return ['FAILED  ${test.label}', ..._head('${error ?? ''}', 40)];
    }
    if (timing.duration > limits.test) {
      failed++;
      slow.add(timing);
      return ['TOO SLOW (limit ${limits.test.inSeconds} s)  $timing'];
    }
    passed++;
    if (event['testID'] case final int id) _finished[id] = test.label;
    return const [];
  }

  /// The silence the run may show right now.
  Duration get silenceLimit => sawResult ? limits.stall : limits.startup;

  /// True when the run has to end now: silence over the current limit, or the
  /// run limit reached. Checked live, so a slow run ends at the limit instead
  /// of running on until an outer step timeout kills it without a report.
  bool mustEnd({required Duration wall, required Duration silence}) =>
      silence > silenceLimit || wall > limits.run;

  /// Tests that started and have not reported a result.
  List<String> get open => [for (final test in _running.values) test.label];

  List<Timing> slowest(int count) {
    final sorted = [..._timings]
      ..sort((a, b) => b.duration.compareTo(a.duration));
    return sorted.take(count).toList();
  }

  /// Reasons why the run is red; empty for a green run.
  List<String> verdict({
    required Duration wall,
    required int exitCode,
    Duration? stalledAfter,
  }) => [
    if (stalledAfter != null)
      'no reporter event for ${stalledAfter.inSeconds} s, run ended; '
          'running: ${open.isEmpty ? 'no test (loading or compiling)' : open.join('; ')}',
    if (failures.isNotEmpty) '${failures.length} test(s) failed',
    if (slow.isNotEmpty)
      '${slow.length} passing test(s) over ${limits.test.inSeconds} s',
    if (wall > limits.run && stalledAfter == null)
      'run reached ${wall.inSeconds} s, limit ${limits.run.inSeconds} s, '
          'run ended; running: ${open.isEmpty ? 'no test' : open.join('; ')}',
    if (exitCode != 0 &&
        stalledAfter == null &&
        failures.isEmpty &&
        wall <= limits.run)
      'flutter test exited with $exitCode',
  ];

  static int _ms(Object? value) => value is num ? value.toInt() : 0;

  static List<String> _head(String text, int lines) {
    final all = const LineSplitter().convert(text.trimRight());
    return [
      for (final line in all.take(lines)) '  $line',
      if (all.length > lines) '  ... (${all.length - lines} more lines)',
    ];
  }
}

Future<void> _killTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
    return;
  }
  final pids = <int>[pid];
  for (var i = 0; i < pids.length; i++) {
    final children = await Process.run('pgrep', ['-P', '${pids[i]}']);
    pids.addAll('${children.stdout}'.split('\n').map(int.tryParse).nonNulls);
  }
  for (final each in pids.reversed) {
    Process.killPid(each, ProcessSignal.sigkill);
  }
}

/// Seed for `--shuffle`: the given one, or a fresh random 32-bit seed.
int shuffleSeed(String? given, [int Function()? random]) =>
    int.tryParse(given ?? '') ?? (random ?? _randomSeed)();

int _randomSeed() => Random().nextInt(0x7fffffff) + 1;

/// The command that replays exactly the shuffled order of a run.
String shuffleReplay(int seed, List<String> testArgs) =>
    'dart tool/test_guard.dart --shuffle=$seed -- ${testArgs.join(' ')}';

Duration _seconds(String value) => Duration(seconds: int.parse(value));

Future<void> main(List<String> args) async {
  final split = args.indexOf('--');
  if (split < 0) {
    stderr.writeln(
      'usage: dart tool/test_guard.dart [--test-limit=N] '
      '[--stall=N] [--startup=N] [--run-limit=N] [--report=FILE] '
      '-- <flutter test arguments>',
    );
    exit(64);
  }
  final options = <String, String>{
    for (final arg in args.take(split))
      arg.split('=').first: arg.split('=').skip(1).join('='),
  };
  const defaults = Limits();
  final guard = TestGuard(
    Limits(
      test: options['--test-limit']?.let(_seconds) ?? defaults.test,
      stall: options['--stall']?.let(_seconds) ?? defaults.stall,
      startup: options['--startup']?.let(_seconds) ?? defaults.startup,
      run: options['--run-limit']?.let(_seconds) ?? defaults.run,
    ),
  );
  final testArgs = args.skip(split + 1).toList();
  final seed = options.containsKey('--shuffle')
      ? shuffleSeed(options['--shuffle'])
      : null;
  if (seed != null) stdout.writeln('Test order shuffled, seed $seed');
  final reportPath = options['--report'];
  final report = reportPath == null ? null : File(reportPath).openWrite();

  final wall = Stopwatch()..start();
  final silence = Stopwatch()..start();
  final process = await Process.start('flutter', [
    'test',
    ...testArgs,
    if (seed != null) '--test-randomize-ordering-seed=$seed',
    '--reporter=json',
  ], runInShell: Platform.isWindows);
  unawaited(stderr.addStream(process.stderr));

  Duration? stalledAfter;
  var lastProgress = Duration.zero;
  final watch = Timer.periodic(const Duration(seconds: 1), (timer) {
    if (guard.mustEnd(wall: wall.elapsed, silence: silence.elapsed)) {
      if (silence.elapsed > guard.silenceLimit) stalledAfter = silence.elapsed;
      timer.cancel();
      unawaited(_killTree(process.pid));
    } else if (wall.elapsed - lastProgress >= const Duration(seconds: 15)) {
      lastProgress = wall.elapsed;
      stdout.writeln(
        '${wall.elapsed.inSeconds} s: +${guard.passed} '
        '~${guard.skipped} -${guard.failed}',
      );
    }
  });

  await for (final line
      in process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    report?.writeln(line);
    Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue; // tool chatter between the events
    }
    if (event is! Map<String, Object?>) continue;
    silence.reset();
    guard.add(event).forEach(stdout.writeln);
  }
  final exitCode = await process.exitCode;
  watch.cancel();
  await report?.close();

  stdout.writeln(
    '\n${guard.passed} passed, ${guard.skipped} skipped, '
    '${guard.failed} failed in ${wall.elapsed.inSeconds} s. Slowest tests:',
  );
  guard.slowest(10).forEach(stdout.writeln);
  final reasons = guard.verdict(
    wall: wall.elapsed,
    exitCode: exitCode,
    stalledAfter: stalledAfter,
  );
  for (final reason in reasons) {
    stdout.writeln('RED: $reason');
  }
  if (seed != null && reasons.isNotEmpty) {
    stdout.writeln(
      'Shuffle seed $seed. Replay this order locally:\n'
      '  ${shuffleReplay(seed, testArgs)}',
    );
  }
  await stdout.flush();
  exit(reasons.isEmpty ? 0 : 1);
}

extension<T> on T {
  R let<R>(R Function(T) convert) => convert(this);
}
