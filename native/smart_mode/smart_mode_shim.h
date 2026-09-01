// smart_mode_shim.h — the entire native surface Smart-Mode-v2's Dart FFI
// binding talks to. One call in, one call out: everything llama.cpp needs
// (model load, chat-template rendering with `enable_thinking`, tokenize,
// sampler chain, decode loop, detokenize) happens inside the shim, mirroring
// how whisper.h already gives WhisPaste's whisper_ffi_engine.dart a single
// `whisper_full()` entry point instead of exposing llama.cpp's much larger
// low-level C API directly to Dart.
#ifndef WHISPASTE_SMART_MODE_SHIM_H
#define WHISPASTE_SMART_MODE_SHIM_H

// MSVC (unlike clang/gcc's default "export everything" visibility on
// macOS/Linux, which is why this was never needed there) does not export a
// DLL's symbols unless told to: without this, `cl.exe /LD` silently produces
// a `smartmode_shim.dll` with zero exports, and `DynamicLibrary.lookup` on
// the Dart side fails with "procedure not found" even though the dylib
// loads fine.
#if defined(_WIN32)
#define WP_SMART_MODE_API __declspec(dllexport)
#else
#define WP_SMART_MODE_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Runs one Smart-Mode preset (Cleanup/Concise/Translate — the caller decides
// via `system_prompt`) against the GGUF model at `model_path`. Blocking,
// synchronous, loads and frees the model on every call — a prototype
// simplification; production keeps the model resident (see
// whisper_ffi_engine.dart's isolate-hosted long-lived context for the
// pattern this should eventually follow).
//
// Returns a heap-allocated, null-terminated UTF-8 string with the model's
// response, or NULL on failure (model/context/template init failure, decode
// error). Caller must release the result with smart_mode_free_result.
WP_SMART_MODE_API char* smart_mode_run(
    const char* model_path,
    const char* system_prompt,
    const char* user_text,
    int n_ctx,
    int n_gpu_layers,
    float temperature,
    float top_p,
    int top_k
);

// Frees a string previously returned by smart_mode_run. No-op on NULL.
WP_SMART_MODE_API void smart_mode_free_result(char* result);

#ifdef __cplusplus
}
#endif

#endif // WHISPASTE_SMART_MODE_SHIM_H
