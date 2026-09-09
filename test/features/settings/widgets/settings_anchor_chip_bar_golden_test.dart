/// Golden coverage for [SettingsAnchorChipBar] (Ticket 16 — the anchor-/
/// jump-chip bar variant Ticket 15 chose over categorized sub-pages).
///
/// Two captures:
///   - wide: every chip fits on one line, the common desktop-window case.
///   - narrow: the app's own north star requires graceful degradation at
///     small window sizes even though this is a desktop app — the bar wraps
///     onto multiple lines rather than overflowing or clipping (Ticket 16's
///     "works at small window/screen size" AC).
///
/// Determinism anchor: `Inter` is loaded via `loadAppFonts` before any pump,
/// same as the overlay-size-selector goldens next to this file — otherwise
/// the first golden in the suite can render on the Ahem fallback font.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/settings_anchor_chip_bar.dart';

import '../../../fixtures/test_helpers.dart';

const _sectionKeys = <String>[
  'interface',
  'stt',
  'smartMode',
  'audio',
  'hotkey',
  'history',
  'privacy',
];

void main() {
  setUpAll(() => loadAppFonts(onlyLoadTheseFonts: {'Inter'}));

  group('SettingsAnchorChipBar goldens', () {
    testWidgets('golden: settings_anchor_chip_bar_wide — one line', (
      tester,
    ) async {
      const testKey = ValueKey('settings_anchor_chip_bar_wide');
      await tester.pumpWidget(
        makeTestable(
          const RepaintBoundary(
            key: testKey,
            child: ColoredBox(
              color: WpColors.surface,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SettingsAnchorChipBar(
                  sectionKeys: _sectionKeys,
                  locale: 'en',
                ),
              ),
            ),
          ),
          size: const Size(900, 100),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(testKey),
        matchesGoldenFile('goldens/settings_anchor_chip_bar_wide.png'),
      );
    });

    testWidgets(
      'golden: settings_anchor_chip_bar_narrow — wraps onto multiple lines',
      (tester) async {
        const testKey = ValueKey('settings_anchor_chip_bar_narrow');
        await tester.pumpWidget(
          makeTestable(
            const RepaintBoundary(
              key: testKey,
              child: ColoredBox(
                color: WpColors.surface,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  // `makeTestable` hands its child a loose (unconstrained)
                  // width regardless of the outer `size:` passed below — it
                  // only fixes the surrounding window/MediaQuery size, not
                  // the width available to a bare child placed in
                  // `Scaffold(body: child)`. A `SizedBox` here reproduces
                  // the width a narrow real window actually gives this bar
                  // once it sits inside WpPageShell's constrained header, so
                  // this golden genuinely exercises wrapping instead of
                  // rendering identically to the wide capture.
                  child: SizedBox(
                    width: 288,
                    child: SettingsAnchorChipBar(
                      sectionKeys: _sectionKeys,
                      locale: 'en',
                    ),
                  ),
                ),
              ),
            ),
            // Well below any window WhisPaste supports — exercises the same
            // "wraps rather than overflows" behavior the ticket asks for at
            // small window/screen sizes.
            size: const Size(320, 220),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'a narrow window must never overflow the chip bar',
        );

        await expectLater(
          find.byKey(testKey),
          matchesGoldenFile('goldens/settings_anchor_chip_bar_narrow.png'),
        );
      },
    );
  });
}
