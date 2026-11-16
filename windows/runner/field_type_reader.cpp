#include "field_type_reader.h"

#include <objbase.h>
#include <uiautomation.h>
#include <windows.h>

namespace field_type {

namespace {

constexpr char kPassword[] = "password";
constexpr char kNormal[] = "normal";
constexpr char kUnknown[] = "unknown";

// A custom secure field can report a child element as focused.
constexpr int kMaxAncestorHops = 4;
// The paste waits only briefly for the answer, so a slow target ends early.
constexpr DWORD kConnectionTimeoutMs = 500;
constexpr DWORD kTransactionTimeoutMs = 500;
constexpr int kAttempts = 2;
constexpr DWORD kRetryDelayMs = 100;

template <typename T>
struct ComPtr {
  T* p = nullptr;
  ComPtr() = default;
  ComPtr(const ComPtr&) = delete;
  ComPtr& operator=(const ComPtr&) = delete;
  ~ComPtr() { Reset(); }
  void Reset() {
    if (p) p->Release();
    p = nullptr;
  }
  T** Put() {
    Reset();
    return &p;
  }
  T* operator->() const { return p; }
  explicit operator bool() const { return p != nullptr; }
};

struct ComScope {
  HRESULT hr;
  ComScope() : hr(::CoInitializeEx(nullptr, COINIT_MULTITHREADED)) {}
  ~ComScope() {
    if (SUCCEEDED(hr)) ::CoUninitialize();
  }
};

struct Attempt {
  const char* type = kUnknown;
  // True when a later attempt may know more (Chromium placeholder element).
  bool retry = false;
};

bool IsPassword(IUIAutomationElement* element) {
  BOOL is_password = FALSE;
  return SUCCEEDED(element->get_CurrentIsPassword(&is_password)) &&
         is_password;
}

// Only the availability of the pattern, never its content.
bool HasTextOrValuePattern(IUIAutomationElement* element) {
  const PATTERNID ids[] = {UIA_TextPatternId, UIA_ValuePatternId};
  for (PATTERNID id : ids) {
    ComPtr<IUnknown> pattern;
    if (SUCCEEDED(element->GetCurrentPattern(id, pattern.Put())) && pattern) {
      return true;
    }
  }
  return false;
}

Attempt ReadOnce() {
  Attempt a;
  ComPtr<IUIAutomation> uia;
  if (FAILED(::CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                reinterpret_cast<void**>(uia.Put()))) &&
      FAILED(::CoCreateInstance(__uuidof(CUIAutomation), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                reinterpret_cast<void**>(uia.Put())))) {
    return a;
  }
  {
    ComPtr<IUIAutomation2> uia2;
    if (SUCCEEDED(uia->QueryInterface(__uuidof(IUIAutomation2),
                                      reinterpret_cast<void**>(uia2.Put())))) {
      uia2->put_ConnectionTimeout(kConnectionTimeoutMs);
      uia2->put_TransactionTimeout(kTransactionTimeoutMs);
    }
  }

  ComPtr<IUIAutomationElement> element;
  if (FAILED(uia->GetFocusedElement(element.Put())) || !element) {
    a.retry = true;
    return a;
  }
  int pid = 0;
  if (SUCCEEDED(element->get_CurrentProcessId(&pid)) &&
      static_cast<DWORD>(pid) == ::GetCurrentProcessId()) {
    return a;
  }
  BOOL is_password = FALSE;
  if (FAILED(element->get_CurrentIsPassword(&is_password))) return a;
  if (is_password) {
    a.type = kPassword;
    return a;
  }
  // "normal" needs proof: a text or value provider. Chromium answers the very
  // first client with a bare placeholder that has neither.
  const bool text_field = HasTextOrValuePattern(element.p);

  ComPtr<IUIAutomationTreeWalker> walker;
  uia->get_ControlViewWalker(walker.Put());
  for (int hop = 0; hop < kMaxAncestorHops && walker; ++hop) {
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(element.p, parent.Put())) || !parent) {
      break;
    }
    if (IsPassword(parent.p)) {
      a.type = kPassword;
      return a;
    }
    element.Reset();
    element.p = parent.p;
    parent.p = nullptr;
  }
  if (text_field) {
    a.type = kNormal;
  } else {
    a.retry = true;
  }
  return a;
}

}  // namespace

std::string Read() {
  ComScope com;
  if (FAILED(com.hr) && com.hr != RPC_E_CHANGED_MODE) return kUnknown;
  Attempt a;
  for (int attempt = 0; attempt < kAttempts; ++attempt) {
    if (attempt > 0) ::Sleep(kRetryDelayMs);
    a = ReadOnce();
    if (!a.retry) break;
  }
  return a.type;
}

}  // namespace field_type
