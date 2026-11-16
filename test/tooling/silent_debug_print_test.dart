import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/semantics_tree_recorder.dart';

/// #1491: every test runs with the silent debugPrint, the first one too, and
/// the binding's per-test check of the foundation debug variables holds.
void main() {
  for (final name in ['first', 'second']) {
    testWidgets('$name widget test keeps the silent debugPrint', (_) async {
      expect(identical(debugPrint, silentDebugPrint), isTrue);
    });
  }

  test('a plain test sees it too', () {
    expect(identical(debugPrint, silentDebugPrint), isTrue);
  });
}
