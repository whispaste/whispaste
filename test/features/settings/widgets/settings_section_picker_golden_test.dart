/// Golden coverage for [SettingsSectionPicker] (concept proposal 5, which
/// replaced the Ticket 16 anchor-chip wall).
///
/// Two captures:
///   - wide: the 288 px trigger used in a wide content area.
///   - narrow: the 232 px trigger used at 800 px windows, with a long
///     section title open-able without clipping its check column.
///
/// Determinism anchor: `Inter` is loaded via `loadAppFonts` before any pump,
/// same as the overlay-size-selector goldens next to this file.
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_screenshot/golden_screenshot.dart';

import 'package:whispaste/core/theme/colors.dart';
import 'package:whispaste/features/settings/widgets/settings_section_picker.dart';

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

  group('SettingsSectionPicker goldens', () {
    testWidgets('golden: settings_section_picker_wide — 288 px trigger', (
      tester,
    ) async {
      const testKey = ValueKey('settings_section_picker_wide');
      await tester.pumpWidget(
        makeTestable(
          const RepaintBoundary(
            key: testKey,
            child: ColoredBox(
              color: WpColors.surface,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 288,
                  child: SettingsSectionPicker(
                    sectionKeys: _sectionKeys,
                    locale: 'en',
                    activeSectionKey: 'hotkey',
                  ),
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
        matchesGoldenFile('goldens/settings_section_picker_wide.png'),
      );
    });

    testWidgets('golden: settings_section_picker_narrow — 232 px trigger', (
      tester,
    ) async {
      const testKey = ValueKey('settings_section_picker_narrow');
      await tester.pumpWidget(
        makeTestable(
          const RepaintBoundary(
            key: testKey,
            child: ColoredBox(
              color: WpColors.surface,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 232,
                  child: SettingsSectionPicker(
                    sectionKeys: _sectionKeys,
                    locale: 'en',
                    activeSectionKey: 'interface',
                  ),
                ),
              ),
            ),
          ),
          size: const Size(320, 220),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'a narrow window must never overflow the section picker',
      );

      await expectLater(
        find.byKey(testKey),
        matchesGoldenFile('goldens/settings_section_picker_narrow.png'),
      );
    });
  });
}
