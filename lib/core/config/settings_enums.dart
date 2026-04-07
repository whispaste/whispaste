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
  onDevice('On Device (Private)'),
  openAI('OpenAI'),
  groq('Groq'),
  deepgram('Deepgram');

  const SttProviderType(this.value);

  /// The string persisted in SQLite and shown in dropdowns.
  final String value;

  /// Look up by persisted [value]. Falls back to [onDevice].
  static SttProviderType fromValue(String? v) {
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
  groq('groq'),
  deepgram('deepgram');

  const CloudSttProvider(this.value);
  final String value;

  static CloudSttProvider fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return openAI;
  }
}

// ---------------------------------------------------------------------------
// Post-Processing Provider
// ---------------------------------------------------------------------------

/// LLM provider for post-processing.
enum PostProcessProviderType {
  local('Local'),
  openAI('OpenAI'),
  anthropic('Anthropic'),
  groq('Groq'),
  gemini('Gemini');

  const PostProcessProviderType(this.value);
  final String value;

  static PostProcessProviderType fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return local;
  }

  bool get isLocal => this == local;
}

// ---------------------------------------------------------------------------
// Post-Processing Preset
// ---------------------------------------------------------------------------

/// Built-in post-processing presets.
enum PostProcessPreset {
  cleanup('Clean up', 'cleanup'),
  concise('Concise', 'concise'),
  translate('Translate', 'translate');

  const PostProcessPreset(this.displayValue, this.goKey);

  /// Display name shown in UI dropdowns.
  final String displayValue;

  /// Key used in Go backend communication.
  final String goKey;

  static PostProcessPreset fromDisplayValue(String? v) {
    for (final e in values) {
      if (e.displayValue == v) return e;
    }
    return cleanup;
  }

  static PostProcessPreset fromGoKey(String? v) {
    for (final e in values) {
      if (e.goKey == v) return e;
    }
    return cleanup;
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
  inWindow('in-window'),
  floating('floating'),
  off('off');

  const OverlayMode(this.value);
  final String value;

  static OverlayMode fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return inWindow;
  }
}

// ---------------------------------------------------------------------------
// Floating Button Size
// ---------------------------------------------------------------------------

/// Floating button size presets.
enum FloatingButtonSize {
  small('small', 48),
  normal('normal', 56),
  large('large', 72);

  const FloatingButtonSize(this.value, this.pixels);
  final String value;
  final int pixels;

  static FloatingButtonSize fromValue(String? v) {
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

  static GpuAcceleration fromValue(String? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return auto;
  }
}
