/// Unit tests for [migrateLegacyOnboardingStepIndex] — the pure translation
/// from a persisted resume position of an older flow version to the current
/// one.
///
/// Same testing shape as `onboarding_step_ids_test.dart`: pure function,
/// injected platform, no widget tree. Two source versions are migratable and
/// they need different tables:
///  - **v0** (the pre-redesign 7/8-step flow) is platform-dependent — macOS
///    Developer-ID had Auto-Paste at index 3, everywhere else index 3 was the
///    model step;
///  - **v1** (the six-step redesign) is platform-invariant as a *source*, but
///    its targets are not: the current flow is seven steps on macOS/Windows
///    and six on Linux.
library;

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';

int _migrateV0(
  int legacyIndex, {
  TargetPlatform platform = TargetPlatform.linux,
  bool autoPasteSupported = false,
}) => migrateLegacyOnboardingStepIndex(
  legacyIndex: legacyIndex,
  fromVersion: 0,
  platform: platform,
  autoPasteSupported: autoPasteSupported,
);

int _migrateV1(
  int storedIndex, {
  required TargetPlatform platform,
  bool autoPasteSupported = true,
}) => migrateLegacyOnboardingStepIndex(
  legacyIndex: storedIndex,
  fromVersion: 1,
  platform: platform,
  autoPasteSupported: autoPasteSupported,
);

