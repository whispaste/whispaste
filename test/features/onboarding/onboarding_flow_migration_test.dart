/// Unit tests for [migrateLegacyOnboardingStepIndex] — the pure translation
/// from a persisted legacy (7/8-step) resume position to the six-step flow.
///
/// Same testing shape as `onboarding_step_ids_test.dart`: pure function,
/// injected platform, no widget tree. The legacy index is platform-dependent
/// (macOS Developer-ID had Auto-Paste at index 3; everywhere else index 3 was
/// the model step), so every case is asserted per platform/variant.
library;

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';

int _migrate(
  int legacyIndex, {
  TargetPlatform platform = TargetPlatform.linux,
  bool autoPasteSupported = false,
}) => migrateLegacyOnboardingStepIndex(
  legacyIndex: legacyIndex,
  platform: platform,
  autoPasteSupported: autoPasteSupported,
);

void main() {
  group('migrateLegacyOnboardingStepIndex', () {
    test('current flow version constant is 1 (legacy default is 0)', () {
      expect(kOnboardingFlowVersion, 1);
    });

    group(
      'macOS Developer-ID build (8 legacy steps, autoPaste at index 3)',
      () {
        int m(int i) => _migrate(
          i,
          platform: TargetPlatform.macOS,
          autoPasteSupported: true,
        );

        test('welcome (0) → Welcome page (0)', () => expect(m(0), 0));
        test('privacy (1) → Privacy page (1)', () => expect(m(1), 1));
        test('microphone (2) → Welcome page (0, mic merged)', () {
          expect(m(2), 0);
        });
        test('autoPaste (3) → Autostart & Auto-Paste page (4)', () {
          expect(m(3), 4);
        });
        test('model (4) → Model & Hotkey page (2)', () => expect(m(4), 2));
        test('trigger (5) → Model & Hotkey page (2)', () => expect(m(5), 2));
        test('testRecording (6) → Try & Go page (5)', () => expect(m(6), 5));
        test('ready (7) → Try & Go page (5)', () => expect(m(7), 5));
        test('no legacy step maps onto the Appearance page (3) — it has no '
            'legacy counterpart; the theme choice used to sit on Welcome', () {
          for (var i = 0; i < 8; i++) {
            expect(m(i), isNot(3), reason: 'legacyIndex=$i');
          }
        });
      },
    );

    group('7-step variants (macOS MAS, Windows, Linux — no autoPaste)', () {
      const variants = <(TargetPlatform, bool)>[
        (TargetPlatform.macOS, false),
        (TargetPlatform.windows, true),
        (TargetPlatform.windows, false),
        (TargetPlatform.linux, true),
        (TargetPlatform.linux, false),
      ];

      test('index 3 is the model step → Model & Hotkey page (2), '
          'NOT the Auto-Paste page — the macOS Dev-ID offset must not leak '
          'onto other variants', () {
        for (final (platform, autoPaste) in variants) {
          expect(
            _migrate(3, platform: platform, autoPasteSupported: autoPaste),
            2,
            reason: 'platform=$platform autoPasteSupported=$autoPaste',
          );
        }
      });

      test('full mapping: 0→0, 1→1, 2→0, 3→2, 4→2, 5→5, 6→5', () {
        const expected = [0, 1, 0, 2, 2, 5, 5];
        for (final (platform, autoPaste) in variants) {
          for (var i = 0; i < expected.length; i++) {
            expect(
              _migrate(i, platform: platform, autoPasteSupported: autoPaste),
              expected[i],
              reason:
                  'legacyIndex=$i platform=$platform '
                  'autoPasteSupported=$autoPaste',
            );
          }
        }
      });

      test(
        'index 7 is beyond the 7-step legacy sequence → falls back to 0',
        () {
          for (final (platform, autoPaste) in variants) {
            expect(
              _migrate(7, platform: platform, autoPasteSupported: autoPaste),
              0,
              reason: 'platform=$platform autoPasteSupported=$autoPaste',
            );
          }
        },
      );
    });

    group('out-of-range fallback', () {
      test('position beyond the new length (6) and beyond every legacy '
          'sequence → 0', () {
        for (final platform in TargetPlatform.values) {
          for (final autoPaste in [true, false]) {
            expect(
              _migrate(12, platform: platform, autoPasteSupported: autoPaste),
              0,
            );
            expect(
              _migrate(8, platform: platform, autoPasteSupported: autoPaste),
              0,
            );
          }
        }
      });

      test('negative position → 0', () {
        expect(_migrate(-1), 0);
        expect(
          _migrate(
            -5,
            platform: TargetPlatform.macOS,
            autoPasteSupported: true,
          ),
          0,
        );
      });
    });
  });
}
