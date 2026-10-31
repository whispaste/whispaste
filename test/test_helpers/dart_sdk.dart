import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a `dart` executable for tests that spawn a Dart process.
///
/// Under `flutter test`, [Platform.resolvedExecutable] is the `flutter_tester`
/// binary, and `dart` is not guaranteed to be on `PATH` (the lab guests pick
/// the Flutter SDK per run through a shim and have no `dart` on `PATH`). So the
/// SDK's own binary is located instead: first via `FLUTTER_ROOT`, then by
/// walking up from the running binary to the `bin/cache/dart-sdk` that sits
/// next to it in every Flutter checkout.
///
/// Throws a [StateError] if no SDK can be found, rather than falling back to a
/// bare `dart` that may not resolve.
String resolveDartExecutable() {
  final name = Platform.isWindows ? 'dart.exe' : 'dart';
  final resolved = Platform.resolvedExecutable;
  if (p.basenameWithoutExtension(resolved).toLowerCase() == 'dart') {
    return resolved;
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final candidate = p.join(
      flutterRoot,
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      name,
    );
    if (File(candidate).existsSync()) return candidate;
  }

  for (var dir = File(resolved).parent; ; dir = dir.parent) {
    final candidate = p.join(dir.path, 'cache', 'dart-sdk', 'bin', name);
    if (File(candidate).existsSync()) return candidate;
    if (dir.parent.path == dir.path) break;
  }

  throw StateError(
    'No Dart SDK found next to $resolved (FLUTTER_ROOT is '
    '${flutterRoot ?? 'unset'}).',
  );
}
