/// Overlay F2: which notice card each state gets, and that no action on any
/// card discards what was said (only keep recording, or stop and transcribe).
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/audio/signal_loss_detector.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/theme/overlay_design_spec.dart';
import 'package:whispaste/services/audio_service.dart'
    show RecordingStartFailure;
import 'package:whispaste/services/floating_overlay/floating_overlay_controller_interface.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice.dart';
import 'package:whispaste/services/floating_overlay/overlay_notice_rules.dart';

void main() {
  final l10n = lookupL10n(const Locale('en'));

  List<OverlayNoticeActionId> ids(OverlayNotice? n) => [
    for (final a in n!.actions) a.action,
  ];
  OverlayNoticeActionId primary(OverlayNotice? n) =>
      n!.actions.firstWhere((a) => a.primary).action;

  group('error state', () {
    test('no microphone: choose a microphone, or close', () {
      final n = noticeFor(
        state: OverlayVisualState.error,
        l10n: l10n,
        errorCode: RecordingStartFailure.noMicrophone.errorCode,
      );
      expect(n!.kind, OverlayNoticeKind.noMicrophone);
      expect(n.tone, OverlayNoticeTone.error);
      expect(primary(n), OverlayNoticeActionId.changeMicrophone);
      expect(ids(n), contains(OverlayNoticeActionId.dismiss));
    });

    test('start failed: retry first, change microphone second', () {
      final n = noticeFor(
        state: OverlayVisualState.error,
        l10n: l10n,
        errorCode: RecordingStartFailure.startFailed.errorCode,
      );
      expect(n!.kind, OverlayNoticeKind.startFailed);
      expect(primary(n), OverlayNoticeActionId.retry);
      expect(ids(n), contains(OverlayNoticeActionId.changeMicrophone));
    });

    test('start failed names the app holding the microphone, with actions '
        'addressable by test name', () {
      final n = noticeFor(
        state: OverlayVisualState.error,
        l10n: l10n,
        errorCode: RecordingStartFailure.startFailed.errorCode,
        busyApp: 'Zoom',
      );
      expect(n!.body, contains('Zoom'));
      expect(primary(n), OverlayNoticeActionId.retry);
      expect(
        n.actions.map((a) => a.testName),
        containsAll(['retry', 'change_microphone']),
      );
      final plain = noticeFor(
        state: OverlayVisualState.error,
        l10n: l10n,
        errorCode: RecordingStartFailure.startFailed.errorCode,
      );
      expect(plain!.body, l10n.overlayNoticeStartFailedBody);
    });

    test('other errors keep the plain pill', () {
      expect(
        noticeFor(
          state: OverlayVisualState.error,
          l10n: l10n,
          errorCode: 'transcription_failed',
        ),
        isNull,
      );
    });
  });

  group('recording state', () {
    test('nothing wrong: no card', () {
      expect(
        noticeFor(state: OverlayVisualState.recording, l10n: l10n),
        isNull,
      );
    });

    test('signal lost: paste what was said, never a discard', () {
      final n = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        signalLost: true,
        quiet: true,
        remaining: '0:20',
      );
      expect(n!.kind, OverlayNoticeKind.signalLost, reason: 'highest rank');
      // Paste or discard (#138), plus the cross, which hides the card (#781).
      expect(ids(n), [
        OverlayNoticeActionId.pasteSoFar,
        OverlayNoticeActionId.discardRecording,
        OverlayNoticeActionId.hideHint,
      ]);
      expect(primary(n), OverlayNoticeActionId.pasteSoFar);
    });

    test('a mic dropout offers paste-so-far and discard by stable ids', () {
      final detector = SignalLossDetector(samplesPerSecond: 10);
      expect(detector.observe(-30), isNull);
      bool? lost;
      for (var i = 0; i < 30; i++) {
        lost = detector.observe(double.negativeInfinity) ?? lost;
      }
      expect(lost, isTrue);
      final n = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        signalLost: lost!,
      );
      expect(n!.kind, OverlayNoticeKind.signalLost);
      expect(
        n.actions.map((a) => a.testName),
        containsAll(['paste_so_far', 'discard_recording']),
      );
    });

    test('time running out: record more once, then only finish and paste', () {
      final first = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        remaining: '0:25',
        quiet: true,
        canExtend: true,
        extendMinutes: 5,
      );
      expect(first!.kind, OverlayNoticeKind.timeRunningOut);
      expect(primary(first), OverlayNoticeActionId.keepRecording);
      expect(first.actions.first.label, 'Record 5 more min');
      expect(ids(first), [
        OverlayNoticeActionId.keepRecording,
        OverlayNoticeActionId.stopNow,
        OverlayNoticeActionId.hideHint,
      ]);

      final extended = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        remaining: '0:25',
      );
      expect(ids(extended), [
        OverlayNoticeActionId.stopNow,
        OverlayNoticeActionId.hideHint,
      ]);
      expect(primary(extended), OverlayNoticeActionId.stopNow);
    });

    test('quiet: finish and paste first, choose a microphone second', () {
      final n = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        quiet: true,
      );
      expect(n!.kind, OverlayNoticeKind.quiet);
      expect(n.tone, OverlayNoticeTone.hint);
      expect(primary(n), OverlayNoticeActionId.stopNow);
      expect(ids(n), [
        OverlayNoticeActionId.stopNow,
        OverlayNoticeActionId.changeMicrophone,
        OverlayNoticeActionId.hideHint,
      ]);
    });

    test('a card over a recording ends in a cross that only hides it', () {
      final cards = [
        noticeFor(state: OverlayVisualState.recording, l10n: l10n, quiet: true),
        noticeFor(
          state: OverlayVisualState.recording,
          l10n: l10n,
          remaining: '0:20',
          canExtend: true,
        ),
      ];
      for (final n in cards) {
        expect(n!.actions.last.action, OverlayNoticeActionId.hideHint);
        expect(ids(n), isNot(contains(OverlayNoticeActionId.dismiss)));
      }
    });

    test('a hidden card stays away for the rest of the recording', () {
      for (final hidden in [
        OverlayNoticeKind.quiet,
        OverlayNoticeKind.timeRunningOut,
      ]) {
        expect(
          noticeFor(
            state: OverlayVisualState.recording,
            l10n: l10n,
            quiet: true,
            remaining: '0:20',
            hiddenKinds: {
              OverlayNoticeKind.quiet,
              OverlayNoticeKind.timeRunningOut,
            },
          ),
          isNull,
          reason: '$hidden',
        );
      }
      // Hiding one kind keeps the other.
      final n = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        quiet: true,
        remaining: '0:20',
        hiddenKinds: {OverlayNoticeKind.timeRunningOut},
      );
      expect(n!.kind, OverlayNoticeKind.quiet);
    });

    test('quiet hint turned off: no card', () {
      expect(
        noticeFor(
          state: OverlayVisualState.recording,
          l10n: l10n,
          quiet: true,
          quietHintEnabled: false,
        ),
        isNull,
      );
    });

    test('microphone change queued: the card no longer offers it', () {
      final n = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        quiet: true,
        micChangeQueued: true,
      );
      expect(ids(n), [
        OverlayNoticeActionId.stopNow,
        OverlayNoticeActionId.hideHint,
      ]);
      expect(primary(n), OverlayNoticeActionId.stopNow);
    });
  });

  // #826: one label, one effect. Stopping to transcribe and paste is the same
  // effect on the lost-signal, the time-limit and the quiet card, so the three
  // buttons carry the same text.
  test('every stop-and-paste button carries the same label', () {
    String stopLabel(OverlayNotice? n) => n!.actions
        .firstWhere(
          (a) =>
              a.action == OverlayNoticeActionId.stopNow ||
              a.action == OverlayNoticeActionId.pasteSoFar,
        )
        .label;
    final lost = noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      signalLost: true,
    );
    final limit = noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      remaining: '0:20',
    );
    final quiet = noticeFor(
      state: OverlayVisualState.recording,
      l10n: l10n,
      quiet: true,
    );
    expect({stopLabel(lost), stopLabel(limit), stopLabel(quiet)}, hasLength(1));
  });

  test('transcribing and done never show a card', () {
    for (final state in [
      OverlayVisualState.transcribing,
      OverlayVisualState.done,
    ]) {
      expect(
        noticeFor(state: state, l10n: l10n, signalLost: true, quiet: true),
        isNull,
      );
    }
  });

  group('wire format', () {
    test('a snapshot with a card travels as size class notice', () {
      final notice = noticeFor(
        state: OverlayVisualState.recording,
        l10n: l10n,
        quiet: true,
      );
      final snapshot = FloatingOverlaySnapshot(
        visible: true,
        state: OverlayVisualState.recording,
        label: '',
        size: OverlaySizeVariant.compact,
        notice: notice,
      );
      final map = snapshot.toMap();
      expect(map['size'], 'notice');
      expect(map['pillSize'], OverlaySizeVariant.compact.name);

      final back = FloatingOverlaySnapshot.fromMap(map);
      expect(back.size, OverlaySizeVariant.compact);
      expect(back.notice!.kind, OverlayNoticeKind.quiet);
      expect(
        [for (final a in back.notice!.actions) (a.action, a.primary)],
        [for (final a in notice!.actions) (a.action, a.primary)],
      );
    });

    test('a malformed card payload falls back to the pill', () {
      expect(OverlayNotice.fromMap({'kind': 'nonsense'}), isNull);
      expect(OverlayNotice.fromMap('x'), isNull);
    });
  });
}
