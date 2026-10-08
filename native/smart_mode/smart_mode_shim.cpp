// smart_mode_shim.cpp — see smart_mode_shim.h for the public surface.
//
// Pattern follows llama.cpp's own examples/simple-chat/simple-chat.cpp
// (model load -> context -> sampler chain -> tokenize/decode loop), extended
// with common/chat.h's Jinja-based chat-templating so `enable_thinking` is
// reachable — the exact switch the Smart-Mode-v2 spike test (see
// .scratch/smart-mode-v2/spike-test-results.md) found necessary for
// Gemma-4-E2B to answer fast AND correctly instead of stalling in an
// internal ~600-token "thinking" preamble.
#include "llama.h"
#include "chat.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "smart_mode_shim.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif defined(__linux__)
#include <dlfcn.h>
#endif

namespace {

bool g_backends_loaded = false;

void ensure_backends_loaded() {
  if (g_backends_loaded) return;
#if defined(_WIN32)
  // ggml_backend_load_all() (no explicit path) searches only the *executable's*
  // directory and the current working directory (see
  // ggml-backend-reg.cpp:get_executable_path(), which calls
  // GetModuleFileNameW(NULL, ...) -- NULL means "the process's .exe", not this
  // DLL). WhisPaste ships the ggml-cpu.dll/ggml-vulkan.dll backend plugins next
  // to smartmode_shim.dll under a smart_mode\ subfolder, not next to
  // whispaste.exe, so the default search finds nothing and every model load
  // fails with "no backends are loaded". Resolve *this* module's own directory
  // instead and pass it explicitly.
  HMODULE self_module = nullptr;
  if (GetModuleHandleExW(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
          reinterpret_cast<LPCWSTR>(&ensure_backends_loaded),
          &self_module)) {
    wchar_t path[MAX_PATH];
    DWORD len = GetModuleFileNameW(self_module, path, MAX_PATH);
    if (len > 0 && len < MAX_PATH) {
      std::wstring dir(path, len);
      auto last_slash = dir.find_last_of(L'\\');
      if (last_slash != std::wstring::npos) {
        dir = dir.substr(0, last_slash);
        int utf8_len = WideCharToMultiByte(CP_UTF8, 0, dir.c_str(), -1, nullptr, 0, nullptr, nullptr);
        if (utf8_len > 0) {
          std::string dir_utf8(static_cast<size_t>(utf8_len) - 1, '\0');
          WideCharToMultiByte(CP_UTF8, 0, dir.c_str(), -1, dir_utf8.data(), utf8_len, nullptr, nullptr);
          ggml_backend_load_all_from_path(dir_utf8.c_str());
          g_backends_loaded = true;
          return;
        }
      }
    }
  }
#elif defined(__linux__)
  // Same problem on Linux: ggml_backend_load_all() searches the directory of
  // /proc/self/exe (the Flutter bundle root) and the CWD, but the backend
  // modules (libggml-cpu-*.so, libggml-vulkan.so) ship next to this shim in
  // <bundle>/lib/smart_mode/ (see scripts/build-libllama-linux.sh). Scanning
  // exactly this directory also keeps ggml from ever picking up libwhisper's
  // own backend modules one level up in <bundle>/lib/.
  Dl_info info;
  if (dladdr(reinterpret_cast<void*>(&ensure_backends_loaded), &info) != 0 &&
      info.dli_fname != nullptr) {
    std::string path(info.dli_fname);
    auto last_slash = path.find_last_of('/');
    if (last_slash != std::string::npos) {
      ggml_backend_load_all_from_path(path.substr(0, last_slash).c_str());
      g_backends_loaded = true;
      return;
    }
  }
#endif
  ggml_backend_load_all();
  g_backends_loaded = true;
}

char* dup_cstr(const std::string& s) {
  char* out = static_cast<char*>(std::malloc(s.size() + 1));
  if (out == nullptr) return nullptr;
  std::memcpy(out, s.c_str(), s.size() + 1);
  return out;
}

bool is_aborted(const volatile int32_t* abort_flag) {
  return abort_flag != nullptr && *abort_flag != 0;
}

// llama.cpp's ggml_abort_callback: polled by the CPU backend during graph
// compute, so even a long prompt-processing llama_decode() stops early.
bool abort_callback(void* data) {
  return is_aborted(static_cast<const volatile int32_t*>(data));
}

}  // namespace

struct smart_mode_session {
  llama_model* model = nullptr;
  llama_context* ctx = nullptr;
  common_chat_templates_ptr tmpls;
};

extern "C" smart_mode_session* smart_mode_load(
    const char* model_path,
    int n_ctx,
    int n_gpu_layers
) {
  if (model_path == nullptr) return nullptr;

  llama_log_set(
      [](enum ggml_log_level level, const char* text, void*) {
        if (level >= GGML_LOG_LEVEL_ERROR) {
          std::fprintf(stderr, "[smart_mode_shim] %s", text);
        }
      },
      nullptr);

  ensure_backends_loaded();

  llama_model_params model_params = llama_model_default_params();
  model_params.n_gpu_layers = n_gpu_layers;

  llama_model* model = llama_model_load_from_file(model_path, model_params);
  if (model == nullptr) {
    std::fprintf(stderr, "[smart_mode_shim] failed to load model: %s\n", model_path);
    return nullptr;
  }

  llama_context_params ctx_params = llama_context_default_params();
  ctx_params.n_ctx = n_ctx;
  ctx_params.n_batch = n_ctx;

  llama_context* ctx = llama_init_from_model(model, ctx_params);
  if (ctx == nullptr) {
    std::fprintf(stderr, "[smart_mode_shim] failed to create context\n");
    llama_model_free(model);
    return nullptr;
  }

  auto* session = new smart_mode_session();
  session->model = model;
  session->ctx = ctx;
  session->tmpls = common_chat_templates_init(model, "");
  return session;
}

