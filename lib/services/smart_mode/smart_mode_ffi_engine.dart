/// Real in-process [SmartModeEngine] backed by a bundled `libllama` +
/// `libsmartmode_shim` via `dart:ffi` (llama.cpp b10150, Gemma-4-E2B-it).
/// Prototype sibling to [WhisperFfiEngine] — same bundling mechanism per
/// platform (macOS: Xcode "[WP] Embed & Sign libllama" phase, `../Frameworks/`
/// resolution, `@loader_path`-relocatable dylibs, Apple Guideline 2.5.2
/// no-runtime-code-download constraint; Windows: DLLs staged next to
/// `whispaste.exe` under a dedicated `smart_mode\` subdirectory, see
/// [smartModeLibraryPathFor]), but deliberately NOT isolate-hosted and NOT
/// persistent-context yet: [run] loads the ~2.9GB GGUF, generates once, and
/// frees everything on every call. That simplification is fine for
/// validating "does the bundled native engine work at all" — the next step
/// once this is proven is a long-lived context, following
/// whisper_isolate_engine.dart's pattern.
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/config/settings_enums.dart';
import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/windows_dll_search_path.dart';
import '../path_service.dart';
import 'smart_mode_engine.dart';
import 'smart_mode_openai_engine.dart';

final _log = AppLogger('SmartModeFfi');

typedef _SmartModeRunNative =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<Utf8> modelPath,
      ffi.Pointer<Utf8> systemPrompt,
      ffi.Pointer<Utf8> userText,
      ffi.Int32 nCtx,
      ffi.Int32 nGpuLayers,
      ffi.Float temperature,
      ffi.Float topP,
      ffi.Int32 topK,
    );
typedef _SmartModeRunDart =
    ffi.Pointer<Utf8> Function(
      ffi.Pointer<Utf8> modelPath,
      ffi.Pointer<Utf8> systemPrompt,
      ffi.Pointer<Utf8> userText,
      int nCtx,
      int nGpuLayers,
      double temperature,
      double topP,
      int topK,
    );
typedef _SmartModeFreeResultNative =
    ffi.Void Function(ffi.Pointer<Utf8> result);
typedef _SmartModeFreeResultDart = void Function(ffi.Pointer<Utf8> result);

/// Test-only override for the directory [smartModeModelPath] resolves
/// against, mirroring [sttDirOverride]. Must stay null in production code.
String? smartModeModelDirOverride;

/// `models/smart_mode/<filename>` under [appDataDir] — a sibling of
/// [sttDir], not reusing it, since Smart-Mode-v2 models are a distinct asset
/// class (chat/instruct GGUF, not Whisper encoder-decoder GGML) with their
/// own licensing/attribution surface (Apache 2.0, see
/// `.scratch/smart-mode-v2/research-gemma-4-e2b-license-and-config.md`).
String smartModeModelPath({String filename = 'gemma-4-E2B-it-Q4_K_M.gguf'}) =>
    p.join(
      smartModeModelDirOverride ?? p.join(appDataDir(), 'models', 'smart_mode'),
      filename,
    );

/// Absolute path to the bundled `libsmartmode_shim` shared library, resolved
/// relative to [Platform.resolvedExecutable] exactly like
/// [whisperLibraryPathFor].
String defaultSmartModeLibraryPath() =>
    smartModeLibraryPathFor(Platform.resolvedExecutable);

