/// Golden coverage for [WpOverlaySizeSelector] — the visual card selector
/// that replaced the overlay-size text dropdown (Ticket 13).
///
/// Renders the selector once per [FloatingOverlaySize] value so the
/// selected-card chrome (accent border/fill + checkmark-free selected label)
/// is captured for all three cards, not just whichever one happens to be
/// active by default.
///
/// Determinism anchor: `Inter` is loaded via `loadAppFonts` before any pump,
/// same as the overlay parity goldens — otherwise the first golden in the
/// suite can render on the Ahem fallback font.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/overlay_size_selector.dart';

import '../../../fixtures/test_helpers.dart';

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  group('WpOverlaySizeSelector goldens', () {
    for (final size in FloatingOverlaySize.values) {
      final goldenName = 'overlay_size_selector_${size.value}';
      final testKey = ValueKey(goldenName);

      testWidgets('golden: $goldenName selected', (tester) async {
        await tester.pumpWidget(
          makeTestable(
            // Tightly captured, on the same dark surface the row sits on in
            // the real Settings page — no `Center`, which would size the
            // RepaintBoundary to the whole (bounded) Scaffold body instead
            // of to the row's own intrinsic size.
            RepaintBoundary(
              key: testKey,
              child: ColoredBox(
                color: WpColors.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: WpOverlaySizeSelector(value: size, onChanged: (_) {}),
                ),
              ),
            ),
            size: const Size(360, 120),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(
          find.byKey(testKey),
          matchesGoldenFile('goldens/$goldenName.png'),
        );
      });
    }
  });
}
