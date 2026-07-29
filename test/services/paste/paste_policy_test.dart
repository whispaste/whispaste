import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/paste/paste_policy.dart';

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
  });
}
