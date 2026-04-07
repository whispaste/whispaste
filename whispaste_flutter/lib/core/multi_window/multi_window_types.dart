/// Shared multi-window protocol: window type identifiers and command channel.
///
/// Lives in `core/` because it is used by screens (secondary windows),
/// services (window manager), and the app shell — all different layers.
library;

import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../recording/recording_state.dart';

/// Identifies the type of secondary window in its launch arguments.
abstract final class WindowType {
  static const String main = 'main';
  static const String floatingButton = 'floating_button';
  static const String floatingOverlay = 'floating_overlay';
}

/// Named channel for secondary → main command routing.
///
/// Secondary windows call `commandChannel.invokeMethod('toggleRecording')`
/// and the main window receives them via `commandChannel.setMethodCallHandler`.
const commandChannel = WindowMethodChannel(
  'whispaste_commands',
  mode: ChannelMode.unidirectional,
);

// ---------------------------------------------------------------------------
// Cross-window encoding helpers
// ---------------------------------------------------------------------------

/// Serialises [RecordingState] to a JSON string for cross-window transfer.
String encodeRecordingState(RecordingState state) => jsonEncode({
      'phase': state.phase.index,
      'elapsedMs': state.elapsed.inMilliseconds,
      'audioLevel': state.audioLevel,
      'transcript': state.transcript,
      'errorMessage': state.errorMessage,
    });

/// Deserialises a JSON string back into a [RecordingState].
///
/// Returns [RecordingState()] (idle) if the JSON is malformed or contains
/// an out-of-range phase index.
RecordingState decodeRecordingState(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    final phaseIdx = map['phase'] as int;
    if (phaseIdx < 0 || phaseIdx >= RecordingPhase.values.length) {
      return const RecordingState();
    }
    return RecordingState(
      phase: RecordingPhase.values[phaseIdx],
      elapsed: Duration(milliseconds: map['elapsedMs'] as int),
      audioLevel: (map['audioLevel'] as num).toDouble(),
      transcript: map['transcript'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  } catch (_) {
    return const RecordingState();
  }
}

// ---------------------------------------------------------------------------
// Floating button size mapping
// ---------------------------------------------------------------------------

/// Converts a persisted size string ('small', 'normal', 'large') to pixels.
///
/// Shared by [MultiWindowNotifier] and [FloatingButtonNotifier] so neither
/// needs to import the other.
int floatingButtonSizeFromString(String size) {
  return switch (size.toLowerCase()) {
    'small' => 48,
    'large' => 72,
    _ => 56, // 'normal' / 'medium' / unknown → default
  };
}
