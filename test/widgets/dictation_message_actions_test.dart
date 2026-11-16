/// #453: which situation raises which dictation message, with which button.
/// The message is read from the notice provider (kind, tone, action count,
/// what the action does), never from rendered text.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/floating_overlay/pill_hint.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/pending_audio/pending_audio_queue.dart'
    show PendingRetryOutcome;
import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/dictation_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/stt/recovery_toast_notifier.dart';
import 'package:whispaste/widgets/recording_behavior.dart';

import '../fixtures/test_helpers.dart';

Future<ProviderContainer> _fire(
  WidgetTester tester,
  void Function(BuildContext context, L10n l10n) body,
) async {
  await tester.pumpWidget(
    makeTestable(
      Builder(
        builder: (context) => TextButton(
          key: const Key('fire'),
          onPressed: () => body(context, L10n.of(context)),
          child: const Text('fire'),
        ),
      ),
      locale: const Locale('en'),
    ),
  );
  await tester.tap(find.byKey(const Key('fire')));
  await tester.pump();
  return ProviderScope.containerOf(
    tester.element(find.byKey(const Key('fire'))),
  );
}

DictationNotice? _open(ProviderContainer c) => c.read(dictationNoticeProvider);

/// Runs the first button the way the overlay service does.
void _press(ProviderContainer c) {
  final notice = _open(c)!;
  c.read(dictationNoticeProvider.notifier).dismiss();
  notice.actions.first.onPressed();
}

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('recording errors', () {
    testWidgets('a missing model is an error with cause, step and settings', (
      tester,
    ) async {
      var opened = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'stt_model_not_found',
          onDismiss: () {},
          openSettings: () => opened++,
        ),
      );
      final n = _open(c)!;
      expect(n.tone, OverlayNoticeTone.error);
      expect(n.nextStep, isNotEmpty);
      expect(n.actions, hasLength(1));
      _press(c);
      expect(opened, 1);
      expect(_open(c), isNull);
    });

    testWidgets('a repeatable failure offers the retry first', (tester) async {
      var retried = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'stt_server_failed',
          onDismiss: () {},
          retry: () => retried++,
          openSettings: () {},
        ),
      );
      // "Try again" leads, the fix is its alternative: two different effects.
      final n = _open(c)!;
      expect(n.actions.map((a) => a.id), ['retry', 'open-settings']);
      _press(c);
      expect(retried, 1);
    });

    testWidgets('a repeatable failure with a microphone switch is a pair', (
      tester,
    ) async {
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'stt_server_failed',
          onDismiss: () {},
          retry: () {},
          switchMicrophone: (
            label: l10n.micSwitchOfferAction,
            detail: '',
            actionId: 'use-microphone',
            onPressed: () {},
          ),
        ),
      );
      expect(_open(c)!.actions.map((a) => a.id), ['retry', 'use-microphone']);
    });

    testWidgets('a silent microphone offers the switch, run only on press', (
      tester,
    ) async {
      var switched = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'recording_guard_failed',
          onDismiss: () {},
          switchMicrophone: (
            label: l10n.micSwitchOfferAction,
            detail: l10n.micSwitchOfferDetail('Blue Yeti (USB)'),
            actionId: 'use-microphone',
            onPressed: () => switched++,
          ),
        ),
      );
      expect(switched, 0);
      final n = _open(c)!;
      // The id names the situation, the button what it does, and the whole
      // device name is its own line (#613).
      expect(n.id, 'recording_guard_failed');
      expect(n.actions.single.id, 'use-microphone');
      expect(n.detail, contains('Blue Yeti (USB)'));
      expect(n.body, contains('Blue Yeti (USB)'));
      _press(c);
      expect(switched, 1);
    });

    testWidgets('the suggestion arriving later is read out alone, once', (
      tester,
    ) async {
      void show(BuildContext context, L10n l10n, {String? mic}) =>
          showRecordingErrorToast(
            context: context,
            l10n: l10n,
            errorCode: 'recording_guard_failed',
            onDismiss: () {},
            switchMicrophone: mic == null
                ? null
                : (
                    label: l10n.micSwitchOfferAction,
                    detail: l10n.micSwitchOfferDetail(mic),
                    actionId: 'use-microphone',
                    onPressed: () {},
                  ),
          );
      late BuildContext ctx;
      late L10n text;
      await _fire(tester, (context, l10n) {
        ctx = context;
        text = l10n;
        show(context, l10n);
      });
      final first = tester.takeAnnouncements().map((a) => a.message).toList();
      expect(first, hasLength(1));
      expect(first.single, text.recordingGuardFailed);

      show(ctx, text, mic: 'Blue Yeti');
      await tester.pump();
      expect(tester.takeAnnouncements().map((a) => a.message), [
        text.micSwitchOfferDetail('Blue Yeti'),
      ]);

      // The same suggestion again is not read a third time.
      show(ctx, text, mic: 'Blue Yeti');
      await tester.pump();
      expect(tester.takeAnnouncements(), isEmpty);
    });

    testWidgets('a failed quick note offers to copy the text', (tester) async {
      var copied = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'quick_note_append_failed',
          onDismiss: () {},
          copyTranscript: () => copied++,
        ),
      );
      _press(c);
      expect(copied, 1);
    });

    testWidgets('a missing model leads with the download, Settings second', (
      tester,
    ) async {
      var downloads = 0;
      var opened = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'stt_model_not_found',
          onDismiss: () {},
          openSettings: () => opened++,
          downloadModel: () => downloads++,
        ),
      );
      final n = _open(c)!;
      expect(n.actions.map((a) => a.id), ['download-model', 'open-settings']);
      expect(n.actions.first.confirmation, isNotNull);
      n.actions.first.onPressed();
      n.actions.last.onPressed();
      expect((downloads, opened), (1, 1));
    });

    testWidgets('a quick-note failure offers copy first, Notes second', (
      tester,
    ) async {
      var copied = 0;
      var notes = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'quick_note_append_failed',
          onDismiss: () {},
          copyTranscript: () => copied++,
          openNotes: () => notes++,
        ),
      );
      final n = _open(c)!;
      expect(n.actions.map((a) => a.id), ['copy-text', 'open-notes']);
      n.actions.last.onPressed();
      expect((copied, notes), (0, 1));
    });

    testWidgets('a quick-note failure without a transcript still opens Notes', (
      tester,
    ) async {
      var notes = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'quick_note_append_failed',
          onDismiss: () {},
          openNotes: () => notes++,
        ),
      );
      expect(_open(c)!.actions.map((a) => a.id), ['open-notes']);
      _press(c);
      expect(notes, 1);
    });

    testWidgets('a denied microphone on macOS opens the system settings', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var opened = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'mic_permission_denied',
          onDismiss: () {},
          openMicrophoneSettings: () => opened++,
        ),
      );
      expect(_open(c)!.tone, OverlayNoticeTone.error);
      expect(_open(c)!.actions, hasLength(1));
      _press(c);
      expect(opened, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a denied microphone elsewhere has only the cross, no button', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'mic_permission_denied',
          onDismiss: () {},
          openMicrophoneSettings: () {},
        ),
      );
      expect(_open(c)!.tone, OverlayNoticeTone.error);
      expect(_open(c)!.actions, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // #826 (E8): the card for a retry that did not work.
  group('failed retry of a kept dictation', () {
    Future<ProviderContainer> show(
      WidgetTester tester,
      PendingRetryOutcome outcome, {
      required void Function() retry,
      required void Function() openRecordings,
    }) => _fire(
      tester,
      (context, l10n) => showPendingRetryFailedCard(
        context: context,
        l10n: l10n,
        outcome: outcome,
        retry: retry,
        openRecordings: openRecordings,
      ),
    );

    testWidgets('failed again: try again first, Recordings as the second', (
      tester,
    ) async {
      var retried = 0;
      var opened = 0;
      final c = await show(
        tester,
        PendingRetryOutcome.failed,
        retry: () => retried++,
        openRecordings: () => opened++,
      );
      final n = _open(c)!;
      expect(n.id, 'retry-failed');
      expect(n.tone, OverlayNoticeTone.error);
      expect(n.actions.map((a) => a.id), ['retry', 'open-recordings']);
      n.actions[1].onPressed();
      expect(opened, 1);
      expect(retried, 0);
      n.actions[0].onPressed();
      expect(retried, 1);
    });

    for (final outcome in [
      PendingRetryOutcome.expired,
      PendingRetryOutcome.missing,
    ]) {
      testWidgets('$outcome: only Recordings, nothing to try again', (
        tester,
      ) async {
        var opened = 0;
        final c = await show(
          tester,
          outcome,
          retry: () => fail('a gone recording cannot be retried'),
          openRecordings: () => opened++,
        );
        final n = _open(c)!;
        expect(n.actions.map((a) => a.id), ['open-recordings']);
        n.actions.single.onPressed();
        expect(opened, 1);
      });
    }

    testWidgets('a result that needs no word raises no card', (tester) async {
      final c = await show(
        tester,
        PendingRetryOutcome.saved,
        retry: () {},
        openRecordings: () {},
      );
      expect(_open(c), isNull);
    });
  });

  group('paste failures', () {
    testWidgets('a missing permission on macOS runs the entry reset', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      var reset = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.permissionMissing,
          openAccessibilitySettings: () {},
          resetEntryAndGrant: () => reset++,
        ),
      );
      expect(_open(c)!.actions, hasLength(1));
      _press(c);
      expect(reset, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a missing permission on Linux opens the auto-paste settings', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var opened = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.permissionMissing,
          openAutoPasteSettings: () => opened++,
        ),
      );
      _press(c);
      expect(opened, 1);
      debugDefaultTargetPlatformOverride = null;
    });

    for (final outcome in [
      PasteOutcome.noTarget,
      PasteOutcome.targetChanged,
      PasteOutcome.failed,
    ]) {
      testWidgets('$outcome offers to paste the text again', (tester) async {
        var pasted = 0;
        final c = await _fire(
          tester,
          (context, l10n) => showPasteFailureToast(
            context: context,
            l10n: l10n,
            outcome: outcome,
            repaste: () => pasted++,
          ),
        );
        expect(_open(c)!.actions.single.id, 'paste-failure-repaste');
        _press(c);
        expect(pasted, 1);
      });
    }

    // #1147: the warning offers only what is true. After the legacy restore
    // the text is not on the clipboard, so paste again is the way to insert
    // it. Plain `unconfirmed` keeps the text on the clipboard and offers no
    // paste again (it may have landed). Neither offers a new dictation.
    testWidgets('unconfirmedRestored offers paste again, no new dictation', (
      tester,
    ) async {
      var pasted = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.unconfirmedRestored,
          repaste: () => pasted++,
        ),
      );
      final n = _open(c)!;
      expect(n.offersNewDictation, isFalse);
      expect(n.actions.single.id, 'paste-failure-repaste');
      _press(c);
      expect(pasted, 1);
    });

    testWidgets('unconfirmed offers no paste again and no new dictation', (
      tester,
    ) async {
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.unconfirmed,
          repaste: () {},
        ),
      );
      final n = _open(c)!;
      expect(n.offersNewDictation, isFalse);
      expect(n.actions, isEmpty);
    });

    testWidgets('on Linux only the fix is offered, paste again would fail', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      var pasted = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.permissionMissing,
          openAutoPasteSettings: () {},
          repaste: () => pasted++,
        ),
      );
      debugDefaultTargetPlatformOverride = null;
      expect(_open(c)!.actions.single.id, 'paste-failure-toast-action');
      expect(pasted, 0);
    });

    testWidgets(
      'on macOS a missing permission pairs the fix with paste again',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        var pasted = 0;
        var opened = 0;
        final c = await _fire(
          tester,
          (context, l10n) => showPasteFailureToast(
            context: context,
            l10n: l10n,
            outcome: PasteOutcome.permissionMissing,
            openAccessibilitySettings: () => opened++,
            repaste: () => pasted++,
          ),
        );
        debugDefaultTargetPlatformOverride = null;
        final actions = _open(c)!.actions;
        expect(actions.map((a) => a.id), [
          'paste-failure-toast-action',
          'paste-failure-repaste',
        ]);
        actions.last.onPressed();
        expect(pasted, 1);
        expect(opened, 0);
      },
    );

    testWidgets('a denied microphone without its callback has no button', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'mic_permission_denied',
          onDismiss: () {},
        ),
      );
      debugDefaultTargetPlatformOverride = null;
      expect(_open(c)!.actions, isEmpty);
    });

    // #1617: the outcome is the headline, cause, way out and clipboard
    // sentence form the body, so the card never cuts the clipboard sentence.
    testWidgets('a secure-input skip splits headline and body', (tester) async {
      late L10n l10n;
      final c = await _fire(tester, (context, l) {
        l10n = l;
        showPasteFailureToast(
          context: context,
          l10n: l,
          outcome: PasteOutcome.secureInput,
          secureInputHolder: const SecureInputHolder(
            name: 'SecurityAgent',
            bundleId: 'com.apple.SecurityAgent',
          ),
        );
      });
      final notice = _open(c)!;
      expect(notice.cause, l10n.pasteSecureInputTitle);
      expect(notice.nextStep, startsWith(l10n.pasteSecureInputSystem));
      expect(notice.nextStep, isNot(contains('SecurityAgent')));
    });

    for (final outcome in [
      PasteOutcome.elevationBlocked,
      PasteOutcome.secureInput,
      PasteOutcome.unconfirmed,
    ]) {
      testWidgets('$outcome gets no paste-again button', (tester) async {
        final c = await _fire(
          tester,
          (context, l10n) => showPasteFailureToast(
            context: context,
            l10n: l10n,
            outcome: outcome,
            repaste: () {},
          ),
        );
        expect(_open(c)!.actions, isEmpty);
      });
    }

    testWidgets('no receipt bridge raises no message at all', (tester) async {
      final c = await _fire(
        tester,
        (context, l10n) => showPasteFailureToast(
          context: context,
          l10n: l10n,
          outcome: PasteOutcome.unconfirmedNoBridge,
        ),
      );
      expect(_open(c), isNull);
    });
  });

  group('recovery outcomes', () {
    final targets = {
      RecoveryToastKind.gpuLoadCrashDisabled: 'speech-gpu',
      RecoveryToastKind.cudaLoadCrashDisabled: 'speech-gpu',
      RecoveryToastKind.gpuProbeFailed: 'speech-gpu',
      RecoveryToastKind.gpuLoadIncompatible: 'speech-gpu',
    };
    testWidgets('the card of a model that cannot start offers Restart first', (
      tester,
    ) async {
      final opened = <String>[];
      var restarts = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecoveryToast(
          context: context,
          l10n: l10n,
          kind: RecoveryToastKind.exhausted,
          openSettings: opened.add,
          restart: () => restarts++,
        ),
      );
      final notice = _open(c)!;
      expect(notice.id, 'recovery-exhausted');
      expect(notice.actions.map((a) => a.id), ['restart', 'open-settings']);
      notice.actions.first.onPressed();
      expect(restarts, 1);
      expect(opened, isEmpty);
      notice.actions.last.onPressed();
      expect(opened, ['stt-model']);
    });

    testWidgets('the engine-restart error offers Restart', (tester) async {
      var restarts = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecordingErrorToast(
          context: context,
          l10n: l10n,
          errorCode: 'stt_engine_restart_needed',
          onDismiss: () {},
          restart: () => restarts++,
        ),
      );
      final notice = _open(c)!;
      expect(notice.actions.map((a) => a.id), ['restart']);
      notice.actions.single.onPressed();
      expect(restarts, 1);
    });

    testWidgets('the hotkey card offers Restart and stays open', (
      tester,
    ) async {
      var restarts = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showWpHotkeyHealFailedCard(
          context: context,
          l10n: l10n,
          restart: () => restarts++,
        ),
      );
      final notice = _open(c)!;
      expect(notice.id, 'hotkey-heal-failed-toast');
      expect(notice.actions.map((a) => a.id), ['restart']);
      expect(notice.closesItself, isFalse);
      notice.actions.single.onPressed();
      expect(restarts, 1);
    });

    for (final entry in targets.entries) {
      testWidgets('${entry.key.name} leads to the ${entry.value} settings', (
        tester,
      ) async {
        final opened = <String>[];
        final c = await _fire(
          tester,
          (context, l10n) => showRecoveryToast(
            context: context,
            l10n: l10n,
            kind: entry.key,
            openSettings: opened.add,
          ),
        );
        _press(c);
        expect(opened, [entry.value]);
      });
    }

    testWidgets('a missing Visual C++ runtime is an error with its install', (
      tester,
    ) async {
      var installs = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showRecoveryToast(
          context: context,
          l10n: l10n,
          kind: RecoveryToastKind.vcRuntimeMissing,
          openSettings: (_) {},
          installVcRuntime: () => installs++,
        ),
      );
      expect(_open(c)!.tone, OverlayNoticeTone.error);
      _press(c);
      expect(installs, 1);
    });

    testWidgets('a damaged model file being reloaded is a passive hint with '
        'its own id', (tester) async {
      final c = await _fire(
        tester,
        (context, l10n) => showRecoveryToast(
          context: context,
          l10n: l10n,
          kind: RecoveryToastKind.modelFileRepair,
          openSettings: (_) {},
        ),
      );
      expect(_open(c)!.id, 'recovery-model-file-repair');
      expect(_open(c)!.actions, isEmpty);
    });

    testWidgets('the reload info has no button and closes itself', (
      tester,
    ) async {
      final c = await _fire(
        tester,
        (context, l10n) => showRecoveryToast(
          context: context,
          l10n: l10n,
          kind: RecoveryToastKind.abiInfo,
          openSettings: (_) {},
        ),
      );
      expect(_open(c)!.actions, isEmpty);
      expect(_open(c)!.autoDismiss, isNotNull);
      await tester.pump(const Duration(seconds: 9));
      expect(_open(c), isNull);
    });
  });

  group('hints', () {
    testWidgets('the wrong-language hint switches the language once', (
      tester,
    ) async {
      var switched = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showLanguageMismatchToast(
          context: context,
          l10n: l10n,
          detected: 'de',
          onSwitch: () => switched++,
        ),
      );
      expect(_open(c)!.tone, OverlayNoticeTone.hint);
      expect(_open(c)!.actions.first.label, contains('DE'));
      _press(c);
      expect(switched, 1);
    });

    // #877: the second button keeps the fixed language instead of switching.
    testWidgets('"Keep" on the wrong-language hint keeps, never switches', (
      tester,
    ) async {
      var switched = 0;
      var kept = 0;
      final c = await _fire(
        tester,
        (context, l10n) => showLanguageMismatchToast(
          context: context,
          l10n: l10n,
          detected: 'de',
          onSwitch: () => switched++,
          onKeep: () => kept++,
        ),
      );
      final keep = _open(
        c,
      )!.actions.singleWhere((a) => a.id == 'keep-language');
      c.read(dictationNoticeProvider.notifier).dismiss();
      keep.onPressed();
      expect(kept, 1);
      expect(switched, 0);
    });

    testWidgets('the CPU fallback names cause and next step', (tester) async {
      final c = await _fire(
        tester,
        (context, l10n) => showCpuFallbackToast(context: context, l10n: l10n),
      );
      expect(_open(c)!.nextStep, isNotEmpty);
    });

    testWidgets('no smaller model is an error that stays', (tester) async {
      final c = await _fire(
        tester,
        (context, l10n) =>
            showOomNoSmallerModelToast(context: context, l10n: l10n),
      );
      expect(_open(c)!.tone, OverlayNoticeTone.error);
      await tester.pump(const Duration(minutes: 5));
      expect(_open(c), isNotNull);
    });
  });

  // #839: handover "Try again" -> pill hint "saved, not pasted", found by id.
  group('retry hint', () {
    testWidgets('a saved text that was not pasted raises retry-not-pasted', (
      tester,
    ) async {
      await tester.pumpWidget(
        makeTestable(
          Consumer(
            builder: (context, ref, _) => TextButton(
              key: const Key('retry'),
              onPressed: () => unawaited(
                runKeptDictationRetry(
                  context: context,
                  ref: ref,
                  l10n: L10n.of(context),
                  run: () async =>
                      (outcome: PendingRetryOutcome.saved, paste: null),
                  openRecordings: () {},
                  isMounted: () => true,
                ),
              ),
              child: const Text('retry'),
            ),
          ),
          locale: const Locale('en'),
        ),
      );
      await tester.tap(find.byKey(const Key('retry')));
      await tester.pump();
      final c = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('retry'))),
      );

      expect(c.read(overlayPillHintProvider)?.id, 'retry-not-pasted');
    });
  });
}