extern "C" char* smart_mode_generate(
    smart_mode_session* session,
    const char* system_prompt,
    const char* user_text,
    float temperature,
    float top_p,
    int top_k,
    const volatile int32_t* abort_flag
) {
  if (session == nullptr || user_text == nullptr) return nullptr;
  if (is_aborted(abort_flag)) return nullptr;

  llama_context* ctx = session->ctx;
  const llama_vocab* vocab = llama_model_get_vocab(session->model);

  // Every dictation starts from an empty KV cache — the session keeps the
  // model and context warm, never the previous conversation.
  llama_memory_clear(llama_get_memory(ctx), true);
  llama_set_abort_callback(ctx, abort_callback, const_cast<int32_t*>(abort_flag));

  // --- render the prompt via the model's own Jinja chat template ----------
  common_chat_templates_inputs inputs;
  inputs.add_generation_prompt = true;
  inputs.enable_thinking = false;  // validated in the spike test (see file doc comment).

  if (system_prompt != nullptr && system_prompt[0] != '\0') {
    common_chat_msg sys_msg;
    sys_msg.role = "system";
    sys_msg.content = system_prompt;
    inputs.messages.push_back(sys_msg);
  }
  common_chat_msg user_msg;
  user_msg.role = "user";
  user_msg.content = user_text;
  inputs.messages.push_back(user_msg);

  common_chat_params chat_params = common_chat_templates_apply(session->tmpls.get(), inputs);
  const std::string& prompt = chat_params.prompt;

  // --- sampler chain (temperature -> top_k -> top_p -> dist) ---------------
  llama_sampler* smpl = llama_sampler_chain_init(llama_sampler_chain_default_params());
  llama_sampler_chain_add(smpl, llama_sampler_init_top_k(top_k));
  llama_sampler_chain_add(smpl, llama_sampler_init_top_p(top_p, 1));
  llama_sampler_chain_add(smpl, llama_sampler_init_temp(temperature));
  llama_sampler_chain_add(smpl, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

  // --- tokenize --------------------------------------------------------------
  const int n_prompt_tokens =
      -llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), nullptr, 0, true, true);
  std::vector<llama_token> prompt_tokens(n_prompt_tokens);
  if (llama_tokenize(vocab, prompt.c_str(), static_cast<int32_t>(prompt.size()), prompt_tokens.data(),
                      static_cast<int32_t>(prompt_tokens.size()), true, true) < 0) {
    std::fprintf(stderr, "[smart_mode_shim] tokenize failed\n");
    llama_sampler_free(smpl);
    llama_set_abort_callback(ctx, nullptr, nullptr);
    return nullptr;
  }

  // --- decode loop -------------------------------------------------------
  std::string response;
  llama_batch batch = llama_batch_get_one(prompt_tokens.data(), static_cast<int32_t>(prompt_tokens.size()));
  llama_token new_token_id;
  const int max_new_tokens = 512;
  int n_generated = 0;
  bool aborted = false;

  while (true) {
    if (is_aborted(abort_flag)) {
      aborted = true;
      break;
    }

    const int ctx_size = llama_n_ctx(ctx);
    const int n_ctx_used = llama_memory_seq_pos_max(llama_get_memory(ctx), 0) + 1;
    if (n_ctx_used + batch.n_tokens > ctx_size) {
      std::fprintf(stderr, "[smart_mode_shim] context size exceeded\n");
      break;
    }

    if (llama_decode(ctx, batch) != 0) {
      aborted = is_aborted(abort_flag);
      if (!aborted) std::fprintf(stderr, "[smart_mode_shim] decode failed\n");
      break;
    }

    new_token_id = llama_sampler_sample(smpl, ctx, -1);
    if (llama_vocab_is_eog(vocab, new_token_id)) break;

    char piece[256];
    const int n = llama_token_to_piece(vocab, new_token_id, piece, sizeof(piece), 0, true);
    if (n < 0) {
      std::fprintf(stderr, "[smart_mode_shim] token_to_piece failed\n");
      break;
    }
    response.append(piece, n);

    if (++n_generated >= max_new_tokens) break;

    batch = llama_batch_get_one(&new_token_id, 1);
  }

  llama_sampler_free(smpl);
  llama_set_abort_callback(ctx, nullptr, nullptr);

  if (aborted) return nullptr;
  return dup_cstr(response);
}

extern "C" void smart_mode_unload(smart_mode_session* session) {
  if (session == nullptr) return;
  session->tmpls.reset();
  if (session->ctx != nullptr) llama_free(session->ctx);
  if (session->model != nullptr) llama_model_free(session->model);
  delete session;
}

extern "C" char* smart_mode_run(
    const char* model_path,
    const char* system_prompt,
    const char* user_text,
    int n_ctx,
    int n_gpu_layers,
    float temperature,
    float top_p,
    int top_k
) {
  if (model_path == nullptr || user_text == nullptr) return nullptr;
  smart_mode_session* session = smart_mode_load(model_path, n_ctx, n_gpu_layers);
  if (session == nullptr) return nullptr;
  char* result = smart_mode_generate(
      session, system_prompt, user_text, temperature, top_p, top_k, nullptr);
  smart_mode_unload(session);
  return result;
}

extern "C" void smart_mode_free_result(char* result) {
  std::free(result);
}
