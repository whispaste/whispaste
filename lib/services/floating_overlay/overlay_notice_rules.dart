/// Which notice card the overlay shows (overlay F2).
///
/// Pure logic over the recording signals, testable without a window.
library;

import 'dart:async';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/recording/recording_state.dart'
    show RecordingPhase, isDictationBusy;
import '../audio_service.dart' show RecordingStartFailure;
import 'floating_overlay_controller_interface.dart' show OverlayVisualState;
import 'overlay_notice.dart';

/// The card due for the current overlay state, or null for the plain pill.
///
/// - [errorCode]: the error key of a failed start ([RecordingStartFailure]).
/// - [busyApp]: the app holding the microphone, when the platform names it.
/// - [signalLost] / [quiet]: the live microphone signals of a recording.
/// - [remaining]: time left before the duration limit while the countdown
///   is due, else null.
/// - [canExtend]: the limit has not been extended in this recording yet.
/// - [extendMinutes]: minutes one extension adds, for the button label.
/// - [micChangeQueued]: the user already asked to change the microphone;
///   Settings open when this dictation ends, so the card says so instead of
///   offering the action again.
/// - [hiddenKinds]: cards the user hid for this recording with the cross; the
///   recording goes on without them.
OverlayNotice? noticeFor({
  required OverlayVisualState state,
  required L10n l10n,
  String? errorCode,
  String? busyApp,
  bool signalLost = false,
  bool quiet = false,
  bool quietHintEnabled = true,
  String? remaining,
  bool canExtend = false,
  int extendMinutes = 1,
  bool micChangeQueued = false,
  Set<OverlayNoticeKind> hiddenKinds = const {},
}) {
  OverlayNoticeAction action(
    OverlayNoticeActionId id,
    String label, {
    bool primary = false,
  }) => OverlayNoticeAction(action: id, label: label, primary: primary);

  final changeMic = action(
    OverlayNoticeActionId.changeMicrophone,
    l10n.overlayNoticeChooseMicrophone,
  );
  final dismiss = action(
    OverlayNoticeActionId.dismiss,
    l10n.overlayNoticeDismiss,
  );
  // Over a running recording the cross only hides the card (never stops or
  // discards), and it says so.
  final hideHint = action(
    OverlayNoticeActionId.hideHint,
    l10n.overlayNoticeHideHint,
  );

  switch (state) {
    case OverlayVisualState.error:
      if (errorCode == RecordingStartFailure.noMicrophone.errorCode) {
        return OverlayNotice(
          kind: OverlayNoticeKind.noMicrophone,
          tone: OverlayNoticeTone.error,
          title: l10n.overlayNoticeNoMicrophoneTitle,
          body: l10n.overlayNoticeNoMicrophoneBody,
          actions: [
            action(
              OverlayNoticeActionId.changeMicrophone,
              l10n.overlayNoticeChooseMicrophone,
              primary: true,
            ),
            dismiss,
          ],
        );
      }
      if (errorCode == RecordingStartFailure.startFailed.errorCode) {
        return OverlayNotice(
          kind: OverlayNoticeKind.startFailed,
          tone: OverlayNoticeTone.error,
          title: l10n.overlayNoticeStartFailedTitle,
          body: busyApp == null || busyApp.isEmpty
              ? l10n.overlayNoticeStartFailedBody
              : l10n.overlayNoticeStartFailedBodyApp(busyApp),
          actions: [
            action(
              OverlayNoticeActionId.retry,
              l10n.actionRetry,
              primary: true,
            ),
            changeMic,
            dismiss,
          ],
        );
      }
      return null;

    case OverlayVisualState.recording:
      if (signalLost && !hiddenKinds.contains(OverlayNoticeKind.signalLost)) {
        return OverlayNotice(
          kind: OverlayNoticeKind.signalLost,
          tone: OverlayNoticeTone.error,
          title: l10n.overlayNoticeSignalLostTitle,
          body: l10n.overlayNoticeSignalLostBody,
          actions: [
            action(
              OverlayNoticeActionId.pasteSoFar,
              // Same effect as the stop on the other cards, so the same label.
              l10n.overlayNoticeStopNow,
              primary: true,
            ),
            // The one card that offers to throw the audio away: the mic is
            // gone, so the user may not want the partial text (#138).
            action(
              OverlayNoticeActionId.discardRecording,
              l10n.overlayNoticeDiscard,
            ),
            hideHint,
          ],
        );
      }
      if (remaining != null &&
          !hiddenKinds.contains(OverlayNoticeKind.timeRunningOut)) {
        final stop = action(
          OverlayNoticeActionId.stopNow,
          l10n.overlayNoticeStopNow,
          primary: !canExtend,
        );
        return OverlayNotice(
          kind: OverlayNoticeKind.timeRunningOut,
          tone: OverlayNoticeTone.hint,
          title: l10n.overlayRemainingTime(remaining),
          body: l10n.overlayNoticeTimeRunningOutBody,
          actions: [
            if (canExtend)
              action(
                OverlayNoticeActionId.keepRecording,
                l10n.overlayNoticeKeepRecording(extendMinutes),
                primary: true,
              ),
            stop,
            hideHint,
          ],
        );
      }
      if (quiet &&
          quietHintEnabled &&
          !hiddenKinds.contains(OverlayNoticeKind.quiet)) {
        return OverlayNotice(
          kind: OverlayNoticeKind.quiet,
          tone: OverlayNoticeTone.hint,
          title: l10n.overlayMicVeryQuiet,
          body: micChangeQueued
              ? l10n.overlayNoticeMicChangeAfter
              : l10n.overlayNoticeQuietBody,
          actions: [
            // The card covers the pill, so it carries the stop itself: a
            // mouse user can always end the dictation by mouse. The cross
            // hides the card and keeps recording; the hint is turned off in
            // Settings > Overlay, not here.
            action(
              OverlayNoticeActionId.stopNow,
              l10n.overlayNoticeStopNow,
              primary: true,
            ),
            if (!micChangeQueued)
              action(
                OverlayNoticeActionId.changeMicrophone,
                l10n.overlayNoticeChooseMicrophone,
              ),
            hideHint,
          ],
        );
      }
      return null;

    case OverlayVisualState.transcribing:
    case OverlayVisualState.done:
      return null;
  }
}

