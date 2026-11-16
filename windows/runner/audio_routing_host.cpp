#include "audio_routing_host.h"

#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include "utils.h"

namespace {

flutter::EncodableValue DefaultInputDevice() {
  // The runner initializes COM on this thread. Match record_windows' format
  // probe: eCapture/eCommunications, not the console or multimedia role.
  // GetId returns the same endpoint ID used by record's listInputDevices.
  Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return flutter::EncodableValue();
  }
  Microsoft::WRL::ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications,
                                                 &device))) {
    return flutter::EncodableValue();
  }
  LPWSTR id = nullptr;
  const HRESULT hr = device->GetId(&id);
  flutter::EncodableValue result;
  if (SUCCEEDED(hr) && id) result = flutter::EncodableValue(Utf8FromUtf16(id));
  CoTaskMemFree(id);
  return result;
}

}  // namespace

AudioRoutingHost::AudioRoutingHost(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), "com.whispaste.audio_routing",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getDefaultInputDevice") {
          result->Success(DefaultInputDevice());
        } else {
          result->NotImplemented();
        }
      });
}

AudioRoutingHost::~AudioRoutingHost() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}
