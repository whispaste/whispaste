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
#define WPG_ABI_VERSION 2

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

// ggml backend registry (ggml.h / whisper.h). Every call that loads or
// enumerates a backend goes through the guard: a backend module that throws
// (ggml-vulkan's vk::resultCheck, a driver that aborts with an exception) must
// come back as a NativeCallException, not unwind into a Dart frame.
typedef void (*wpg_void_void_fn)(void);
typedef void (*wpg_void_cstr_fn)(const char*);
typedef void* (*wpg_ptr_cstr_fn)(const char*);
typedef const char* (*wpg_cstr_void_fn)(void);
typedef size_t (*wpg_size_void_fn)(void);
typedef void* (*wpg_ptr_size_fn)(size_t);
typedef int (*wpg_int_ptr_fn)(const void*);
typedef const char* (*wpg_cstr_ptr_fn)(const void*);

// ggml_backend_load_all()
WPG_API int wpg_call_void(wpg_void_void_fn fn, char* err, size_t err_len);

// ggml_backend_load_all_from_path(dir)
WPG_API int wpg_call_void_cstr(wpg_void_cstr_fn fn, const char* arg, char* err,
                               size_t err_len);

// ggml_backend_load(path) -> reg (NULL when rejected), via *out
WPG_API int wpg_call_ptr_cstr(wpg_ptr_cstr_fn fn, const char* arg, void** out,
                              char* err, size_t err_len);

// whisper_print_system_info() / ggml_backend_dev_name(dev) style strings.
WPG_API int wpg_call_cstr_void(wpg_cstr_void_fn fn, const char** out, char* err,
                               size_t err_len);
WPG_API int wpg_call_cstr_ptr(wpg_cstr_ptr_fn fn, const void* arg,
                              const char** out, char* err, size_t err_len);

// ggml_backend_dev_count(), ggml_backend_dev_get(i), ggml_backend_dev_type(dev)
WPG_API int wpg_call_size_void(wpg_size_void_fn fn, size_t* out, char* err,
                               size_t err_len);
WPG_API int wpg_call_ptr_size(wpg_ptr_size_fn fn, size_t index, void** out,
                              char* err, size_t err_len);
WPG_API int wpg_call_int_ptr(wpg_int_ptr_fn fn, const void* arg, int* out,
                             char* err, size_t err_len);

// Scores the ggml backend module at `path` without leaving it loaded: opens
// it, reads `ggml_backend_score()` and closes it again. *out_score is the
// score, 1 when the module exports no score, 0 when it cannot be opened.
// Opening runs the module's static initialisers (vendor driver code), so it
// goes through the guard like every other ggml call.
WPG_API int wpg_backend_score(const char* path, int* out_score, char* err,
                              size_t err_len);

// Process-wide flags. ggml's backend registry is process-wide, but the Dart
// statics that remember "already loaded" are per isolate: a worker isolate
// started after Isolate.exit would load every backend module again. The
// flags live here instead. Values are owned by the caller (Dart).
#define WPG_FLAG_BACKENDS 1  // 0 none, 1 CPU module only, 2 all modules
#define WPG_FLAG_CUDA_PACK 2  // 0 not attempted, 1 attempted
WPG_API int wpg_process_flag_get(int which);
WPG_API void wpg_process_flag_set(int which, int value);

// Process-wide ggml/whisper log sink. Installs `wpg_log_sink` through the
// target's `whisper_log_set(cb, user_data)` (passed as `fn`; the guard
// never links whisper). The sink copies each line into a fixed ring buffer
// that Dart drains with wpg_log_pop(); it never calls into Dart, so a log
// line from any thread at any time (also after a worker isolate has ended)
// is safe. Idempotent.
typedef void (*wpg_log_set_fn)(void (*cb)(int, const char*, void*), void*);
WPG_API int wpg_log_install(wpg_log_set_fn fn, char* err, size_t err_len);

// ggml_log_callback shape. Exported so tests can feed lines through the same
// code path as ggml.
WPG_API void wpg_log_sink(int level, const char* text, void* user_data);

// Pops the oldest buffered line. Returns 1 and fills `level` and `text`
// (truncated, NUL-terminated), or 0 when the buffer is empty.
WPG_API int wpg_log_pop(int* level, char* text, size_t text_len);

// Lines dropped because the ring was full since the last call; reset to 0.
WPG_API size_t wpg_log_take_dropped(void);

// Test hook with the wpg_void_pp_fn shape, deliberately UNGUARDED and built
// in its own translation unit with the platform's default exception model
// (MSVC /EHsc, like the third-party DLLs): `*(const int*)kind` 0 returns
// normally, 1 throws std::runtime_error("wpg selftest"), 2 throws a
// non-std::exception type. Called through wpg_call_void_pp it exercises the
// exact production path; called directly from Dart it aborts the process.
WPG_API void wpg_selftest_throw(const void* kind, const void* unused);

// Throwing hooks for the ggml-shaped wrappers above, same contract as
// wpg_selftest_throw: each throws std::runtime_error("wpg selftest") (or
// "wpg selftest: <arg>" for the string variant) from a nested frame.
WPG_API void wpg_selftest_throw_void(void);
WPG_API void wpg_selftest_throw_cstr(const char* arg);
WPG_API void* wpg_selftest_throw_ptr_cstr(const char* arg);

#ifdef __cplusplus
}
#endif

#endif  // WHISPASTE_FFI_GUARD_H
