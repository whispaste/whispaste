/// Type-safe enums for settings values that were previously magic strings.
///
/// Each enum stores its persistence key in [value] so it round-trips through
/// SQLite (`toStorageMap` / `fromStorageMap`) without breaking existing data.
library;

// ---------------------------------------------------------------------------
// STT Provider
// ---------------------------------------------------------------------------

/// Speech-to-text engine selection.
enum SttProviderType {
  onDevice('On Device'),
  openAI('OpenAI'),
  deepgram('Deepgram');

  const SttProviderType(this.value);

  /// The string persisted in SQLite and shown in dropdowns.
  final String value;

  /// Look up by persisted [value]. Falls back to [onDevice].
  static SttProviderType fromValue(String? v) {
    if (v == 'On Device (Private)') return onDevice; // legacy migration
    // Groq was removed in v1.2.13 — treat any legacy 'Groq' value as onDevice.
    if (v == 'Groq') return onDevice;
    for (final e in values) {
      if (e.value == v) return e;
    }
    return onDevice;
  }

  bool get isLocal => this == onDevice;
}

// ---------------------------------------------------------------------------
// Cloud STT Provider (sub-selection when SttProviderType is not onDevice)
// ---------------------------------------------------------------------------

/// Cloud STT backend.
enum CloudSttProvider {
  openAI('openai'),
  deepgram('deepgram');

  const CloudSttProvider(this.value);
  final String value;

  static CloudSttProvider fromValue(String? v) {
    // Groq was removed in v1.2.13 — fall back to openAI for any legacy value.
    if (v == 'groq') return openAI;
    for (final e in values) {
      if (e.value == v) return e;
    }
    return openAI;
  }
}

// ---------------------------------------------------------------------------
// After Transcription Action
// ---------------------------------------------------------------------------

/// What happens after successful transcription.
enum AfterTranscriptionAction {
  clipboard('clipboard'),
  paste('paste'),
  clipboardAndPaste('clipboard_and_paste'),
  nothing('nothing');

  const AfterTranscriptionAction(this.value);
  final String value;

  static AfterTranscriptionAction fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return clipboard;
  }
}

// ---------------------------------------------------------------------------
// Overlay Mode
// ---------------------------------------------------------------------------

/// Where the recording overlay is displayed.
enum OverlayMode {
  floating('floating'),
  off('off');

  const OverlayMode(this.value);
  final String value;

  static OverlayMode fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    // Migrate legacy 'in-window' → floating
    if (v == 'in-window') return floating;
    return floating;
  }
}

// ---------------------------------------------------------------------------
// Overlay Start Position
// ---------------------------------------------------------------------------

/// Where the floating overlay initially appears when recording starts.
///
/// [off] is a virtual entry used only in the consolidated start-position
/// dropdown to represent "overlay disabled" — it is never written to the
/// persisted [OverlaySettings.overlayStartPosition] field.
enum OverlayStartPosition {
  off('off'),
  topCenter('top-center'),
  bottomCenter('bottom-center'),
  lastPosition('last-position');

  const OverlayStartPosition(this.value);
  final String value;

  static OverlayStartPosition fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return topCenter;
  }
}

// ---------------------------------------------------------------------------
// Floating Overlay Size
// ---------------------------------------------------------------------------

/// Display size for the floating overlay window.
enum FloatingOverlaySize {
  normal('normal'),
  compact('compact');

  const FloatingOverlaySize(this.value);
  final String value;

  static FloatingOverlaySize fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return normal;
  }
}

// ---------------------------------------------------------------------------
// GPU Acceleration
// ---------------------------------------------------------------------------

/// GPU acceleration preference.
enum GpuAcceleration {
  auto('auto'),
  enabled('enabled'),
  disabled('disabled');

  const GpuAcceleration(this.value);
  final String value;
}
