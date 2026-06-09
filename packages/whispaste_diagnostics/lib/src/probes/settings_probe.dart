/// Settings snapshot probe — Provider/Model/Backend/Hotkey/After-Action.
///
/// Pure-Dart (no Flutter). The app layer reads the SharedPreferences / settings
/// object and passes a [SettingsSnapshot] into this probe's formatter. The
/// privacy sanitizer redacts all key/secret fields before they leave the
/// probe's boundary.
library;

import '../privacy/sanitizer.dart';

// ---------------------------------------------------------------------------
// Result model
// ---------------------------------------------------------------------------

/// A sanitized snapshot of WhisPaste settings relevant to diagnostics.
class SettingsSnapshotResult {
  const SettingsSnapshotResult({
    required this.sttProvider,
    required this.sttModel,
    required this.sttBackend,
    required this.hotkey,
    required this.afterAction,
    required this.apiKeyRedacted,
  });

  /// STT provider identifier (e.g. `onDevice`, `openAI`, `deepgram`).
  final String? sttProvider;

  /// Selected STT model ID (e.g. `whisper-small`, `nova-3`).
  final String? sttModel;

  /// Compute backend for onDevice STT (e.g. `cpu`, `cuda`, `vulkan`).
  final String? sttBackend;

  /// Hotkey string in display form (e.g. `Ctrl+Shift+D`).
  final String? hotkey;

  /// After-transcription action (`paste` or `clipboard`).
  final String? afterAction;

  /// `true` when an API key was present (but its value is NOT included).
  final bool apiKeyRedacted;
}

// ---------------------------------------------------------------------------
// Input struct (passed by the app layer — never touches the key values)
// ---------------------------------------------------------------------------

/// Raw settings fields passed from the app layer into [buildSettingsSnapshot].
///
/// The app reads these from SharedPreferences and fills this struct. Fields
/// that contain secrets (API keys) are never passed as plain strings — the
/// caller only sets [hasApiKey] to indicate presence.
class SettingsInput {
  const SettingsInput({
    this.sttProvider,
    this.sttModel,
    this.sttBackend,
    this.hotkey,
    this.afterAction,
    this.hasApiKey = false,
  });

  final String? sttProvider;
  final String? sttModel;
  final String? sttBackend;
  final String? hotkey;
  final String? afterAction;

  /// Whether a cloud API key is configured. The value is NEVER included.
  final bool hasApiKey;
}

// ---------------------------------------------------------------------------
// Builder (pure, testable)
// ---------------------------------------------------------------------------

/// Builds a [SettingsSnapshotResult] from [inputs].
///
/// Runs the sanitizer over all string fields to ensure no secrets or paths
/// leak. The sanitizer call here is defensive — [SettingsInput] design already
/// excludes key values, but belt-and-suspenders for any future extension.
SettingsSnapshotResult buildSettingsSnapshot(SettingsInput inputs) {
  String? sanitize(String? s) {
    if (s == null) return null;
    if (containsSensitiveData(s)) return '<redacted>';
    return sanitizePaths(s);
  }

  return SettingsSnapshotResult(
    sttProvider: sanitize(inputs.sttProvider),
    sttModel: sanitize(inputs.sttModel),
    sttBackend: sanitize(inputs.sttBackend),
    hotkey: sanitize(inputs.hotkey),
    afterAction: sanitize(inputs.afterAction),
    apiKeyRedacted: inputs.hasApiKey,
  );
}
