/// Tests for the resume-position migration into flow version 5 (Onboarding
/// v6, ticket V01). Pure list checks, no widget tree.
///
/// Every stored position, whatever version wrote it, must land on the first
/// page that is still open for that user, and no position may skip a page
/// the user has not seen.
library;

import 'package:flutter/material.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/features/onboarding/onboarding_flow_migration.dart';
import 'package:whispaste/features/onboarding/onboarding_overlay.dart';

int _m(int index, int from, TargetPlatform platform, bool autoPaste) =>
    migrateLegacyOnboardingStepIndex(
      legacyIndex: index,
      fromVersion: from,
      platform: platform,
      autoPasteSupported: autoPaste,
    );

const _desktop = [
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
];

void main() {
  group('onboardingIncludesAutoPasteStep', () {
    test('every desktop platform includes the Auto-Paste permission', () {
      for (final p in _desktop) {
        expect(
          onboardingIncludesAutoPasteStep(
            platform: p,
            autoPasteSupported: true,
          ),
          isTrue,
          reason: '$p',
        );
      }
    });

    test('the kill switch removes it from every platform', () {
      for (final p in _desktop) {
        expect(
          onboardingIncludesAutoPasteStep(
            platform: p,
            autoPasteSupported: false,
          ),
          isFalse,
          reason: '$p',
        );
      }
    });
  });

  group('v5 indices match the widget sequence', () {
    test('kV5 constants are the order of buildOnboardingStepIds', () {
      final steps = buildOnboardingStepIds();
      expect(steps.indexOf(OnboardingStepId.welcome), kV5Welcome);
      expect(steps.indexOf(OnboardingStepId.about), kV5About);
      expect(steps.indexOf(OnboardingStepId.access), kV5Access);
      expect(steps.indexOf(OnboardingStepId.mic), kV5Mic);
      expect(steps.indexOf(OnboardingStepId.hotkey), kV5Hotkey);
      expect(steps.indexOf(OnboardingStepId.tryOut), kV5Try);
      expect(steps.indexOf(OnboardingStepId.privacy), kV5Privacy);
      expect(steps.length, kV5Privacy + 1);
    });
  });

  group('migrateLegacyOnboardingStepIndex', () {
    test('flow version is 5 (fresh-install default is 0)', () {
      expect(kOnboardingFlowVersion, 5);
    });

    test('a fresh install (version 0, position 0) resolves to Start', () {
      for (final p in _desktop) {
        expect(_m(0, 0, p, true), kV5Welcome, reason: '$p');
      }
    });

    test('a negative position resolves to Start', () {
      expect(_m(-1, 4, TargetPlatform.macOS, true), kV5Welcome);
    });

    test('a current-version position is kept, clamped to the sequence', () {
      expect(_m(kV5Hotkey, 5, TargetPlatform.macOS, true), kV5Hotkey);
      expect(_m(9, 5, TargetPlatform.macOS, true), kV5Privacy);
    });

    group('from v4 (eight positions, Speech and Appearance still in it)', () {
      const p = TargetPlatform.macOS;
      test('Start and Speech both resume on Start', () {
        expect(_m(0, 4, p, true), kV5Welcome);
        expect(_m(1, 4, p, true), kV5Welcome, reason: 'model moved away');
      });
      test('Hotkey keeps its page, Try keeps its page', () {
        expect(_m(2, 4, p, true), kV5Hotkey);
        expect(_m(4, 4, p, true), kV5Try);
      });
      test('Access (microphone then) and Auto-Paste resume on Access', () {
        expect(_m(3, 4, p, true), kV5Access);
        expect(_m(5, 4, p, true), kV5Access);
      });
      test('Appearance and Privacy resume on Privacy', () {
        expect(_m(6, 4, p, true), kV5Privacy);
        expect(_m(7, 4, p, true), kV5Privacy);
      });
      test('Done keeps the closing page', () {
        expect(_m(8, 4, p, true), kV5Privacy);
      });
      test('a position beyond the v4 sequence falls back to Start', () {
        expect(_m(9, 4, p, true), kV5Welcome);
      });
    });

    group('from v3 (seven steps, Done at 6)', () {
      test('the positions map through v4 to v5', () {
        const p = TargetPlatform.macOS;
        expect(_m(0, 3, p, true), kV5Welcome);
        expect(_m(1, 3, p, true), kV5Welcome, reason: 'speech');
        expect(_m(2, 3, p, true), kV5Hotkey, reason: 'hotkey');
        expect(_m(3, 3, p, true), kV5Access, reason: 'access');
        expect(_m(4, 3, p, true), kV5Try, reason: 'try');
        expect(_m(5, 3, p, true), kV5Access, reason: 'auto-paste');
        expect(_m(6, 3, p, true), kV5Privacy, reason: 'appearance');
        expect(_m(7, 3, p, true), kV5Welcome, reason: 'beyond the sequence');
      });
    });

    group('from v2, with Auto-Paste (macOS, Windows, Linux)', () {
      for (final p in _desktop) {
        test('$p: every v2 position lands on the first open page', () {
          // v2: 0 Welcome · 1 Privacy · 2 Model · 3 Hotkey · 4 Appearance ·
          // 5 Auto-Paste · 6 Try & Go
          expect(_m(0, 2, p, true), kV5Welcome);
          expect(_m(1, 2, p, true), kV5Privacy, reason: 'privacy');
          expect(_m(2, 2, p, true), kV5Welcome, reason: 'model');
          expect(_m(3, 2, p, true), kV5Hotkey, reason: 'hotkey');
          expect(_m(4, 2, p, true), kV5Privacy, reason: 'appearance');
          expect(_m(5, 2, p, true), kV5Access, reason: 'auto-paste');
          expect(_m(6, 2, p, true), kV5Try, reason: 'try');
          expect(_m(7, 2, p, true), kV5Welcome, reason: 'beyond');
        });
      }
    });

    test('from v2 under the kill switch, Try & Go is index 5', () {
      expect(_m(5, 2, TargetPlatform.macOS, false), kV5Try);
      expect(_m(4, 2, TargetPlatform.macOS, false), kV5Privacy);
      expect(_m(6, 2, TargetPlatform.macOS, false), kV5Welcome);
    });

    test('from v1 (six-step redesign), macOS', () {
      const p = TargetPlatform.macOS;
      expect(_m(0, 1, p, true), kV5Welcome);
      expect(_m(1, 1, p, true), kV5Privacy);
      expect(_m(2, 1, p, true), kV5Welcome, reason: 'model and hotkey');
      expect(_m(3, 1, p, true), kV5Privacy, reason: 'appearance');
      expect(_m(4, 1, p, true), kV5Access, reason: 'autostart and paste');
      expect(_m(5, 1, p, true), kV5Try);
    });

    test('from v1 under the kill switch, autostart page lands on Privacy', () {
      expect(_m(4, 1, TargetPlatform.linux, false), kV5Privacy);
    });

    test('from v0 on macOS, the Auto-Paste position resumes on Access', () {
      const p = TargetPlatform.macOS;
      expect(_m(0, 0, p, true), kV5Welcome);
      expect(_m(1, 0, p, true), kV5Privacy);
      expect(_m(2, 0, p, true), kV5Welcome, reason: 'microphone');
      expect(_m(3, 0, p, true), kV5Access, reason: 'auto-paste');
      expect(_m(4, 0, p, true), kV5Welcome, reason: 'model');
      expect(_m(5, 0, p, true), kV5Hotkey, reason: 'trigger');
      expect(_m(6, 0, p, true), kV5Try, reason: 'test recording');
      expect(_m(7, 0, p, true), kV5Try, reason: 'ready');
    });

    test('from v0 off macOS, there is no Auto-Paste position', () {
      const p = TargetPlatform.windows;
      expect(_m(3, 0, p, true), kV5Welcome, reason: 'model');
      expect(_m(4, 0, p, true), kV5Hotkey, reason: 'trigger');
      expect(_m(5, 0, p, true), kV5Try, reason: 'test recording');
      expect(_m(6, 0, p, true), kV5Try, reason: 'ready');
    });
  });
}