/// Whether a card holds the global cancel key (#728): it has a real button
/// (the close cross does not count) or it stands until closed. Only a card
/// that closes itself and has no button leaves Escape to the target app.
/// Shared by the key grab and the footer so both agree.
bool noticeHoldsCancelKey({required int buttons, required bool standing}) =>
    buttons > 0 || standing;

/// What runs behind a card, for its footer: the keys mean something else in
/// each (#984).
enum NoticeFooterPhase {
  /// A recording runs: the hotkey stops and pastes, the cancel key discards.
  recording,

  /// The text is being transcribed or refined: the hotkey does nothing then,
  /// only the cancel key works, and it discards.
  processing,

  /// No dictation runs: the hotkey starts a new one, the cancel key closes
  /// the card.
  idle,
}

/// The footer line of a card (#781): only the keys that work while it stands
/// in [phase] (#984). [holdsCancelKey] matters only when no dictation runs:
/// a self-closing card without a button leaves the cancel key to the target
/// app, so its footer names only the hotkey. The keys of the card's buttons
/// stand on the buttons themselves; the footer names only the keys no button
/// shows (#1845: repeating them made the line too long to read).
String noticeFooterFor({
  required L10n l10n,
  required NoticeFooterPhase phase,
  required String hotkey,
  required String cancelKey,
  bool holdsCancelKey = true,
}) => switch (phase) {
  NoticeFooterPhase.recording => l10n.overlayNoticeFooterDictating(
    hotkey,
    cancelKey,
  ),
  NoticeFooterPhase.processing => l10n.overlayNoticeFooterProcessing(cancelKey),
  NoticeFooterPhase.idle =>
    holdsCancelKey
        ? l10n.overlayNoticeFooterIdle(hotkey, cancelKey)
        : l10n.overlayNoticeFooterHotkeyOnly(hotkey),
};

