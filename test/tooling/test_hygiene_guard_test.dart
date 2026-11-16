import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard (#1491): tests stay silent and wait no real time.
///
/// * No `print`, `debugPrint` or `stdout`/`stderr` writes under `test/`
///   (`flutter_test_config.dart` silences the app logger on top of that).
/// * A real wait (`Future.delayed` with a duration above zero) may not be
///   added. Existing ones are listed in `real_wait_baseline.json` per file;
///   the count may only go down. Use `fakeAsync` or an injected clock/scale
///   (see `flashDurationScale`) instead.
void main() {
  final self =
      'test${Platform.pathSeparator}tooling${Platform.pathSeparator}'
      'test_hygiene_guard_test.dart';
  final files = [
    for (final e in Directory('test').listSync(recursive: true))
      if (e is File &&
          e.path.endsWith('.dart') &&
          !e.path.endsWith(self) &&
          // Child processes that talk over stdout, not tests.
          !e.path.contains(
            '${Platform.pathSeparator}fixtures${Platform.pathSeparator}',
          ))
        e,
  ];

  /// Source without line comments, so a mention in a comment is not a call.
  String code(File f) => f
      .readAsLinesSync()
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('no console output from tests', () {
    final output = RegExp(
      r'(^|[^\w.])(print|debugPrint)\(|std(out|err)\.write',
      multiLine: true,
    );
    // Deliberate output: a fixture string, a child process, a host-gated e2e
    // script line and a test that asserts on debugPrint itself.
    const allowed = [
      'platform_channel_parity_test.dart',
      'kill_writer_child.dart',
      'compositor_focus_e2e_test.dart',
      'no_transcript_in_logs_test.dart',
    ];
    final offenders = <String>[
      for (final f in files)
        if (output.hasMatch(code(f)) && !allowed.any(f.path.endsWith)) f.path,
    ];
    expect(offenders, isEmpty, reason: 'Tests must not write to the console.');
  });

  test('no new real waits (Future.delayed above zero)', () {
    final wait = RegExp(r'\.delayed\(\s*(?!(const\s+)?Duration(\.zero|\(\)))');
    final baseline =
        (jsonDecode(
                  File(
                    'test/tooling/real_wait_baseline.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)
            .cast<String, int>();
    final now = <String, int>{
      for (final f in files)
        if (wait.allMatches(code(f)).isNotEmpty)
          f.path.replaceAll(Platform.pathSeparator, '/'): wait
              .allMatches(code(f))
              .length,
    };
    final worse = <String>[
      for (final e in now.entries)
        if (e.value > (baseline[e.key] ?? 0))
          '${e.key}: ${e.value} > ${baseline[e.key] ?? 0}',
    ];
    expect(
      worse,
      isEmpty,
      reason:
          'New real wait. Use fakeAsync or an injected clock instead of '
          'Future.delayed; the baseline only shrinks.',
    );
    final stale = <String>[
      for (final e in baseline.entries)
        if ((now[e.key] ?? 0) < e.value) e.key,
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'Real waits were removed: lower the counts in '
          'real_wait_baseline.json (${stale.join(', ')}).',
    );
  });
}
