/// UIA-FND-02 — one radius scale.
///
/// Maintainer decision (UI audit 2026-10): every control (buttons, input
/// fields, banners, error notices, keycaps, dock selectors) has an 8 px corner
/// radius. The values come from `design-tokens/primitives.tokens.json`
/// (`radius.control`) and `design-tokens/app.tokens.json` (`dock.control-radius`),
/// generated into `lib/core/theme/generated/wp_tokens.g.dart`.
///
/// This test pins the control radius and checks that the hand-written
/// `WpRadius` and the generated `WpRadiusTokens` never disagree on a shared step.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/theme/generated/wp_tokens.g.dart';
import 'package:whispaste/core/theme/tokens.dart';

void main() {
  test('UIA-FND-02: every control has an 8 px corner radius', () {
    expect(WpRadiusTokens.control, 8);
    expect(WpDockTokens.controlRadius, 8);
  });

  test('UIA-FND-02: WpRadius and WpRadiusTokens agree on shared steps', () {
    expect(WpRadiusTokens.sm, WpRadius.sm);
  });
}
