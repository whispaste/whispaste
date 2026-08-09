/// Unit tests for [shouldShowTccResetNotice] and
/// [maybeMarkTccResetNoticeVersion].
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/paste/tcc_reset_notice.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Pure function — shouldShowTccResetNotice
  // ──────────────────────────────────────────────────────────────────────────

  group('shouldShowTccResetNotice — pure decision function', () {
    test('fires on a real version bump with missing permission on macOS', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.51',
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
        ),
        isTrue,
      );
    });

    test('fresh install (no prior version recorded) never fires', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: null,
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
        ),
        isFalse,
      );
    });

    test('same version as last seen never fires (already decided)', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.53',
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
        ),
        isFalse,
      );
    });

    test('mid-onboarding users never see it (onboarding step handles it)', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.51',
          currentVersion: '1.2.53',
          onboardingCompleted: false,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
        ),
        isFalse,
      );
    });

    test('non-macOS never fires', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.51',
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: false,
          capabilityStatus: PasteCapabilityStatus.permissionMissing,
        ),
        isFalse,
      );
    });

    test('capability ready (permission intact) never fires', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.51',
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.ready,
        ),
        isFalse,
      );
    });

    test('null capability status (probe never resolved) never fires', () {
      expect(
        shouldShowTccResetNotice(
          lastSeenVersion: '1.2.51',
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: null,
        ),
        isFalse,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Version gate — maybeMarkTccResetNoticeVersion
  // ──────────────────────────────────────────────────────────────────────────

  group('maybeMarkTccResetNoticeVersion — version gate', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('first-ever launch records the version but never shows', () async {
      final result = await maybeMarkTccResetNoticeVersion(
        currentVersion: '1.2.53',
        onboardingCompleted: true,
        isMacOS: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
      );
      expect(result, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('tcc_reset_notice_last_seen_version'), '1.2.53');
    });

    test('a genuine version bump with missing permission shows once', () async {
      SharedPreferences.setMockInitialValues({
        'tcc_reset_notice_last_seen_version': '1.2.51',
      });

      final first = await maybeMarkTccResetNoticeVersion(
        currentVersion: '1.2.53',
        onboardingCompleted: true,
        isMacOS: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
      );
      expect(first, isTrue);

      // A second launch on the SAME version must not fire again — the
      // question was already decided for 1.2.53 above.
      final second = await maybeMarkTccResetNoticeVersion(
        currentVersion: '1.2.53',
        onboardingCompleted: true,
        isMacOS: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
      );
      expect(second, isFalse);
    });

    test(
      'version bump with intact permission advances the gate silently',
      () async {
        SharedPreferences.setMockInitialValues({
          'tcc_reset_notice_last_seen_version': '1.2.51',
        });

        final result = await maybeMarkTccResetNoticeVersion(
          currentVersion: '1.2.53',
          onboardingCompleted: true,
          isMacOS: true,
          capabilityStatus: PasteCapabilityStatus.ready,
        );
        expect(result, isFalse);

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('tcc_reset_notice_last_seen_version'), '1.2.53');
      },
    );

    test('suppressed while the introduction is reopened from Settings, even '
        'though onboarding is long completed', () async {
      SharedPreferences.setMockInitialValues({
        'tcc_reset_notice_last_seen_version': '1.2.51',
      });

      final result = await maybeMarkTccResetNoticeVersion(
        currentVersion: '1.2.53',
        onboardingCompleted: true,
        onboardingManuallyOpen: true,
        isMacOS: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
      );
      expect(
        result,
        isFalse,
        reason:
            'Whoever is looking at the flow already has its dedicated '
            'Auto-Paste step in front of them.',
      );
    });

    test('suppressed while an onboarding revision run is in progress, even '
        'though onboarding is long completed', () async {
      SharedPreferences.setMockInitialValues({
        'tcc_reset_notice_last_seen_version': '1.2.51',
      });

      final result = await maybeMarkTccResetNoticeVersion(
        currentVersion: '1.2.53',
        onboardingCompleted: true,
        onboardingRevisionRunning: true,
        isMacOS: true,
        capabilityStatus: PasteCapabilityStatus.permissionMissing,
      );
      expect(
        result,
        isFalse,
        reason:
            'A revision run has its own dedicated Auto-Paste step in '
            'front of the user too.',
      );
    });
  });
}