/// How long the action key of a two-button card waits for a second press
/// before it runs the first button (#816). Short enough that the first button
/// still feels immediate, long enough for a relaxed double press.
const noticeSecondPressWindow = Duration(milliseconds: 400);

/// The button a run of [presses] of the action key runs on a card with
/// [buttons] buttons (#816): one press the first, a second press within
/// [noticeSecondPressWindow] the second. A card with one button ignores the
/// count, so no press is ever lost.
OverlayNoticeActionId noticeActionForPresses({
  required int presses,
  required int buttons,
}) => presses >= 2 && buttons >= 2
    ? OverlayNoticeActionId.notice2
    : OverlayNoticeActionId.notice1;

/// Turns presses of the one global action key into card buttons (#816), so
/// the second button needs no third global key. A one-button card runs at
/// once; on a two-button card the first press waits [window] for a second.
/// [card] is the card the press belongs to: a press for another card starts
/// over, so a pending press never runs a button of a card that replaced it.
class NoticeKeyPresses<T extends Object> {
  NoticeKeyPresses(this._run, {this.window = noticeSecondPressWindow});

  final void Function(T card, OverlayNoticeActionId action) _run;
  final Duration window;
  Timer? _pending;
  T? _card;

  /// One press of the action key while [card] with [buttons] buttons stands.
  void press(T card, {required int buttons}) {
    final second = _pending != null && identical(_card, card);
    cancel();
    if (buttons < 2 || second) {
      _run(
        card,
        noticeActionForPresses(presses: second ? 2 : 1, buttons: buttons),
      );
      return;
    }
    _card = card;
    _pending = Timer(window, () {
      _pending = null;
      _card = null;
      _run(card, noticeActionForPresses(presses: 1, buttons: buttons));
    });
  }

  /// Drops a waiting first press, e.g. when the card closed.
  void cancel() {
    _pending?.cancel();
    _pending = null;
    _card = null;
  }
}

/// The footer phase for the recording [phase] behind a card (#984): a
/// recording, the processing that follows, or nothing running. Done and error
/// count as idle, so a card that outlives its recording no longer offers
/// "stop and paste" (#1195).
NoticeFooterPhase noticeFooterPhaseFor(RecordingPhase phase) => switch (phase) {
  RecordingPhase.recording => NoticeFooterPhase.recording,
  RecordingPhase.transcribing ||
  RecordingPhase.refining => NoticeFooterPhase.processing,
  RecordingPhase.idle ||
  RecordingPhase.done ||
  RecordingPhase.error => NoticeFooterPhase.idle,
};

/// Id of the card "still busy with the previous recording": a press that came
/// while a recording or its processing still held the pipeline.
const kPipelineBusyNoticeId = 'pipeline-busy';

/// Id of the card "the text is still being processed": a press during
/// transcription or refinement.
const kStillProcessingNoticeId = 'still-processing';

/// Whether the card [noticeId] still tells the truth (#1195). The busy cards
/// hold only while the app is busy: "still busy" while a dictation runs or a
/// pipeline still holds its lock ([pipelineBusy]), "still processing" only
/// while the text is transcribed or refined. Every other card is not tied to
/// the recording state.
bool noticeFitsState({
  required String noticeId,
  required RecordingPhase phase,
  required bool pipelineBusy,
}) => switch (noticeId) {
  kPipelineBusyNoticeId => pipelineBusy || isDictationBusy(phase),
  kStillProcessingNoticeId =>
    phase == RecordingPhase.transcribing || phase == RecordingPhase.refining,
  _ => true,
};
