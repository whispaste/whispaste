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
///
/// Optional settings parameters enrich the payload with context that the
/// floating overlay needs to render a full UX (progress ring, hotkey hint,
/// AI mode badge, etc.).
String encodeRecordingState(
  RecordingState state, {
  int maxRecordDurationSeconds = 0,
  String? afterAction,
  String? aiMode,
  bool? isLocalStt,
  String? hotkeyLabel,
}) => jsonEncode({
  'phase': state.phase.name,
  'elapsedMs': state.elapsed.inMilliseconds,
  'audioLevel': state.audioLevel,
  'transcript': state.transcript,
  'errorMessage': state.errorMessage,
  if (maxRecordDurationSeconds > 0)
    'maxRecordDurationSeconds': maxRecordDurationSeconds,
  'afterAction': ?afterAction,
  'aiMode': ?aiMode,
  'isLocalStt': ?isLocalStt,
  'hotkeyLabel': ?hotkeyLabel,
});

/// Deserialises a JSON string back into a [DecodedRecordingState].
///
/// Returns a default idle state if the JSON is malformed.
DecodedRecordingState decodeRecordingState(String json) {
  try {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return DecodedRecordingState(
      phase: _parsePhase(map['phase']),
      elapsed: Duration(milliseconds: map['elapsedMs'] as int),
      audioLevel: (map['audioLevel'] as num).toDouble(),
      transcript: map['transcript'] as String?,
      errorMessage: map['errorMessage'] as String?,
      maxRecordDurationSeconds:
          (map['maxRecordDurationSeconds'] as num?)?.toInt() ?? 0,
      afterAction: map['afterAction'] as String?,
      aiMode: map['aiMode'] as String?,
      isLocalStt: map['isLocalStt'] as bool?,
      hotkeyLabel: map['hotkeyLabel'] as String?,
    );
  } catch (_) {
    return const DecodedRecordingState();
  }
}

/// Parses a [RecordingPhase] from a string name or legacy integer index.
RecordingPhase _parsePhase(dynamic raw) {
  if (raw is String) {
    return RecordingPhase.values.firstWhere(
      (p) => p.name == raw,
      orElse: () => RecordingPhase.idle,
    );
  }
  // Backward compat: integer index from old clients.
  if (raw is int && raw >= 0 && raw < RecordingPhase.values.length) {
    return RecordingPhase.values[raw];
  }
  return RecordingPhase.idle;
}

/// Extended [RecordingState] with optional settings context decoded from IPC.
class DecodedRecordingState extends RecordingState {
  const DecodedRecordingState({
    super.phase,
    super.elapsed,
    super.audioLevel,
    super.transcript,
    super.errorMessage,
    this.maxRecordDurationSeconds = 0,
    this.afterAction,
    this.aiMode,
    this.isLocalStt,
    this.hotkeyLabel,
  });

  final int maxRecordDurationSeconds;
  final String? afterAction;
  final String? aiMode;
  final bool? isLocalStt;
  final String? hotkeyLabel;
}

// ---------------------------------------------------------------------------
// Floating button size mapping
// ---------------------------------------------------------------------------

/// Converts a persisted size string ('small', 'normal', 'large') to pixels.
///
/// Shared by the multi-window service and settings UI so size mapping stays
/// consistent everywhere.
int floatingButtonSizeFromString(String size) {
  return switch (size.toLowerCase()) {
    'small' => 48,
    'large' => 72,
    _ => 56, // 'normal' / 'medium' / unknown → default
  };
}
