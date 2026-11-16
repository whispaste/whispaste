import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/paste/paste_policy.dart';
import 'package:whispaste/services/paste/paster.dart';

void main() {
  group('resolveAfterTranscriptionAction', () {
    group('when auto-paste is supported (Developer-ID / Windows / Linux)', () {
      for (final action in AfterTranscriptionAction.values) {
        test('keeps $action unchanged', () {
          expect(
            resolveAfterTranscriptionAction(action, autoPasteSupported: true),
            action,
          );
        });
      }
    });

    group('when auto-paste is unavailable (Mac App Store build)', () {
      test('downgrades paste to clipboard', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.paste,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('downgrades clipboardAndPaste to clipboard', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.clipboardAndPaste,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('leaves clipboard untouched', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.clipboard,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.clipboard,
        );
      });

      test('leaves nothing untouched', () {
        expect(
          resolveAfterTranscriptionAction(
            AfterTranscriptionAction.nothing,
            autoPasteSupported: false,
          ),
          AfterTranscriptionAction.nothing,
        );
      });
    });
  });

  group('AfterTranscriptionAction.fromValue back-compat', () {
    // 'type'/'clipboard_and_type' existed briefly as separate user-facing
    // actions (direct Unicode typing) before being folded back into
    // paste/clipboardAndPaste as an internal mechanism choice — see
    // DesktopPaster.paste. Anyone who saved a setting during that window
    // must still resolve to the equivalent paste-flavored action.
    test('"type" maps to paste', () {
      expect(
        AfterTranscriptionAction.fromValue('type'),
        AfterTranscriptionAction.paste,
      );
    });

    test('"clipboard_and_type" maps to clipboardAndPaste', () {
      expect(
        AfterTranscriptionAction.fromValue('clipboard_and_type'),
        AfterTranscriptionAction.clipboardAndPaste,
      );
    });
  });

  group('afterTranscriptionActionPastes', () {
    // The shared "does this user even use Auto-Paste" predicate. Every
    // proactive Auto-Paste surface (startup gate, restart watch, TCC-reset
    // notice) keys off it — a clipboard-only user (the factory default!)
    // must never trigger any Auto-Paste permission UI.
    test('paste-flavored actions paste', () {
      expect(
        afterTranscriptionActionPastes(AfterTranscriptionAction.paste),
        isTrue,
      );
      expect(
        afterTranscriptionActionPastes(
          AfterTranscriptionAction.clipboardAndPaste,
        ),
        isTrue,
      );
    });

    test('clipboard-only and nothing never paste', () {
      expect(
        afterTranscriptionActionPastes(AfterTranscriptionAction.clipboard),
        isFalse,
      );
      expect(
        afterTranscriptionActionPastes(AfterTranscriptionAction.nothing),
        isFalse,
      );
    });

    test('kill-switch build downgrades paste actions to not-pasting', () {
      expect(
        afterTranscriptionActionPastes(
          AfterTranscriptionAction.paste,
          autoPasteSupported: false,
        ),
        isFalse,
      );
    });
  });

  group('shouldShowAutoPasteRestartSurface', () {
    // Regression for the live-reported bug: the app-level restart watch
    // showed Auto-Paste modals to a clipboard-only user because it only
    // guarded on platform + onboarding, never on "does this user paste".
    test('requires ALL of needsRestart, onboarding done, and pasting', () {
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: true,
          onboardingCompleted: true,
          userPastes: true,
        ),
        isTrue,
      );
    });

    test('clipboard-only user never sees the restart surface', () {
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: true,
          onboardingCompleted: true,
          userPastes: false,
        ),
        isFalse,
      );
    });

    test('suppressed during onboarding and without restart need', () {
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: true,
          onboardingCompleted: false,
          userPastes: true,
        ),
        isFalse,
      );
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: false,
          onboardingCompleted: true,
          userPastes: true,
        ),
        isFalse,
      );
    });

    test('suppressed while the introduction is reopened from Settings, even '
        'though onboarding is long completed', () {
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: true,
          onboardingCompleted: true,
          onboardingManuallyOpen: true,
          userPastes: true,
        ),
        isFalse,
        reason:
            'The flow carries its own inline restart banner on the '
            'Auto-Paste step — a native modal on top of it is a second, '
            'competing voice.',
      );
    });

    test('suppressed while an onboarding revision run is in progress, even '
        'though onboarding is long completed', () {
      expect(
        shouldShowAutoPasteRestartSurface(
          needsRestart: true,
          onboardingCompleted: true,
          onboardingRevisionRunning: true,
          userPastes: true,
        ),
        isFalse,
        reason:
            'A revision run carries the same inline restart banner as a '
            'first run — a native modal on top of it is a second, '
            'competing voice.',
      );
    });
  });

  group('shouldEnableAutoPasteAfterGrant', () {
    bool decide({
      bool grantRequestedHere = true,
      PasteCapabilityStatus? previous = PasteCapabilityStatus.permissionMissing,
      PasteCapabilityStatus? next = PasteCapabilityStatus.ready,
      AfterTranscriptionAction current = AfterTranscriptionAction.clipboard,
      bool freshOnboarding = true,
      bool alreadyGrantedAtStart = false,
      bool autoPasteSupported = true,
    }) => shouldEnableAutoPasteAfterGrant(
      grantRequestedHere: grantRequestedHere,
      previous: previous,
      next: next,
      current: current,
      freshOnboarding: freshOnboarding,
      alreadyGrantedAtStart: alreadyGrantedAtStart,
      autoPasteSupported: autoPasteSupported,
    );

    test('a requested grant that turns ready switches it on', () {
      expect(decide(), isTrue);
      expect(decide(current: AfterTranscriptionAction.nothing), isTrue);
      expect(decide(previous: null), isTrue);
    });

    test('never without a grant asked for in the step', () {
      expect(decide(grantRequestedHere: false), isFalse);
    });

    test('only the change to ready counts', () {
      expect(decide(previous: PasteCapabilityStatus.ready), isFalse);
      expect(decide(next: PasteCapabilityStatus.permissionMissing), isFalse);
      expect(decide(next: null), isFalse);
    });

    test('a user who already pastes keeps the choice', () {
      expect(decide(current: AfterTranscriptionAction.paste), isFalse);
      expect(
        decide(current: AfterTranscriptionAction.clipboardAndPaste),
        isFalse,
      );
    });

    test('never in a build with Auto-Paste switched off', () {
      expect(decide(autoPasteSupported: false), isFalse);
    });

    test('a grant already there at the first probe counts on a fresh run', () {
      expect(
        decide(
          grantRequestedHere: false,
          previous: null,
          alreadyGrantedAtStart: true,
        ),
        isTrue,
      );
    });

    test('no first-probe grant and no request: nothing changes', () {
      expect(decide(grantRequestedHere: false, previous: null), isFalse);
    });

    test('an already-granted permission never changes an existing install', () {
      expect(
        decide(
          freshOnboarding: false,
          grantRequestedHere: false,
          previous: null,
          alreadyGrantedAtStart: true,
        ),
        isFalse,
      );
    });

    test('a revision run or a review reopened from Settings never changes '
        'the stored choice of an existing install', () {
      expect(decide(freshOnboarding: false), isFalse);
      expect(
        decide(
          freshOnboarding: false,
          current: AfterTranscriptionAction.nothing,
        ),
        isFalse,
      );
    });
  });

  group('shouldOfferPasteSetupHint', () {
    bool decide({
      AfterTranscriptionAction action = AfterTranscriptionAction.clipboard,
      bool onboardingCompleted = true,
      bool alreadyShown = false,
      bool offHintDismissed = false,
      bool autoPasteSupported = true,
    }) => shouldOfferPasteSetupHint(
      action: action,
      onboardingCompleted: onboardingCompleted,
      alreadyShown: alreadyShown,
      offHintDismissed: offHintDismissed,
      autoPasteSupported: autoPasteSupported,
    );

    test('clipboard-only after the onboarding, first time: due', () {
      expect(decide(), isTrue);
    });

    test('once per installation', () {
      expect(decide(alreadyShown: true), isFalse);
    });

    test('not after the status bar chip was closed', () {
      expect(decide(offHintDismissed: true), isFalse);
    });

    test('not during the onboarding', () {
      expect(decide(onboardingCompleted: false), isFalse);
    });

    test('only for clipboard-only', () {
      for (final action in [
        AfterTranscriptionAction.paste,
        AfterTranscriptionAction.clipboardAndPaste,
        AfterTranscriptionAction.nothing,
      ]) {
        expect(decide(action: action), isFalse, reason: '$action');
      }
    });

    test('not where Auto-Paste is switched off', () {
      expect(decide(autoPasteSupported: false), isFalse);
    });
  });

  group('shouldPreselectDirectPaste (#431)', () {
    bool decide({
      PasteCapabilityStatus? status = PasteCapabilityStatus.ready,
      AfterTranscriptionAction current = AfterTranscriptionAction.clipboard,
      bool freshOnboarding = true,
      bool declined = false,
      bool masBuild = true,
      bool autoPasteSupported = true,
    }) => shouldPreselectDirectPaste(
      status: status,
      current: current,
      freshOnboarding: freshOnboarding,
      declined: declined,
      masBuild: masBuild,
      autoPasteSupported: autoPasteSupported,
    );

    test('a grant on a fresh Mac App Store onboarding preselects it', () {
      expect(decide(), isTrue);
    });

    test('a missing grant stays on the clipboard', () {
      expect(decide(status: PasteCapabilityStatus.permissionMissing), isFalse);
      expect(decide(status: null), isFalse);
    });

    test('a deliberately chosen value is never overridden', () {
      expect(decide(current: AfterTranscriptionAction.nothing), isFalse);
      expect(
        decide(current: AfterTranscriptionAction.clipboardAndPaste),
        isFalse,
      );
    });

    test('going on without the permission counts as a no', () {
      expect(decide(declined: true), isFalse);
    });

    test('only a first run sets the choice', () {
      expect(decide(freshOnboarding: false), isFalse);
    });

    test('every other build is unchanged', () {
      expect(decide(masBuild: false), isFalse);
      expect(decide(autoPasteSupported: false), isFalse);
    });
  });
}
