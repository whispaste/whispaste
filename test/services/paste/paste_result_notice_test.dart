import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_labels.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/paste/paste_failure_notifier.dart';
import 'package:whispaste/services/paste/paste_result_notice.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/sound_feedback_service.dart';
import 'package:whispaste/services/system_attention_service.dart';
import 'package:whispaste/services/tray_service.dart';

import '../../test_helpers/paste_notice_fakes.dart';

late L10n en;

PasteResultNotice? _notice(
  PasteOutcome outcome, {
  TargetPlatform platform = TargetPlatform.macOS,
  bool uinputDeviceMissing = false,
  bool restartNeeded = false,
  bool resetEntryFirst = false,
  bool linuxConsentNotice = false,
}) => pasteResultNotice(
  outcome: outcome,
  l10n: en,
  platform: platform,
  uinputDeviceMissing: uinputDeviceMissing,
  restartNeeded: restartNeeded,
  resetEntryFirst: resetEntryFirst,
  linuxConsentNotice: linuxConsentNotice,
);

void main() {
  setUpAll(() async {
    en = await L10n.delegate.load(const Locale('en'));
  });

  group('pasteResultNotice (decision table)', () {
    test('a landed paste needs no notice', () {
      expect(_notice(PasteOutcome.success), isNull);
    });

    test('a blocked app is a user rule, not a failure', () {
      expect(_notice(PasteOutcome.blocked), isNull);
    });

    test('an unconfirmed paste without a receipt bridge is no warning on '
        'Linux', () {
      expect(
        _notice(
          PasteOutcome.unconfirmedNoBridge,
          platform: TargetPlatform.linux,
        ),
        isNull,
      );
    });

    test('an unconfirmed paste without a receipt bridge is no warning on '
        'macOS either', () {
      expect(_notice(PasteOutcome.unconfirmedNoBridge), isNull);
    });

    test('a refused receipt write on macOS/Windows is a calm info notice, not '
        'a warning', () {
      final notice = _notice(PasteOutcome.unconfirmedReceiptRefused);

      expect(notice, isNotNull);
      expect(notice!.kind, AttentionKind.pasteReceiptRefused);
      expect(notice.title, en.pasteNotificationReceiptRefusedTitle);
      expect(notice.body, en.pasteReceiptRefusedText);
      expect(notice.trayLabel, isNull);
      expect(notice.action, isNull);
      expect(notice.informational, isTrue);
    });

    test('a target change stays an in-app toast, no OS notice', () {
      expect(_notice(PasteOutcome.targetChanged), isNull);
    });

    test(
      'an unconfirmed paste warns and says the text is on the clipboard',
      () {
        final notice = _notice(
          PasteOutcome.unconfirmed,
          platform: TargetPlatform.linux,
        )!;

        expect(notice.kind, AttentionKind.pasteFailedUnknown);
        expect(
          notice.body,
          en.pasteFailureUnconfirmed(
            pasteShortcutLabel(l10n: en, isMacOS: false),
          ),
        );
        expect(notice.body.toLowerCase(), contains('clipboard'));
        expect(notice.trayLabel, isNull, reason: 'the text is safe, no badge');
      },
    );

    test('a missing macOS permission warns with the clipboard hint and opens '
        'the recovery', () {
      final notice = _notice(PasteOutcome.permissionMissing)!;

      expect(notice.kind, AttentionKind.pasteBlockedPermission);
      expect(notice.body, contains(en.pasteNotificationClipboardHint));
      expect(notice.trayMenuItemKey, kTrayPastePermissionActionNeededKey);
      expect(notice.action, PasteNoticeAction.permissionRecovery);
    });

    test('a stale macOS grant asks for a restart with the clipboard hint', () {
      final notice = _notice(
        PasteOutcome.permissionMissing,
        restartNeeded: true,
      )!;

      expect(notice.title, en.pasteNotificationRestartNeededTitle);
      expect(notice.body, contains(en.pasteNotificationClipboardHint));
    });

    test('a missing Linux uinput device names no udev rule', () {
      final notice = _notice(
        PasteOutcome.permissionMissing,
        platform: TargetPlatform.linux,
        uinputDeviceMissing: true,
      )!;

      expect(
        notice.body,
        en.pasteNotificationLinuxNoDeviceBody(
          pasteShortcutLabel(l10n: en, isMacOS: false),
        ),
      );
      expect(notice.action, PasteNoticeAction.openAutoPasteSettings);
    });

    test('a Linux consent notice wins over the plain uinput text', () {
      final notice = _notice(
        PasteOutcome.permissionMissing,
        platform: TargetPlatform.linux,
        linuxConsentNotice: true,
      )!;

      expect(
        notice.body,
        en.linuxUinputConsentNotice(
          pasteShortcutLabel(l10n: en, isMacOS: false),
        ),
      );
    });

    test('an elevated target is a Windows-only admin notice', () {
      final notice = _notice(
        PasteOutcome.elevationBlocked,
        platform: TargetPlatform.windows,
      )!;

      expect(notice.kind, AttentionKind.pasteBlockedElevation);
      expect(notice.trayLabel, en.pasteNotificationElevationBlockedTray);
    });

    test('no target window gets its own notice', () {
      final notice = _notice(PasteOutcome.noTarget)!;

      expect(notice.kind, AttentionKind.pasteBlockedNoTarget);
    });

    test('a failed native paste reports the unknown failure with a badge', () {
      final notice = _notice(PasteOutcome.failed)!;

      expect(notice.kind, AttentionKind.pasteFailedUnknown);
      expect(notice.trayLabel, en.pasteNotificationFailedTray);
    });

    test('a missing native paste channel reports like a failed paste', () {
      final notice = _notice(PasteOutcome.platformUnavailable)!;

      expect(notice.kind, AttentionKind.pasteFailedUnknown);
    });
  });

  group('PasteResultReporter (shared by every paste path)', () {
    late ProviderContainer container;
    late RecordingSystemAttention attention;
    late FakeNoticeTray tray;
    late FakeNoticeSound sound;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          systemAttentionServiceProvider.overrideWith((ref) {
            attention = RecordingSystemAttention(ref);
            return attention;
          }),
          trayServiceProvider.overrideWith(() {
            tray = FakeNoticeTray();
            return tray;
          }),
          soundFeedbackProvider.overrideWith(() {
            sound = FakeNoticeSound();
            return sound;
          }),
        ],
      );
      addTearDown(container.dispose);
      // Instantiate the services the reporter reaches for.
      container.read(systemAttentionServiceProvider);
      container.read(trayServiceProvider);
      container.read(soundFeedbackProvider);
    });

    test('an unconfirmed paste sends one OS notice, one in-app toast and '
        'one error sound', () async {
      final fired = await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.unconfirmed);

      expect(fired, isTrue);
      expect(attention.requests, hasLength(1));
      expect(attention.requests.single.kind, AttentionKind.pasteFailedUnknown);
      expect(
        container.read(pasteFailureNotifierProvider)?.outcome,
        PasteOutcome.unconfirmed,
      );
      expect(sound.playErrorCalls, 1);
    });

    test('a landed paste clears a stale notice and sends nothing', () async {
      final fired = await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.success);

      expect(fired, isFalse);
      expect(attention.requests, isEmpty);
      expect(attention.clearCalls, 1);
      expect(container.read(pasteFailureNotifierProvider), isNull);
    });

    test('a receipt-less Linux paste is silent everywhere', () async {
      final fired = await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.unconfirmedNoBridge);

      expect(fired, isFalse);
      expect(attention.requests, isEmpty);
      expect(container.read(pasteFailureNotifierProvider), isNull);
      expect(sound.playErrorCalls, 0);
    });

    test('a refused receipt write sends one calm info notice and an in-app '
        'toast, but no error sound and no tray entry', () async {
      final fired = await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.unconfirmedReceiptRefused);

      expect(fired, isTrue);
      expect(attention.requests, hasLength(1));
      expect(attention.requests.single.kind, AttentionKind.pasteReceiptRefused);
      expect(attention.requests.single.body, en.pasteReceiptRefusedText);
      expect(
        container.read(pasteFailureNotifierProvider)?.outcome,
        PasteOutcome.unconfirmedReceiptRefused,
      );
      expect(sound.playErrorCalls, 0);
      expect(tray.setActionNeededLabels, isEmpty);
    });

    test('a blocked app is silent everywhere', () async {
      final fired = await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.blocked);

      expect(fired, isFalse);
      expect(attention.requests, isEmpty);
      expect(container.read(pasteFailureNotifierProvider), isNull);
    });

    test('a failed paste with a badge sets the tray entry once', () async {
      await container
          .read(pasteResultReporterProvider)
          .report(PasteOutcome.failed);

      expect(attention.requests, hasLength(1));
      expect(tray.setActionNeededLabels, hasLength(1));
    });
  });
}
