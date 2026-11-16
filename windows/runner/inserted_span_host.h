// Runner-owned MethodChannel `com.whispaste.inserted_span` (#384): reads back
// the text WhisPaste just inserted into the focused field of another app, so
// later corrections by the user can be noticed. Not a Flutter plugin; owned by
// FlutterWindow. The UI Automation work runs on a worker thread and the reply
// is posted back to the platform thread (same pattern as AudioFileDecodeHost).
//
// Contract (same on macOS and Linux):
//   readInsertedSpan({expectedText: String, slackChars: int = 0})
//   -> {readable: bool, text: String?, matchesExpected: bool,
//       reason: String, pattern: String?}
// reason: ok | no_focus | password_field | own_window | no_text_pattern |
//         no_caret | uia_unavailable | uia_error | busy (two reads already
//         running).
// text is the range ending at the caret, at most expectedText + slackChars
// characters; null unless readable. Callers must never log it.

#ifndef RUNNER_INSERTED_SPAN_HOST_H_
#define RUNNER_INSERTED_SPAN_HOST_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class InsertedSpanHost {
 public:
  InsertedSpanHost(flutter::FlutterEngine* engine, HWND owner);
  ~InsertedSpanHost();

  InsertedSpanHost(const InsertedSpanHost&) = delete;
  InsertedSpanHost& operator=(const InsertedSpanHost&) = delete;

  void Destroy();

  // Handles the private window message that carries a finished read back to
  // the platform thread. Returns true when the message was consumed.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  HWND owner_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_INSERTED_SPAN_HOST_H_
