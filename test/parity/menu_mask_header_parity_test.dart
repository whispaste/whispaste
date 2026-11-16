import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The right Win/Super start-menu mask is compiled twice: the Windows runner
/// and the Linux runner each carry their own copy of `menu_mask.h`, and both
/// copies say "keep them identical". Each runner builds its own copy, so a
/// divergence would only show up on one platform. PAR-045.
void main() {
  test('windows/runner and linux/runner carry byte-identical menu_mask.h', () {
    final windows = File('windows/runner/menu_mask.h').readAsBytesSync();
    final linux = File('linux/runner/menu_mask.h').readAsBytesSync();
    expect(
      linux,
      equals(windows),
      reason:
          'linux/runner/menu_mask.h and windows/runner/menu_mask.h must stay '
          'byte-identical (PAR-045). Copy the changed file over the other one.',
    );
  });
}