/// Pure resolver behind [defaultSmartModeLibraryPath], split out for unit
/// tests exactly like [whisperLibraryPathFor]. Given the app [executablePath],
/// returns the bundled `libsmartmode_shim` path for the current OS:
/// - macOS: `<App>.app/Contents/MacOS/<exe>` → `../Frameworks/libsmartmode_shim.dylib`
///   (embedded via the opt-in "[WP] Embed & Sign libllama" Xcode phase, see
///   `macos/embed_libllama.sh`).
/// - Windows: `smart_mode\smartmode_shim.dll` next to `whispaste.exe` — a
///   dedicated subdirectory, NOT the Flutter bundle root that
///   [whisperLibraryPathFor] uses. Reason: llama.cpp vendors its own copy of
///   `ggml` (see `build-libllama-windows.ps1`), independently pinned from
///   whisper.cpp's vendored copy and not guaranteed ABI-compatible with it —
///   staging both engines' `ggml*.dll` under the same directory would let one
///   silently overwrite/shadow the other's build. macOS avoids this by
///   renaming every ggml dylib with a `-llama` suffix instead (see
///   `build-libllama-macos.sh`); Windows instead keeps the two engines'
///   native libraries in disjoint directories, which needs no dylib-renaming
///   or relinking. Linux support is not part of this ticket.
String smartModeLibraryPathFor(String executablePath) {
  final execDir = p.dirname(executablePath);
  if (Platform.isMacOS) {
    return p.normalize(
      p.join(execDir, '..', 'Frameworks', 'libsmartmode_shim.dylib'),
    );
  }
  if (Platform.isWindows) {
    return p.join(execDir, 'smart_mode', 'smartmode_shim.dll');
  }
  throw UnsupportedError(
    'SmartModeFfiEngine is not bundled for this platform yet',
  );
}

class SmartModeFfiEngine implements SmartModeEngine {
  SmartModeFfiEngine({String? libraryPath, String? modelPath})
    : _libraryPath = libraryPath ?? defaultSmartModeLibraryPath(),
      _modelPath = modelPath ?? smartModeModelPath();

  final String _libraryPath;
  final String _modelPath;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    if (!File(_modelPath).existsSync()) {
      throw StateError('smart_mode_model_not_found: $_modelPath');
    }

    final ffi.DynamicLibrary dylib;
    try {
      ensureWindowsDllSearchPath(_libraryPath);
      dylib = ffi.DynamicLibrary.open(_libraryPath);
    } catch (e) {
      throw StateError('smart_mode_library_load_failed: $e');
    }

    final smartModeRun = dylib
        .lookupFunction<_SmartModeRunNative, _SmartModeRunDart>(
          'smart_mode_run',
        );
    final smartModeFreeResult = dylib
        .lookupFunction<_SmartModeFreeResultNative, _SmartModeFreeResultDart>(
          'smart_mode_free_result',
        );

    final modelPathC = _modelPath.toNativeUtf8();
    final systemPromptC = systemPrompt.toNativeUtf8();
    final userTextC = userText.toNativeUtf8();
    try {
      // Config validated in the spike test (spike-test-results.md):
      // temperature 0.3 / top_p 0.95 / top_k 64, `enable_thinking: false`
      // (baked into the shim itself, not a parameter here — see
      // smart_mode_shim.cpp).
      final resultPtr = smartModeRun(
        modelPathC,
        systemPromptC,
        userTextC,
        2048,
        99,
        0.3,
        0.95,
        64,
      );
      if (resultPtr == ffi.nullptr) {
        _log.warning('smart_mode_run returned NULL');
        throw StateError('smart_mode_run_failed');
      }
      final result = resultPtr.toDartString();
      smartModeFreeResult(resultPtr);
      return result;
    } finally {
      malloc.free(modelPathC);
      malloc.free(systemPromptC);
      malloc.free(userTextC);
    }
  }
}

/// Production [SmartModeEngine] — [RecordingOrchestrator] (ticket 02) reads
/// this via [Ref.read], never watches it: the engine is stateless per call,
/// so there is nothing to react to. Tests override this provider with a fake
/// implementing [SmartModeEngine] instead of constructing a real
/// [SmartModeFfiEngine] (which would `dlopen` a native library that doesn't
/// exist in the test environment).
///
/// Selects local vs. cloud per [SmartModeSettings.provider] (ticket 06,
/// ADR 0010: strict either-or, never both).
final smartModeEngineProvider = Provider<SmartModeEngine>((ref) {
  final providerType = SmartModeProviderType.fromValue(
    ref.watch(settingsProvider).value?.smartMode.provider,
  );
  return switch (providerType) {
    SmartModeProviderType.local => SmartModeFfiEngine(),
    SmartModeProviderType.openAI => SmartModeOpenAiEngine(ref: ref),
  };
});
