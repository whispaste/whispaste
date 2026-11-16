#include "inserted_span_reader.h"

#include <objbase.h>
#include <oleauto.h>
#include <uiautomation.h>
#include <windows.h>

#include <algorithm>

namespace inserted_span {

namespace {

// Upper bounds so a caller can never pull a large part of a document.
constexpr int kMaxExpectedChars = 4096;
constexpr int kMaxSlackChars = 256;
constexpr int kMaxAfterChars = kMaxExpectedChars + kMaxSlackChars;
// How far up from the focused element a text provider is looked for (Notepad
// can report a child element such as a detected hyperlink as focused).
constexpr int kMaxAncestorHops = 4;
// Bounds for a target that does not answer.
constexpr DWORD kConnectionTimeoutMs = 800;
constexpr DWORD kTransactionTimeoutMs = 800;
constexpr int kAttempts = 3;
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

std::wstring WithoutCr(const std::wstring& s) {
  std::wstring out;
  out.reserve(s.size());
  for (wchar_t c : s) {
    if (c != L'\r') out.push_back(c);
  }
  return out;
}

bool Contains(const std::wstring& text, const std::wstring& part) {
  return text.find(part) != std::wstring::npos;
}

Outcome Fail(const char* reason) {
  Outcome o;
  o.reason = reason;
  return o;
}

// Returns a degenerate range at the caret, or nothing.
bool CaretRange(IUIAutomationTextPattern* text, IUIAutomationTextPattern2* text2,
                ComPtr<IUIAutomationTextRange>& caret) {
  if (text2) {
    BOOL active = FALSE;
    // An inactive caret may sit at a stale spot; the selection is better then.
    if (SUCCEEDED(text2->GetCaretRange(&active, caret.Put())) && caret &&
        active) {
      return true;
    }
  }
  ComPtr<IUIAutomationTextRangeArray> selection;
  if (FAILED(text->GetSelection(selection.Put())) || !selection) return false;
  int count = 0;
  if (FAILED(selection->get_Length(&count)) || count < 1) return false;
  if (FAILED(selection->GetElement(0, caret.Put())) || !caret) return false;
  // Collapse onto the end of the selection: that is where the caret sits after
  // a paste.
  return SUCCEEDED(caret->MoveEndpointByRange(
      TextPatternRangeEndpoint_Start, caret.p, TextPatternRangeEndpoint_End));
}

Outcome ReadOnce(const std::wstring& expected_in, int slack_chars,
                 int after_chars) {
  const std::wstring expected = expected_in.size() > kMaxExpectedChars
                                    ? expected_in.substr(expected_in.size() -
                                                         kMaxExpectedChars)
                                    : expected_in;
  const int slack = std::clamp(slack_chars, 0, kMaxSlackChars);
  const int after = std::clamp(after_chars, 0, kMaxAfterChars);

  ComPtr<IUIAutomation> uia;
  if (FAILED(::CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                reinterpret_cast<void**>(uia.Put()))) &&
      FAILED(::CoCreateInstance(__uuidof(CUIAutomation), nullptr,
                                CLSCTX_INPROC_SERVER, __uuidof(IUIAutomation),
                                reinterpret_cast<void**>(uia.Put())))) {
    return Fail("uia_unavailable");
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
    return Fail("no_focus");
  }
  int pid = 0;
  if (SUCCEEDED(element->get_CurrentProcessId(&pid)) &&
      static_cast<DWORD>(pid) == ::GetCurrentProcessId()) {
    return Fail("own_window");
  }
  BOOL is_password = FALSE;
  if (FAILED(element->get_CurrentIsPassword(&is_password))) {
    return Fail("uia_error");
  }
  if (is_password) return Fail("password_field");

  ComPtr<IUIAutomationTreeWalker> walker;
  uia->get_ControlViewWalker(walker.Put());

  ComPtr<IUIAutomationTextPattern> text;
  ComPtr<IUIAutomationTextPattern2> text2;
  const char* pattern = "";
  for (int hop = 0; hop <= kMaxAncestorHops && element; ++hop) {
    if (SUCCEEDED(element->GetCurrentPatternAs(
            UIA_TextPattern2Id, __uuidof(IUIAutomationTextPattern2),
            reinterpret_cast<void**>(text2.Put()))) &&
        text2) {
      if (SUCCEEDED(text2->QueryInterface(
              __uuidof(IUIAutomationTextPattern),
              reinterpret_cast<void**>(text.Put()))) &&
          text) {
        pattern = "text_pattern2";
      }
    }
    if (!text && SUCCEEDED(element->GetCurrentPatternAs(
                     UIA_TextPatternId, __uuidof(IUIAutomationTextPattern),
                     reinterpret_cast<void**>(text.Put()))) &&
        text) {
      pattern = "text_pattern";
    }
    if (text) break;
    if (!walker) break;
    ComPtr<IUIAutomationElement> parent;
    if (FAILED(walker->GetParentElement(element.p, parent.Put())) || !parent) {
      break;
    }
    // A password ancestor (e.g. a custom secure field) is not read either.
    BOOL parent_password = FALSE;
    if (SUCCEEDED(parent->get_CurrentIsPassword(&parent_password)) &&
        parent_password) {
      return Fail("password_field");
    }
    element.Reset();
    element.p = parent.p;
    parent.p = nullptr;
  }
  if (!text) return Fail("no_text_pattern");

  ComPtr<IUIAutomationTextRange> range;
  if (!CaretRange(text.p, text2.p, range)) return Fail("no_caret");

  const int want = static_cast<int>(expected.size()) + slack;
  int moved = 0;
  if (FAILED(range->MoveEndpointByUnit(TextPatternRangeEndpoint_Start,
                                       TextUnit_Character, -want, &moved))) {
    return Fail("uia_error");
  }
  // Behind the caret too; the provider stops at the document end.
  int moved_after = 0;
  if (after > 0 &&
      FAILED(range->MoveEndpointByUnit(TextPatternRangeEndpoint_End,
                                       TextUnit_Character, after,
                                       &moved_after))) {
    return Fail("uia_error");
  }
  BSTR raw = nullptr;
  // MoveEndpointByUnit counts text units (clusters), GetText counts UTF-16
  // code units and cuts off the END of the range. Surrogate pairs and CRLF
  // therefore need headroom, or the tail that is compared would be lost.
  if (FAILED(range->GetText((want + after) * 2 + 16, &raw))) {
    return Fail("uia_error");
  }
  Outcome o;
  o.readable = true;
  o.reason = "ok";
  o.pattern = pattern;
  if (raw) {
    o.text.assign(raw, ::SysStringLen(raw));
    ::SysFreeString(raw);
  }
  o.matches_expected =
      !expected.empty() && Contains(WithoutCr(o.text), WithoutCr(expected));
  return o;
}

}  // namespace

Outcome Read(const std::wstring& expected, int slack_chars, int after_chars) {
  ComScope com;
  if (FAILED(com.hr) && com.hr != RPC_E_CHANGED_MODE) {
    return Fail("uia_unavailable");
  }
  // Chromium (Chrome, Edge, Electron) builds its accessibility tree only when
  // the first UIA client asks; that first answer is a bare placeholder without
  // a text provider or password flag. A short retry gets the real element.
  Outcome o;
  for (int attempt = 0; attempt < kAttempts; ++attempt) {
    if (attempt > 0) ::Sleep(kRetryDelayMs);
    o = ReadOnce(expected, slack_chars, after_chars);
    if (o.reason != "no_text_pattern" && o.reason != "no_focus") break;
  }
  return o;
}

}  // namespace inserted_span
