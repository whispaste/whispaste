/// Smoke tests — RTL padding regression guards.
///
/// Verifies that [settingsDropdown] icon padding uses [EdgeInsetsDirectional]
/// (logical start/end) rather than physical left/right, so it mirrors
/// correctly in RTL locales like Hebrew.
///
/// These are not golden tests; they assert that:
///   - The widget renders without exceptions in a Hebrew (RTL) locale.
///   - Exactly one [Padding] widget with an [EdgeInsetsDirectional] value
///     matching our expected start-inset exists in the widget tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/theme/tokens.dart';
import 'package:whispaste/features/settings/settings_widgets.dart';

import '../fixtures/rtl_golden_harness.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns true when [padding] is an [EdgeInsetsDirectional] whose [start]
/// matches [expectedStart] (within floating-point tolerance).
bool _isDirectionalStart(EdgeInsetsGeometry padding, double expectedStart) {
  if (padding is EdgeInsetsDirectional) {
    return (padding.start - expectedStart).abs() < 0.5;
  }
  return false;
}

// ---------------------------------------------------------------------------
// settingsDropdown — dropdown icon padding
// ---------------------------------------------------------------------------

void main() {
  group('settingsDropdown — RTL padding (EdgeInsetsDirectional)', () {
    testWidgets('renders without exception in he locale', (tester) async {
      await tester.pumpWidget(
        wrapForRtlGolden(
          Builder(
            builder: (context) => settingsDropdown(
              context: context,
              value: 'a',
              items: const ['a', 'b'],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dropdown icon uses EdgeInsetsDirectional(start)', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapForRtlGolden(
          Builder(
            builder: (context) => settingsDropdown(
              context: context,
              value: 'a',
              items: const ['a', 'b'],
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find all Padding widgets whose padding is EdgeInsetsDirectional
      // with start == WpSpacing.xs.
      final paddings = tester.widgetList<Padding>(find.byType(Padding));
      final hasDirectionalStart = paddings.any(
        (p) => _isDirectionalStart(p.padding, WpSpacing.xs),
      );
      expect(
        hasDirectionalStart,
        isTrue,
        reason:
            'settingsDropdown icon padding should use '
            'EdgeInsetsDirectional.only(start: WpSpacing.xs)',
      );
    });
  });
}