void main() {
  group('onboardingIncludesAutoPasteStep', () {
    test('macOS and Windows include the Auto-Paste page, Linux does not', () {
      expect(
        onboardingIncludesAutoPasteStep(
          platform: TargetPlatform.macOS,
          autoPasteSupported: true,
        ),
        isTrue,
      );
      expect(
        onboardingIncludesAutoPasteStep(
          platform: TargetPlatform.windows,
          autoPasteSupported: true,
        ),
        isTrue,
      );
      expect(
        onboardingIncludesAutoPasteStep(
          platform: TargetPlatform.linux,
          autoPasteSupported: true,
        ),
        isFalse,
      );
    });

    test('the kill switch removes the page from every platform', () {
      for (final platform in TargetPlatform.values) {
        expect(
          onboardingIncludesAutoPasteStep(
            platform: platform,
            autoPasteSupported: false,
          ),
          isFalse,
          reason: '$platform',
        );
      }
    });
  });

  group('migrateLegacyOnboardingStepIndex', () {
    test('current flow version constant is 2 (fresh-install default is 0)', () {
      expect(kOnboardingFlowVersion, 2);
    });

    test('a fresh install (version 0, position 0) resolves to 0 — the '
        'highest-volume production path, pinned rather than left to luck', () {
      for (final platform in TargetPlatform.values) {
        for (final autoPaste in [true, false]) {
          expect(
            migrateLegacyOnboardingStepIndex(
              legacyIndex: 0,
              fromVersion: 0,
              platform: platform,
              autoPasteSupported: autoPaste,
            ),
            0,
            reason: 'platform=$platform autoPasteSupported=$autoPaste',
          );
        }
      }
    });

    // ── v1 (six-step redesign) → current ──────────────────────────────────

    group('from v1, on a platform that keeps the Auto-Paste page', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        group('$platform', () {
          int m(int i) => _migrateV1(i, platform: platform);

          test('welcome (0) → Welcome (0)', () => expect(m(0), 0));
          test('privacy (1) → Privacy (1)', () => expect(m(1), 1));
          test('model & hotkey (2) → Model (2), the first half of the page '
              'that split — never the half the user has not seen', () {
            expect(m(2), 2);
          });
          test('appearance (3) → Appearance (4), which moved back one slot '
              'when the hotkey page appeared before it', () {
            expect(m(3), 4);
          });
          test('autostart & auto-paste (4) → Auto-Paste (5)', () {
            expect(m(4), 5);
          });
          test('try & go (5) → last page (6)', () => expect(m(5), 6));
          test('beyond the six-step source sequence → 0', () {
            expect(m(6), 0);
            expect(m(11), 0);
          });
        });
      }
    });

    group('from v1, on Linux (no Auto-Paste page in the new sequence)', () {
      int m(int i) => _migrateV1(i, platform: TargetPlatform.linux);

      test('the first four positions map exactly as elsewhere', () {
        expect(m(0), 0);
        expect(m(1), 1);
        expect(m(2), 2);
        expect(m(3), 4);
      });

      test('autostart & auto-paste (4) → Appearance (4): the page it names '
          'no longer exists here, and its autostart toggle — the only part '
          'Linux ever rendered — now lives on the Appearance page', () {
        expect(m(4), 4);
      });

      test('try & go (5) → last page (5, not 6)', () => expect(m(5), 5));
    });

    test('the Auto-Paste kill switch collapses macOS/Windows onto the same '
        'targets as Linux', () {
      for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
        expect(
          _migrateV1(4, platform: platform, autoPasteSupported: false),
          4,
          reason: '$platform',
        );
        expect(
          _migrateV1(5, platform: platform, autoPasteSupported: false),
          5,
          reason: '$platform',
        );
      }
    });

    // ── v0 (pre-redesign 7/8-step flow) → current ─────────────────────────

    group(
      'from v0, macOS Developer-ID build (8 steps, autoPaste at index 3)',
      () {
        int m(int i) => _migrateV0(
          i,
          platform: TargetPlatform.macOS,
          autoPasteSupported: true,
        );

        test('welcome (0) → Welcome (0)', () => expect(m(0), 0));
        test('privacy (1) → Privacy (1)', () => expect(m(1), 1));
        test('microphone (2) → Welcome (0, mic merged)', () => expect(m(2), 0));
        test('autoPaste (3) → Auto-Paste (5)', () => expect(m(3), 5));
        test('model (4) → Model (2)', () => expect(m(4), 2));
        test(
          'trigger (5) → Hotkey (3) — the two are separate pages again, so '
          'this is one-to-one instead of the collapse the merged flow needed',
          () {
            expect(m(5), 3);
          },
        );
        test('testRecording (6) → last page (6)', () => expect(m(6), 6));
        test('ready (7) → last page (6)', () => expect(m(7), 6));
        test('no v0 step maps onto the Appearance page (4) — the theme choice '
            'used to sit on the Welcome page and has no v0 counterpart', () {
          for (var i = 0; i < 8; i++) {
            expect(m(i), isNot(4), reason: 'legacyIndex=$i');
          }
        });
      },
    );

    group('from v0, 7-step variants (macOS MAS, Windows, Linux)', () {
      const variants = <(TargetPlatform, bool)>[
        (TargetPlatform.macOS, false),
        (TargetPlatform.windows, true),
        (TargetPlatform.windows, false),
        (TargetPlatform.linux, true),
        (TargetPlatform.linux, false),
      ];

      test('index 3 is the model step → Model (2), NOT the Auto-Paste page — '
          'the macOS Dev-ID offset must not leak onto other variants', () {
        for (final (platform, autoPaste) in variants) {
          expect(
            _migrateV0(3, platform: platform, autoPasteSupported: autoPaste),
            2,
            reason: 'platform=$platform autoPasteSupported=$autoPaste',
          );
        }
      });

      test('full mapping per variant, including the now platform-dependent '
          'last-page index', () {
        for (final (platform, autoPaste) in variants) {
          final last =
              onboardingIncludesAutoPasteStep(
                platform: platform,
                autoPasteSupported: autoPaste,
              )
              ? 6
              : 5;
          final expected = [0, 1, 0, 2, 3, last, last];
          for (var i = 0; i < expected.length; i++) {
            expect(
              _migrateV0(i, platform: platform, autoPasteSupported: autoPaste),
              expected[i],
              reason:
                  'legacyIndex=$i platform=$platform '
                  'autoPasteSupported=$autoPaste',
            );
          }
        }
      });

      test(
        'index 7 is beyond the 7-step source sequence → falls back to 0',
        () {
          for (final (platform, autoPaste) in variants) {
            expect(
              _migrateV0(7, platform: platform, autoPasteSupported: autoPaste),
              0,
              reason: 'platform=$platform autoPasteSupported=$autoPaste',
            );
          }
        },
      );
    });

    // ── Bounds and defensive paths ────────────────────────────────────────

    group('out-of-range fallback', () {
      test('position beyond every source sequence → 0', () {
        for (final platform in TargetPlatform.values) {
          for (final autoPaste in [true, false]) {
            expect(
              _migrateV0(12, platform: platform, autoPasteSupported: autoPaste),
              0,
            );
            expect(
              _migrateV0(8, platform: platform, autoPasteSupported: autoPaste),
              0,
            );
          }
        }
      });

      test('negative position → 0, whatever the source version', () {
        expect(_migrateV0(-1), 0);
        expect(_migrateV1(-1, platform: TargetPlatform.macOS), 0);
        expect(
          _migrateV0(
            -5,
            platform: TargetPlatform.macOS,
            autoPasteSupported: true,
          ),
          0,
        );
      });
    });

    test('a position already at (or beyond) the current version is clamped, '
        'not re-translated — the caller guards on the version, this is the '
        'belt to that braces', () {
      expect(
        migrateLegacyOnboardingStepIndex(
          legacyIndex: 6,
          fromVersion: kOnboardingFlowVersion,
          platform: TargetPlatform.macOS,
          autoPasteSupported: true,
        ),
        6,
      );
      expect(
        migrateLegacyOnboardingStepIndex(
          legacyIndex: 6,
          fromVersion: kOnboardingFlowVersion,
          platform: TargetPlatform.linux,
          autoPasteSupported: true,
        ),
        5,
        reason: 'Linux has no sixth index to resume at',
      );
    });
  });
}
