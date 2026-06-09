/// Cross-platform path helpers for WhisPaste app data and STT assets.
///
/// This file is the app-layer adapter for `package:whispaste_diagnostics`.
/// All logic lives in the pure-Dart package; this file re-exports it
/// and preserves the existing import path for app-side callers.
library;

export 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show
        sttDirOverride,
        modelFilenames,
        resolveModelFilename,
        appDataDir,
        sttDir,
        whisperServerPath,
        sttModelPath;
