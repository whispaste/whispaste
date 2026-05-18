// Runner-owned MethodChannel bridge for taskbar-flash attention requests
// (Windows equivalent of macOS Dock-icon bouncing).
//
// Used when WhisPaste needs to signal a pending action item (e.g. paste
// failed due to a fixable configuration issue) and the main window may be
// hidden or behind other apps.

#ifndef ATTENTION_HOST_H_
#define ATTENTION_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <memory>

class AttentionHost {
 public:
  AttentionHost(flutter::FlutterEngine* engine, HWND owner);
  ~AttentionHost();

  AttentionHost(const AttentionHost&) = delete;
  AttentionHost& operator=(const AttentionHost&) = delete;

  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  bool RequestAttention(bool critical);
  void CancelAttention();

  flutter::FlutterEngine* engine_;
  HWND owner_;
  bool destroyed_ = false;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // ATTENTION_HOST_H_
