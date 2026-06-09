/// Cross-platform path helpers for WhisPaste app data and STT assets.
///
/// Pure-Dart (no Flutter, no Riverpod). All functions are synchronous —
/// they derive paths from environment variables and well-known directory
/// conventions.
library;

import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Override the STT directory for testing. When non-null, [sttDir] returns
/// this value instead of the real AppData path, isolating tests from the
/// host file system.
@visibleForTesting
String? sttDirOverride;

// ---------------------------------------------------------------------------
// Model ID → GGML filename lookup
// ---------------------------------------------------------------------------

/// Maps model IDs to their on-disk GGML filenames.
const Map<String, String> modelFilenames = {
  'whisper-small': 'ggml-small-q5_1.bin',
  'whisper-medium': 'ggml-medium-q5_0.bin',
  'whisper-large-v3-turbo': 'ggml-large-v3-turbo-q5_0.bin',
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
String sttDir() => sttDirOverride ?? p.join(appDataDir(), 'models', 'stt');

/// Full path to the whisper-server executable.
///
/// On macOS, checks the app bundle first (`Contents/Helpers/whisper-server`)
/// for App Store builds where the binary is bundled at build time. Falls back
/// to the downloaded path in Application Support.
String whisperServerPath() {
  final name = Platform.isWindows ? 'whisper-server.exe' : 'whisper-server';

  // Check app bundle first (macOS App Store distribution bundles the binary).
  if (Platform.isMacOS) {
    final exe = Platform.resolvedExecutable;
    final contentsDir = p.dirname(p.dirname(exe)); // .app/Contents/
    final bundledPath = p.join(contentsDir, 'Helpers', name);
    if (File(bundledPath).existsSync()) {
      return bundledPath;
    }
  }

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
