import 'package:flutter_test/flutter_test.dart';

import 'test_deadline.dart';

/// Drives a widget test until [done] holds, without a fixed real wait (#1491).
///
/// Real I/O (`dart:io` files, isolates, bundled assets) only progresses on the
/// real event loop, while the code's own continuations and timers run in the
/// fake zone of `testWidgets`. Each round gives the real loop one turn
/// (`Duration.zero`: a yield, not a sleep) and then pumps [step] of fake time,
/// so timeouts and animations advance on the controlled clock. It stops as
/// soon as [done] holds; the root-zone [TestDeadline] only turns a hang into a
/// failure naming [what].
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String what,
  Duration step = Duration.zero,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = TestDeadline(timeout);
  while (!done()) {
    if (deadline.expired) fail('timed out waiting for: $what');
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(step);
  }
}

/// [pumpUntil] for a condition that needs real async work itself (a database
/// read), evaluated inside `runAsync`.
Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() done, {
  required String what,
  Duration step = Duration.zero,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = TestDeadline(timeout);
  while (!(await tester.runAsync(done) ?? false)) {
    if (deadline.expired) fail('timed out waiting for: $what');
    await tester.pump(step);
  }
}
