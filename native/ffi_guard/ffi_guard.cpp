// ffi_guard.cpp — see ffi_guard.h. Must be built with an exception model
// that lets a catch clause see exceptions thrown through extern "C"
// functions (MSVC /EHs, not /EHsc: under /EHsc the compiler assumes extern
// "C" callees never throw and may drop the handlers below).
#include "ffi_guard.h"

#include <atomic>
#include <cstdint>
#include <cstring>
#include <exception>
#include <memory>
#include <mutex>
#include <string>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#endif

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

// Process-wide state for the ggml backend registry and the log sink. See
// ffi_guard.h. Kept here, not in Dart, because Dart statics are per isolate.
std::atomic<int> g_process_flags[4] = {};

// Ring buffer of ggml/whisper log lines. wpg_log_sink runs on whatever thread
// ggml logs from (including Vulkan/CUDA worker threads), so it takes a mutex,
// never blocks for long and never calls into Dart.
constexpr size_t kLogSlots = 256;
constexpr size_t kLogLineBytes = 512;
struct LogSlot {
  int level;
  char text[kLogLineBytes];
};
std::mutex g_log_mutex;
LogSlot g_log_slots[kLogSlots];
size_t g_log_head = 0;     // index of the oldest line
size_t g_log_count = 0;    // lines currently buffered
size_t g_log_dropped = 0;  // lines lost to a full buffer since last take
bool g_log_installed = false;

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

int wpg_call_void(wpg_void_void_fn fn, char* err, size_t err_len) {
  return guarded(err, err_len, [&] { fn(); });
}

int wpg_call_void_cstr(wpg_void_cstr_fn fn, const char* arg, char* err,
                       size_t err_len) {
  return guarded(err, err_len, [&] { fn(arg); });
}

int wpg_call_ptr_cstr(wpg_ptr_cstr_fn fn, const char* arg, void** out,
                      char* err, size_t err_len) {
  *out = nullptr;
  return guarded(err, err_len, [&] { *out = fn(arg); });
}

int wpg_call_cstr_void(wpg_cstr_void_fn fn, const char** out, char* err,
                       size_t err_len) {
  *out = nullptr;
  return guarded(err, err_len, [&] { *out = fn(); });
}

int wpg_call_cstr_ptr(wpg_cstr_ptr_fn fn, const void* arg, const char** out,
                      char* err, size_t err_len) {
  *out = nullptr;
  return guarded(err, err_len, [&] { *out = fn(arg); });
}

int wpg_call_size_void(wpg_size_void_fn fn, size_t* out, char* err,
                       size_t err_len) {
  *out = 0;
  return guarded(err, err_len, [&] { *out = fn(); });
}

int wpg_call_ptr_size(wpg_ptr_size_fn fn, size_t index, void** out, char* err,
                      size_t err_len) {
  *out = nullptr;
  return guarded(err, err_len, [&] { *out = fn(index); });
}

int wpg_call_int_ptr(wpg_int_ptr_fn fn, const void* arg, int* out, char* err,
                     size_t err_len) {
  *out = 0;
  return guarded(err, err_len, [&] { *out = fn(arg); });
}

extern "C++" {
namespace {

using score_fn = int (*)(void);

// Closes a module handle on scope exit, also when the score call throws.
struct module_closer {
  void operator()(void* handle) const {
#if defined(_WIN32)
    FreeLibrary(static_cast<HMODULE>(handle));
#else
    dlclose(handle);
#endif
  }
};
using module_handle = std::unique_ptr<void, module_closer>;

// Returns null when the module cannot be opened.
module_handle open_module(const char* path) {
#if defined(_WIN32)
  const int wide_len = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
  if (wide_len <= 0) return nullptr;
  std::wstring wide(static_cast<size_t>(wide_len), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path, -1, &wide[0], wide_len);
  return module_handle(static_cast<void*>(LoadLibraryW(wide.c_str())));
#else
  return module_handle(dlopen(path, RTLD_NOW | RTLD_LOCAL));
#endif
}

void* find_symbol(void* handle, const char* name) {
#if defined(_WIN32)
  return reinterpret_cast<void*>(
      GetProcAddress(static_cast<HMODULE>(handle), name));
#else
  return dlsym(handle, name);
#endif
}

}  // namespace
}  // extern "C++"

int wpg_backend_score(const char* path, int* out_score, char* err,
                      size_t err_len) {
  *out_score = 0;
  return guarded(err, err_len, [&] {
    if (path == nullptr) return;
    module_handle module = open_module(path);
    if (!module) return;
    void* sym = find_symbol(module.get(), "ggml_backend_score");
    if (sym == nullptr) {
      *out_score = 1;  // the module exports no score: counts as supported
      return;
    }
    *out_score = reinterpret_cast<score_fn>(sym)();
  });
}

int wpg_process_flag_get(int which) {
  if (which < 0 || which >= 4) return 0;
  return g_process_flags[which].load();
}

void wpg_process_flag_set(int which, int value) {
  if (which < 0 || which >= 4) return;
  g_process_flags[which].store(value);
}

void wpg_log_sink(int level, const char* text, void* /*user_data*/) {
  try {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    if (g_log_count == kLogSlots) {
      g_log_head = (g_log_head + 1) % kLogSlots;
      --g_log_count;
      ++g_log_dropped;
    }
    LogSlot& slot = g_log_slots[(g_log_head + g_log_count) % kLogSlots];
    slot.level = level;
    if (text == nullptr) text = "";
    std::strncpy(slot.text, text, kLogLineBytes - 1);
    slot.text[kLogLineBytes - 1] = '\0';
    // ggml lines end in '\n'; the Dart side logs one record per line.
    size_t n = std::strlen(slot.text);
    while (n > 0 && (slot.text[n - 1] == '\n' || slot.text[n - 1] == '\r')) {
      slot.text[--n] = '\0';
    }
    ++g_log_count;
  } catch (...) {
    // Logging must never throw into ggml.
  }
}

int wpg_log_install(wpg_log_set_fn fn, char* err, size_t err_len) {
  return guarded(err, err_len, [&] {
    std::lock_guard<std::mutex> lock(g_log_mutex);
    if (g_log_installed || fn == nullptr) return;
    fn(&wpg_log_sink, nullptr);
    g_log_installed = true;
  });
}

int wpg_log_pop(int* level, char* text, size_t text_len) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  if (g_log_count == 0) return 0;
  const LogSlot& slot = g_log_slots[g_log_head];
  if (level != nullptr) *level = slot.level;
  if (text != nullptr && text_len > 0) {
    std::strncpy(text, slot.text, text_len - 1);
    text[text_len - 1] = '\0';
  }
  g_log_head = (g_log_head + 1) % kLogSlots;
  --g_log_count;
  return 1;
}

size_t wpg_log_take_dropped(void) {
  std::lock_guard<std::mutex> lock(g_log_mutex);
  size_t dropped = g_log_dropped;
  g_log_dropped = 0;
  return dropped;
}

}  // extern "C"
