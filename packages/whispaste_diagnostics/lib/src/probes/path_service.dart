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

// ---------------------------------------------------------------------------
// MSIX child-process path de-virtualization (FLUTTER_WHISPASTE-A0)
// ---------------------------------------------------------------------------

/// Test seam: overrides the executable path used to detect an MSIX package and
/// derive its family name. Production reads [Platform.resolvedExecutable].
@visibleForTesting
String? resolvedExecutableOverride;

/// Derives the MSIX **Package Family Name** (`Name_PublisherId`) from a
/// `…\WindowsApps\<PackageFullName>\…` executable path, or `null` when the path
/// is not inside a WindowsApps package directory.
///
/// A package full name is `Name_Version_Arch_ResourceId_PublisherId` — the
/// ResourceId segment is usually empty, leaving a `__` before the publisher
/// hash (e.g. `12342SilvioLindstedt.WhisPaste_1.2.36.0_x64__phagqa3gq04kr`).
/// The family name keeps only the first (`Name`) and last (`PublisherId`)
/// segments. All logic is plain string handling so it is unit-testable off
/// Windows.
@visibleForTesting
String? msixPackageFamilyFromExePath(String exePath) {
  final normalized = exePath.replaceAll('/', r'\');
  const marker = r'\windowsapps\';
  final idx = normalized.toLowerCase().indexOf(marker);
  if (idx < 0) return null;
  final after = normalized.substring(idx + marker.length);
  final fullName = after.split(r'\').first;
  final parts = fullName.split('_');
  if (parts.length < 2) return null;
  final name = parts.first;
  final publisherId = parts.last;
  if (name.isEmpty || publisherId.isEmpty) return null;
  return '${name}_$publisherId';
}

/// Pure core of [deVirtualizeMsixChildPath] — every input is injected so the
/// mapping can be exercised cross-platform. Uses the Windows path style
/// unconditionally because MSIX is a Windows-only concept.
///
/// Returns [path] unchanged when [exePath] is not a WindowsApps package path,
/// either env var is missing, or [path] is not under `%APPDATA%\WhisPaste`.
@visibleForTesting
String deVirtualizeMsixChildPathFor({
  required String path,
  required String exePath,
  required String? appData,
  required String? localAppData,
}) {
  final family = msixPackageFamilyFromExePath(exePath);
  if (family == null) return path;
  if (appData == null || appData.isEmpty) return path;
  if (localAppData == null || localAppData.isEmpty) return path;

  final virtualRoot = p.windows.join(appData, 'WhisPaste');
  // Windows paths are case-insensitive; compare lower-cased.
  if (!path.toLowerCase().startsWith(virtualRoot.toLowerCase())) return path;

  final physicalRoot = p.windows.join(
    localAppData,
    'Packages',
    family,
    'LocalCache',
    'Roaming',
    'WhisPaste',
  );
  return '$physicalRoot${path.substring(virtualRoot.length)}';
}

/// Rewrites a logical WhisPaste data [path] (under the MSIX-virtualized
/// `%APPDATA%\WhisPaste` root) into the **physical** package-local path the
/// MSIX runtime redirects those writes to:
///
///     %APPDATA%\WhisPaste\…
///       → %LOCALAPPDATA%\Packages\`<PFN>`\LocalCache\Roaming\WhisPaste\…
///
/// The packaged parent process resolves the virtualized path transparently via
/// the runtime's AppData redirection. A spawned **non-packaged** child (the
/// downloaded `whisper-server.exe`) does **not** inherit that redirection — it
/// resolves the literal string against the un-virtualized filesystem, where the
/// real `%APPDATA%\WhisPaste` is empty. Passing the child the physical path
/// makes it resolve the model / binary / working-dir identically to the parent.
///
/// Field repro — FLUTTER_WHISPASTE-A0 (GTX 650, Microsoft Store / MSIX build):
/// whisper-server exits 3 with `ggml_backend_load_best: search path … does not
/// exist` and `whisper_init_from_file…: failed to open` the model, even though
/// the packaged app sees the file present and SHA-256-verified.
///
/// Returns [path] unchanged on non-Windows, on non-MSIX builds, or when [path]
/// is not under the `%APPDATA%\WhisPaste` root.
String deVirtualizeMsixChildPath(String path) {
  if (!Platform.isWindows) return path;
  return deVirtualizeMsixChildPathFor(
    path: path,
    exePath: resolvedExecutableOverride ?? Platform.resolvedExecutable,
    appData: Platform.environment['APPDATA'],
    localAppData: Platform.environment['LOCALAPPDATA'],
  );
}
