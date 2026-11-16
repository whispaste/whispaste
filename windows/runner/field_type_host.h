// Runner-owned MethodChannel `com.whispaste.field_type` (#948): the type of the
// focused field of another app, so WhisPaste does not paste into a password
// field. Only the type, never the content. Not a Flutter plugin; owned by
// FlutterWindow. The UI Automation work runs on a worker thread and the reply
// is posted back to the platform thread (same pattern as InsertedSpanHost).
//
// Contract (macOS #949 and Linux #950 answer "unknown" until they read it):
//   focusedFieldType() -> String: password | normal | unknown
// "unknown" also when two reads are already running.

#ifndef RUNNER_FIELD_TYPE_HOST_H_
#define RUNNER_FIELD_TYPE_HOST_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class FieldTypeHost {
 public:
  FieldTypeHost(flutter::FlutterEngine* engine, HWND owner);
  ~FieldTypeHost();

  FieldTypeHost(const FieldTypeHost&) = delete;
  FieldTypeHost& operator=(const FieldTypeHost&) = delete;

  void Destroy();

  // Handles the private window message that carries a finished read back to
  // the platform thread. Returns true when the message was consumed.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  HWND owner_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_FIELD_TYPE_HOST_H_
