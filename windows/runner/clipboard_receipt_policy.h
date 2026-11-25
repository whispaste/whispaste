#ifndef RUNNER_CLIPBOARD_RECEIPT_POLICY_H_
#define RUNNER_CLIPBOARD_RECEIPT_POLICY_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

// How the Windows host answers a WM_RENDERFORMAT for its receipt write.
// Platform-neutral C++17 so it is tested without Windows
// (test/scripts/clipboard_receipt_policy_test.sh).
//
// Windows asks the clipboard owner to render delayed data only once: after
// the first render the text sits on the clipboard and later readers get it
// without a WM_RENDERFORMAT. A clipboard monitor that reads the transcript
// before the paste keystroke (it ignores the history exclusion formats) used
// to take that one render, so the target's real paste left no read receipt and
// every dictation ended in "Auto-Paste not confirmed" although the text had
// arrived. Declining the monitor's render keeps the announcement for the
// target: Windows sends WM_RENDERFORMAT again on the next read (verified on
// the Windows lab, also for a CF_TEXT read).
enum class ReceiptRender {
  kRender,          // No armed receipt: just render.
  kRenderPreRead,   // Render; a read before the keystroke, no proof.
  kRenderRead,      // Render; the read after the keystroke is the receipt.
  kDecline,         // Do not render; the announcement stays for the target.
};

// `reader_pid` is the process that has the clipboard open (0 when it opened
// the clipboard without a window and cannot be named). Only a read before the
// keystroke by a named process that is neither WhisPaste nor the paste target
// is declined. The target's own early read and an unnamed reader render as
// before, so no reader that might be the paste itself goes without the text.
inline ReceiptRender DecideReceiptRender(bool receipt_active,
                                         bool keystroke_posted,
                                         uint32_t reader_pid,
                                         uint32_t own_pid,
                                         uint32_t target_pid) {
  if (!receipt_active) return ReceiptRender::kRender;
  if (keystroke_posted) return ReceiptRender::kRenderRead;
  if (reader_pid == 0 || target_pid == 0 || reader_pid == own_pid ||
      reader_pid == target_pid) {
    return ReceiptRender::kRenderPreRead;
  }
  return ReceiptRender::kDecline;
}

// Diagnostics only, never a decision: who read the transcript before the
// keystroke. The paste log then names the program behind a missing receipt
// (a reader without a window stays unnamed). Only the file name of the
// program, never its path, which could carry the user name.
inline std::wstring ExeBaseName(const std::wstring& image_path) {
  const size_t slash = image_path.find_last_of(L"\\/");
  return slash == std::wstring::npos ? image_path
                                     : image_path.substr(slash + 1);
}

// At most this many distinct readers per paste, so a busy machine cannot
// grow the log line.
constexpr size_t kMaxEarlyReaders = 3;

// Adds `name` once; an empty name counts as unnamed ("?").
inline void NoteEarlyReader(std::vector<std::wstring>* readers,
                            const std::wstring& name) {
  const std::wstring entry = name.empty() ? L"?" : name;
  if (std::find(readers->begin(), readers->end(), entry) != readers->end()) {
    return;
  }
  if (readers->size() < kMaxEarlyReaders) readers->push_back(entry);
}

// "none" or the names joined by commas, for the receipt log line.
inline std::wstring JoinEarlyReaders(const std::vector<std::wstring>& readers) {
  if (readers.empty()) return L"none";
  std::wstring joined;
  for (const std::wstring& r : readers) {
    if (!joined.empty()) joined += L",";
    joined += r;
  }
  return joined;
}

#endif  // RUNNER_CLIPBOARD_RECEIPT_POLICY_H_
