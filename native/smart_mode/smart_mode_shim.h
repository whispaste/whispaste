// smart_mode_shim.h — the entire native surface Smart-Mode-v2's Dart FFI
// binding talks to. A small session API (load / generate / unload):
// everything llama.cpp needs (model load, chat-template rendering with
// `enable_thinking`, tokenize, sampler chain, decode loop, detokenize)
// happens inside the shim, mirroring how whisper.h gives WhisPaste's
// whisper_ffi_engine.dart a handful of entry points instead of exposing
// llama.cpp's much larger low-level C API directly to Dart.
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

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque, long-lived Smart-Mode session: the loaded model, its context and
// the rendered chat templates. Created once by smart_mode_load and reused by
// every smart_mode_generate call until smart_mode_unload, so the ~2.9GB GGUF
// is read from disk once per warm window instead of once per call. Owned by
// exactly one thread at a time (WhisPaste's Smart-Mode worker isolate).
typedef struct smart_mode_session smart_mode_session;

// Loads the GGUF model at `model_path` and creates a context of `n_ctx`
// tokens. Returns NULL on failure (model/context init failure).
WP_SMART_MODE_API smart_mode_session* smart_mode_load(
    const char* model_path,
    int n_ctx,
    int n_gpu_layers
);

// Runs one Smart-Mode preset (Cleanup/Concise/Translate — the caller decides
// via `system_prompt`) against `user_text` on an already loaded session.
// Blocking. Each call starts from an empty KV cache (no state leaks between
// dictations).
//
// `abort_flag` (may be NULL) is polled before every decoded token and by
// llama.cpp's own abort callback during prompt processing: once another
// thread sets it to a non-zero value, generation stops and NULL is
// returned. The session stays loaded and usable after an abort.
//
// Returns a heap-allocated, null-terminated UTF-8 string with the model's
// response, or NULL on failure/abort. Caller must release the result with
// smart_mode_free_result.
WP_SMART_MODE_API char* smart_mode_generate(
    smart_mode_session* session,
    const char* system_prompt,
    const char* user_text,
    float temperature,
    float top_p,
    int top_k,
    const volatile int32_t* abort_flag
);

// Frees the model, context and templates of `session`. No-op on NULL.
WP_SMART_MODE_API void smart_mode_unload(smart_mode_session* session);

// One-shot convenience: load + generate + unload in a single call (the
// original prototype surface, kept for main_smart_mode_debug.dart-style
// callers). Returns NULL on failure.
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

// Frees a string previously returned by smart_mode_generate/smart_mode_run.
// No-op on NULL.
WP_SMART_MODE_API void smart_mode_free_result(char* result);

#ifdef __cplusplus
}
#endif

#endif // WHISPASTE_SMART_MODE_SHIM_H
