// ffi_guard.h — catches C++ exceptions thrown by third-party native code
// (whisper.cpp/ggml incl. ggml-vulkan, sherpa-onnx/onnxruntime) before they
// reach a Dart FFI frame. An exception that unwinds into a Dart frame cannot
// be handled there and ends in std::terminate -> abort (Sentry 140866975,
// 135332054, 151627808); routed through this library it becomes an error
// code plus message that Dart turns into an ordinary exception.
//
// The library has no link-time dependency on whisper or sherpa-onnx: Dart
// resolves the target function itself and passes its address in `fn`, so
// the guard always calls exactly the symbol the app already loaded. Struct
// parameters that whisper.cpp takes by value are passed by pointer here
// (Dart FFI cannot portably forward a by-value struct through a C variadic
// shim) and dereferenced inside the guard.
#ifndef WHISPASTE_FFI_GUARD_H
#define WHISPASTE_FFI_GUARD_H

#if defined(_WIN32)
#define WPG_API __declspec(dllexport)
#else
#define WPG_API __attribute__((visibility("default")))
#endif

#include <stdbool.h>
#include <stddef.h>

#include "whisper.h"

#ifdef __cplusplus
extern "C" {
#endif

// Return codes of every guarded call. On a non-zero code `err` holds a
// NUL-terminated, truncated description of the exception.
#define WPG_OK 0
#define WPG_STD_EXCEPTION (-1)
#define WPG_UNKNOWN_EXCEPTION (-2)

// Bumped whenever an export's signature changes; Dart refuses a guard whose
// version it does not know and falls back to unguarded calls.
#define WPG_ABI_VERSION 1

WPG_API int wpg_abi_version(void);

// Size of the whisper.cpp structs this guard was compiled against. Dart
// compares them with its ffigen bindings and skips the whisper wrappers on a
// mismatch instead of copying a struct with the wrong layout.
WPG_API size_t wpg_sizeof_whisper_context_params(void);
WPG_API size_t wpg_sizeof_whisper_full_params(void);

typedef struct whisper_context* (*wpg_whisper_init_from_file_fn)(
    const char*, struct whisper_context_params);
typedef struct whisper_state* (*wpg_whisper_init_state_fn)(
    struct whisper_context*);
typedef int (*wpg_whisper_full_fn)(struct whisper_context*,
                                   struct whisper_full_params, const float*,
                                   int);
typedef int (*wpg_whisper_full_with_state_fn)(struct whisper_context*,
                                              struct whisper_state*,
                                              struct whisper_full_params,
                                              const float*, int);
typedef void (*wpg_void_pp_fn)(const void*, const void*);

WPG_API int wpg_whisper_init_from_file(
    wpg_whisper_init_from_file_fn fn, const char* path,
    const struct whisper_context_params* params,
    struct whisper_context** out_ctx, char* err, size_t err_len);

WPG_API int wpg_whisper_init_state(wpg_whisper_init_state_fn fn,
                                   struct whisper_context* ctx,
                                   struct whisper_state** out_state, char* err,
                                   size_t err_len);

WPG_API int wpg_whisper_full(wpg_whisper_full_fn fn,
                             struct whisper_context* ctx,
                             const struct whisper_full_params* params,
                             const float* samples, int n_samples, int* out_rc,
                             char* err, size_t err_len);

WPG_API int wpg_whisper_full_with_state(
    wpg_whisper_full_with_state_fn fn, struct whisper_context* ctx,
    struct whisper_state* state, const struct whisper_full_params* params,
    const float* samples, int n_samples, int* out_rc, char* err,
    size_t err_len);

// Generic `void fn(const void*, const void*)`, e.g.
// SherpaOnnxDecodeOfflineStream(recognizer, stream).
WPG_API int wpg_call_void_pp(wpg_void_pp_fn fn, const void* a, const void* b,
                             char* err, size_t err_len);

// whisper `abort_callback` (ggml_abort_callback shape): true once the int32
// at `flag` is non-zero. Dart owns the flag and raises it from another
// isolate (another thread) to cancel an in-flight decode, hence the atomic
// read. whisper.cpp polls it after the encoder and between decoder steps,
// so a raise mid-encoder takes effect once the encoder finishes.
WPG_API bool wpg_abort_flag_cb(void* flag);

// Test hook with the wpg_void_pp_fn shape, deliberately UNGUARDED and built
// in its own translation unit with the platform's default exception model
// (MSVC /EHsc, like the third-party DLLs): `*(const int*)kind` 0 returns
// normally, 1 throws std::runtime_error("wpg selftest"), 2 throws a
// non-std::exception type. Called through wpg_call_void_pp it exercises the
// exact production path; called directly from Dart it aborts the process.
WPG_API void wpg_selftest_throw(const void* kind, const void* unused);

#ifdef __cplusplus
}
#endif

#endif  // WHISPASTE_FFI_GUARD_H
