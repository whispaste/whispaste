import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures/tolerant_golden_comparator.dart';

/// Runs before every test file under test/. flutter_tools has already set a
/// [LocalFileComparator] for the file at this point; swap in the tolerant
/// one so plain `matchesGoldenFile` goldens pass on both the maintainer's
/// Mac and the GitHub-hosted macOS runner (see kGoldenPixelTolerance).
/// golden_screenshot tests install their own comparator per test.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = goldenFileComparator;
  if (previous is LocalFileComparator) {
    goldenFileComparator = TolerantGoldenComparator(
      previous.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
