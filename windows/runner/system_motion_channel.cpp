#include "system_motion_channel.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <algorithm>
#include <vector>

namespace {

constexpr char kChannelName[] = "com.whispaste.system_motion";

// All live channels, touched only on the platform (UI) thread.
std::vector<SystemMotionChannel*>& LiveChannels() {
  static std::vector<SystemMotionChannel*> channels;
  return channels;
}

// Value last pushed, so unrelated WM_SETTINGCHANGE broadcasts stay silent.
bool g_last_reduce_motion = false;

}  // namespace

SystemMotionChannel::SystemMotionChannel(flutter::BinaryMessenger* messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() == "reduceMotion") {
          result->Success(flutter::EncodableValue(ReduceMotion()));
        } else {
          result->NotImplemented();
        }
      });
  if (LiveChannels().empty()) g_last_reduce_motion = ReduceMotion();
  LiveChannels().push_back(this);
}

SystemMotionChannel::~SystemMotionChannel() {
  auto& channels = LiveChannels();
  channels.erase(std::remove(channels.begin(), channels.end(), this),
                 channels.end());
  channel_->SetMethodCallHandler(nullptr);
}

bool SystemMotionChannel::ReduceMotion() {
  BOOL animations = TRUE;
  if (!SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0)) {
    return false;
  }
  return animations == FALSE;
}

void SystemMotionChannel::OnSettingChange() {
  const bool value = ReduceMotion();
  if (value == g_last_reduce_motion) return;
  g_last_reduce_motion = value;
  for (SystemMotionChannel* channel : LiveChannels()) {
    channel->channel_->InvokeMethod(
        "reduceMotionChanged", std::make_unique<flutter::EncodableValue>(value));
  }
}
