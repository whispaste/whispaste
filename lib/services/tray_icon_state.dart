/// Which tray icon variant shows the dictation state (#137).
///
/// The tray icon itself tells a user with the window closed that a dictation
/// is recording or being processed, on macOS, Windows and Linux alike. The
/// variants are the idle icon with a badge in the bottom-right corner: a red
/// dot while recording, an amber ring while transcribing or refining. Dot and
/// ring differ in shape too, so the state does not rely on colour alone.
library;

import '../core/recording/recording_state.dart';

/// The three states the tray icon distinguishes.
enum TrayIconState { idle, recording, processing }

/// The icon state for a recording [phase]. `done` and `error` are end states
/// that stay until the next action; the icon is back to idle for them, like
/// [isDictationBusy].
TrayIconState trayIconStateFor(RecordingPhase phase) => switch (phase) {
  RecordingPhase.recording => TrayIconState.recording,
  RecordingPhase.transcribing ||
  RecordingPhase.refining => TrayIconState.processing,
  RecordingPhase.idle ||
  RecordingPhase.done ||
  RecordingPhase.error => TrayIconState.idle,
};

/// The Flutter asset key of the badge variant for [state], or `null` for
/// idle (each platform keeps its own idle icon). Windows reads an ICO, as
/// PNG tray icons often render as an empty slot there; macOS and Linux read
/// the PNG.
String? trayStateIconAsset(TrayIconState state, {required bool windows}) {
  final ext = windows ? 'ico' : 'png';
  return switch (state) {
    TrayIconState.idle => null,
    TrayIconState.recording => 'assets/tray/tray-recording.$ext',
    TrayIconState.processing => 'assets/tray/tray-processing.$ext',
  };
}

/// The label key of the status line and tooltip prefix for [state]; keys of
/// `trayLabelsFor`.
String trayStatusLabelKey(TrayIconState state) => switch (state) {
  TrayIconState.idle => 'trayStatusReady',
  TrayIconState.recording => 'trayStatusRecording',
  TrayIconState.processing => 'trayStatusProcessing',
};

/// The tray tooltip for [state]: while a dictation runs, its state comes
/// first ([status]), so it survives a truncated tooltip; in idle the tooltip
/// is the [details] line alone, as before.
String trayStateTooltip(
  TrayIconState state, {
  required String status,
  required String details,
}) => state == TrayIconState.idle ? details : '$status · $details';
