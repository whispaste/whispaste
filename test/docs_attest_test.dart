@TestOn('!windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Wires the deterministic Public-Docs-QS gate (`scripts/docs-attest.sh check`)
/// into `flutter test`, mirroring loam.dev's `readme_qa_test.dart`.
///
/// This gives a fast local + CI signal that README, CHANGELOG, the website
/// (DE+EN) and the platform/store SSoT (`platforms.ts`) stay consistent — the
/// same check enforced in the CI website job and the `.githooks/pre-push` hook.
///
/// Skipped on Windows: the gate is a POSIX shell + perl script and Windows CI
/// runners resolve `bash`/`perl` unreliably. The Ubuntu CI job and the pre-push
/// hook cover that platform.
void main() {
  test('public docs are structurally consistent (docs-attest check)', () {
    final repoRoot = _findRepoRoot();
    final script = p.join(repoRoot, 'scripts', 'docs-attest.sh');
    expect(
      File(script).existsSync(),
      isTrue,
      reason: 'scripts/docs-attest.sh must exist',
    );

    final result = Process.runSync('bash', [
      script,
      'check',
    ], workingDirectory: repoRoot);

    // The script prints its own ✗ lines for any violation; surface them.
    expect(
      result.exitCode,
      0,
      reason:
          'docs-attest check failed:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });
}

/// Walks up from the test file until it finds the repo root (the dir holding
/// `pubspec.yaml` next to `scripts/docs-attest.sh`).
String _findRepoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync() &&
        File(p.join(dir.path, 'scripts', 'docs-attest.sh')).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
