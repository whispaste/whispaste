import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// A hang guard for polling real IO, never a performance assertion.
///
/// Uses the root zone so widget pumps cannot advance the deadline. Slow pumps
/// and IO remain free to take as long as the test's timeout allows.
class TestDeadline {
  TestDeadline(Duration timeout) {
    _timer = Zone.root.createTimer(timeout, () => expired = true);
    addTearDown(_timer.cancel);
  }

  late final Timer _timer;
  bool expired = false;
}
