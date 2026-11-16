#include "power_event_host.h"

namespace {

constexpr char kChannelName[] = "com.whispaste.power";

}  // namespace

PowerEventHost::PowerEventHost(flutter::FlutterEngine* engine)
    : engine_(engine) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      engine_->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
}

PowerEventHost::~PowerEventHost() { Destroy(); }

void PowerEventHost::Destroy() {
  if (destroyed_) return;
  destroyed_ = true;
  channel_.reset();
}

void PowerEventHost::HandlePowerBroadcast(WPARAM event) {
  if (destroyed_ || !channel_) return;

  switch (event) {
    case PBT_APMSUSPEND:
      channel_->InvokeMethod("willSleep", nullptr);
      break;
    case PBT_APMRESUMEAUTOMATIC:
    case PBT_APMRESUMESUSPEND:
      channel_->InvokeMethod("didWake", nullptr);
      break;
    default:
      break;
  }
}
