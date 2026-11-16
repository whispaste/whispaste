// Reads back the text that was just inserted into the focused field of another
// app, through UI Automation (#384). Flutter-free so it can be exercised by a
// small console probe as well as by InsertedSpanHost.
//
// Privacy: password fields (IsPassword) are never read, WhisPaste's own windows
// are never read, and only a bounded range around the caret is fetched, never
// the whole document. The returned text must not be logged.

#ifndef RUNNER_INSERTED_SPAN_READER_H_
#define RUNNER_INSERTED_SPAN_READER_H_

#include <string>

namespace inserted_span {

struct Outcome {
  bool readable = false;
  // Text from expected + slack characters before the caret to after_chars
  // behind it (clamped to the document). Empty unless readable.
  std::wstring text;
  // True when |text| (CR removed) contains the expected text (CR removed).
  bool matches_expected = false;
  // "ok", "no_focus", "password_field", "own_window", "no_text_pattern",
  // "no_caret", "uia_unavailable", "uia_error".
  std::string reason;
  // "text_pattern2" or "text_pattern" when readable, else empty.
  std::string pattern;
};

// Blocking; call it on a worker thread. Initialises COM (MTA) for the calling
// thread itself. UIA connection and transaction timeouts bound a hung target.
// |after_chars| behind the caret let the user click anywhere inside the
// pasted text without cutting off its end.
Outcome Read(const std::wstring& expected, int slack_chars, int after_chars);

}  // namespace inserted_span

#endif  // RUNNER_INSERTED_SPAN_READER_H_
