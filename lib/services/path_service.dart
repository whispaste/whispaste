/// Cross-platform path helpers for WhisPaste app data and STT assets.
///
/// This file is the app-layer adapter for `package:whispaste_diagnostics`.
/// All logic lives in the pure-Dart package; this file re-exports it
/// and preserves the existing import path for app-side callers.
library;

export 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show
        appDataDirOverride,
        sttDirOverride,
        retainedAudioDirOverride,
        modelFilenames,
        resolveModelFilename,
        appDataDir,
        appDataFolderName,
        isLocalBuild,
        sttDir,
        retainedAudioDir,
        whisperServerPath,
        sttModelPath;

import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show appDataDir, retainedAudioDir;

/// Scratch root for audio imports (decoded and copied source files of
/// in-flight jobs). Derived from [appDataDir], so it follows the same
/// sandbox/MSIX-redirected location as every other app data path.
String importsRootDir() => p.join(appDataDir(), 'imports');

/// Paths the forgot-PIN wipe could not remove, applied at the next start.
String pendingWipeFile() => p.join(appDataDir(), 'pending-wipe.json');

/// Audio of dictations whose history save failed, kept until a retry in a
/// later session succeeds (see `PendingAudioQueue`).
String pendingAudioDir() => p.join(appDataDir(), 'pending-audio');

/// Every directory that holds user audio. Single source for all factory-reset
/// entry points (UI coordinator and the monolithic reset): retained WAVs and
/// their recovery journal, import scratch copies of source files, and audio
/// waiting for a history save.
List<String> userAudioDirectories() => [
  retainedAudioDir(),
  importsRootDir(),
  pendingAudioDir(),
];
