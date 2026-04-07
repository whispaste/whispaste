/// Cross-platform path helpers for WhisPaste app data and STT assets.
///
/// Extracted from `config_service.dart` so that services can resolve paths
/// without pulling in the Go config reader. All functions are pure
/// (no Riverpod, no async) — they derive paths from environment variables
/// and well-known directory conventions.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Model ID → GGML filename lookup (mirrors internal/models/models.go)
// ---------------------------------------------------------------------------

/// Maps Go model IDs to their on-disk GGML filenames.
const Map<String, String> modelFilenames = {
  'whisper-tiny': 'ggml-tiny-q5_1.bin',
  'whisper-base': 'ggml-base-q5_1.bin',
  'whisper-small': 'ggml-small-q5_1.bin',
  'whisper-medium': 'ggml-medium-q5_0.bin',
  'whisper-large-v3-turbo': 'ggml-large-v3-turbo-q5_0.bin',
  'whisper-large-v3': 'ggml-large-v3-q5_0.bin',
};

/// Falls back to scanning the STT directory for a matching `ggml-*.bin`
/// file if the ID is not in the known table — this covers custom models
/// that may have been added after this code was compiled.
String? resolveModelFilename(String modelId) {
  final known = modelFilenames[modelId];
  if (known != null) return known;

  // Fallback: scan the stt directory for a file whose stem contains the ID.
  try {
    final dir = Directory(sttDir());
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('ggml-') &&
            name.endsWith('.bin') &&
            name.contains(modelId)) {
          return name;
        }
      }
    }
  } on FileSystemException {
    // Can't scan — fall through to null.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// Returns the platform-specific WhisPaste app data directory.
///
/// - Windows: `%APPDATA%\WhisPaste`
/// - macOS: `~/Library/Application Support/WhisPaste`
/// - Linux: `$XDG_CONFIG_HOME/whispaste` or `~/.config/whispaste`
String appDataDir() {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError('APPDATA environment variable is not set');
    }
    return p.join(appData, 'WhisPaste');
  }
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'] ?? '';
    return p.join(home, 'Library', 'Application Support', 'WhisPaste');
  }
  // Linux / other Unix
  final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
  if (xdgConfig != null && xdgConfig.isNotEmpty) {
    return p.join(xdgConfig, 'whispaste');
  }
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.config', 'whispaste');
}

/// Directory containing STT model files and whisper-server.
String sttDir() => p.join(appDataDir(), 'models', 'stt');

/// Full path to the whisper-server executable.
String whisperServerPath() {
  final name = Platform.isWindows ? 'whisper-server.exe' : 'whisper-server';
  return p.join(sttDir(), name);
}

/// Full path to the GGML model file for [modelId].
///
/// Returns `null` if the model ID is not in the lookup table.
String? sttModelPath(String modelId) {
  final filename = resolveModelFilename(modelId);
  if (filename == null) return null;
  return p.join(sttDir(), filename);
}
