// Test of the Windows receipt render decision (clipboard_receipt_policy.h).
// Platform-neutral C++17; run via test/scripts/clipboard_receipt_policy_test.sh.
#include "clipboard_receipt_policy.h"

#include <cstdio>
#include <string>
#include <vector>

namespace {
int failures = 0;
void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

constexpr uint32_t kOwn = 100;
constexpr uint32_t kTarget = 200;
constexpr uint32_t kMonitor = 300;
}  // namespace

int main() {
  // The reported bug: a monitor read before the keystroke took the one
  // render, so the target's paste gave no receipt. It must keep it.
  Expect(DecideReceiptRender(true, false, kMonitor, kOwn, kTarget) ==
             ReceiptRender::kDecline,
         "a foreign monitor before the keystroke does not take the render");
  Expect(DecideReceiptRender(true, true, kTarget, kOwn, kTarget) ==
             ReceiptRender::kRenderRead,
         "the target's read after the keystroke is the receipt");
  Expect(DecideReceiptRender(true, true, kMonitor, kOwn, kTarget) ==
             ReceiptRender::kRenderRead,
         "any read after the keystroke still renders and counts, as before");

  // Readers that might be the paste itself always get the text.
  Expect(DecideReceiptRender(true, false, kTarget, kOwn, kTarget) ==
             ReceiptRender::kRenderPreRead,
         "the target's own early read renders");
  Expect(DecideReceiptRender(true, false, 0, kOwn, kTarget) ==
             ReceiptRender::kRenderPreRead,
         "an unnamed reader renders");
  Expect(DecideReceiptRender(true, false, kOwn, kOwn, kTarget) ==
             ReceiptRender::kRenderPreRead,
         "WhisPaste's own read renders");
  Expect(DecideReceiptRender(true, false, kMonitor, kOwn, 0) ==
             ReceiptRender::kRenderPreRead,
         "without a known target nothing is declined");

  Expect(DecideReceiptRender(false, false, kMonitor, kOwn, kTarget) ==
             ReceiptRender::kRender,
         "no armed receipt: plain render");
  Expect(DecideReceiptRender(false, true, kMonitor, kOwn, kTarget) ==
             ReceiptRender::kRender,
         "no armed receipt after the keystroke: plain render");

  // Naming early readers for the receipt log (diagnostics only).
  Expect(ExeBaseName(L"C:\\Program Files\\Ditto\\Ditto.exe") == L"Ditto.exe",
         "only the file name of a Windows path");
  Expect(ExeBaseName(L"C:\\Users\\someone\\AppData\\clip.exe") == L"clip.exe",
         "the user folder never reaches the log");
  Expect(ExeBaseName(L"tool.exe") == L"tool.exe", "a bare name stays");
  Expect(ExeBaseName(L"") == L"", "an empty path stays empty");

  std::vector<std::wstring> readers;
  Expect(JoinEarlyReaders(readers) == L"none", "no early reader: none");
  NoteEarlyReader(&readers, L"Ditto.exe");
  NoteEarlyReader(&readers, L"Ditto.exe");
  NoteEarlyReader(&readers, L"");
  Expect(JoinEarlyReaders(readers) == L"Ditto.exe,?",
         "each reader once, an unnamed one as ?");
  NoteEarlyReader(&readers, L"a.exe");
  NoteEarlyReader(&readers, L"b.exe");
  Expect(readers.size() == kMaxEarlyReaders, "the list stays bounded");
  Expect(JoinEarlyReaders(readers) == L"Ditto.exe,?,a.exe",
         "the first readers are kept");

  if (failures > 0) {
    std::fprintf(stderr, "clipboard_receipt_policy_test: %d failed\n", failures);
    return 1;
  }
  std::printf("clipboard_receipt_policy_test: all passed\n");
  return 0;
}
