import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Windows often has no `python3` on PATH: the name resolves to the Store
/// alias stub, which exits with 9009. Try the usual launchers in order.
ProcessResult _runGenerator(List<String> args) {
  const launchers = [
    ['python3'],
    ['python'],
    ['py', '-3'],
  ];
  final perUser = _perUserPythonInstalls();
  ProcessResult? last;
  for (final launcher in [
    ...launchers,
    ...perUser.map((exe) => [exe]),
  ]) {
    try {
      final result = Process.runSync(launcher.first, [
        ...launcher.skip(1),
        ...args,
      ]);
      last = result;
      if (result.exitCode != 9009) return result;
    } on ProcessException {
      // Launcher not installed; try the next one.
    }
  }
  return last ?? ProcessResult(0, 127, '', 'no Python interpreter found');
}

/// python.org's default per-user install on Windows, used when no launcher is
/// on PATH (the PATH entries may be Store stubs or a broken shim).
List<String> _perUserPythonInstalls() {
  if (!Platform.isWindows) return const [];
  final local = Platform.environment['LOCALAPPDATA'];
  if (local == null) return const [];
  final root = Directory('$local\\Programs\\Python');
  if (!root.existsSync()) return const [];
  return [
    for (final dir in root.listSync().whereType<Directory>())
      if (dir.path.split(Platform.pathSeparator).last.startsWith('Python3'))
        '${dir.path}\\python.exe',
  ]..sort((a, b) => b.compareTo(a));
}

// THIRD_PARTY_NOTICES.md is generated; this keeps it from going stale.
void main() {
  test('THIRD_PARTY_NOTICES.md is up to date with its generator', () {
    final result = _runGenerator(const [
      'scripts/generate-third-party-notices.py',
      '--check',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  });

  test('the notices never list espeak-ng or piper as shipped', () {
    final text = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
    expect(text.toLowerCase(), isNot(contains('espeak')));
    expect(text.toLowerCase(), isNot(contains('piper')));
  });
}
