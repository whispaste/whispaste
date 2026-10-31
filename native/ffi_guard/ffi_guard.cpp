// ffi_guard.cpp — see ffi_guard.h. Must be built with an exception model
// that lets a catch clause see exceptions thrown through extern "C"
// functions (MSVC /EHs, not /EHsc: under /EHsc the compiler assumes extern
// "C" callees never throw and may drop the handlers below).
#include "ffi_guard.h"

#include <cstdint>
#include <cstring>
#include <exception>

namespace {

void write_error(char* err, size_t err_len, const char* msg) {
  if (err == nullptr || err_len == 0) return;
  if (msg == nullptr) msg = "";
  std::strncpy(err, msg, err_len - 1);
  err[err_len - 1] = '\0';
}

template <typename F>
int guarded(char* err, size_t err_len, F&& body) {
  write_error(err, err_len, "");
  try {
    body();
    return WPG_OK;
  } catch (const std::exception& e) {
    write_error(err, err_len, e.what());
    return WPG_STD_EXCEPTION;
  } catch (...) {
    write_error(err, err_len, "unknown C++ exception");
    return WPG_UNKNOWN_EXCEPTION;
  }
}

}  // namespace

extern "C" {

int wpg_abi_version(void) { return WPG_ABI_VERSION; }

size_t wpg_sizeof_whisper_context_params(void) {
  return sizeof(struct whisper_context_params);
}

size_t wpg_sizeof_whisper_full_params(void) {
  return sizeof(struct whisper_full_params);
}

int wpg_whisper_init_from_file(wpg_whisper_init_from_file_fn fn,
                               const char* path,
                               const struct whisper_context_params* params,
                               struct whisper_context** out_ctx, char* err,
                               size_t err_len) {
  *out_ctx = nullptr;
  return guarded(err, err_len, [&] { *out_ctx = fn(path, *params); });
}

int wpg_whisper_init_state(wpg_whisper_init_state_fn fn,
                           struct whisper_context* ctx,
                           struct whisper_state** out_state, char* err,
                           size_t err_len) {
  *out_state = nullptr;
  return guarded(err, err_len, [&] { *out_state = fn(ctx); });
}

int wpg_whisper_full(wpg_whisper_full_fn fn, struct whisper_context* ctx,
                     const struct whisper_full_params* params,
                     const float* samples, int n_samples, int* out_rc,
                     char* err, size_t err_len) {
  *out_rc = -1;
  return guarded(err, err_len,
                 [&] { *out_rc = fn(ctx, *params, samples, n_samples); });
}

int wpg_whisper_full_with_state(wpg_whisper_full_with_state_fn fn,
                                struct whisper_context* ctx,
                                struct whisper_state* state,
                                const struct whisper_full_params* params,
                                const float* samples, int n_samples,
                                int* out_rc, char* err, size_t err_len) {
  *out_rc = -1;
  return guarded(err, err_len, [&] {
    *out_rc = fn(ctx, state, *params, samples, n_samples);
  });
}

bool wpg_abort_flag_cb(void* flag) {
  if (flag == nullptr) return false;
#if defined(_MSC_VER)
  return *static_cast<volatile const int32_t*>(flag) != 0;
#else
  return __atomic_load_n(static_cast<const int32_t*>(flag),
                         __ATOMIC_RELAXED) != 0;
#endif
}

int wpg_call_void_pp(wpg_void_pp_fn fn, const void* a, const void* b,
                     char* err, size_t err_len) {
  return guarded(err, err_len, [&] { fn(a, b); });
}

}  // extern "C"
