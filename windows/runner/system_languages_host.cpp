#include "system_languages_host.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <cwchar>
#include <vector>

#include "utils.h"

using flutter::EncodableList;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;

namespace {

constexpr char kChannelName[] = "whispaste/system_languages";

// The user's preferred UI languages, in order. The buffer holds
// NUL-terminated names closed by one more NUL.
EncodableList PreferredUILanguages() {
  EncodableList languages;
  ULONG count = 0;
  ULONG size = 0;
  if (!::GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &count, nullptr,
                                     &size) ||
      size == 0) {
    return languages;
  }
  std::vector<wchar_t> buffer(size);
  if (!::GetUserPreferredUILanguages(MUI_LANGUAGE_NAME, &count, buffer.data(),
                                     &size)) {
    return languages;
  }
  for (const wchar_t* name = buffer.data(); *name != L'\0';
       name += std::wcslen(name) + 1) {
    languages.emplace_back(Utf8FromUtf16(name));
  }
  return languages;
}

}  // namespace

SystemLanguagesHost::SystemLanguagesHost(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [](const MethodCall<EncodableValue>& call,
         std::unique_ptr<MethodResult<EncodableValue>> result) {
        if (call.method_name() == "preferredLanguages") {
          result->Success(EncodableValue(PreferredUILanguages()));
        } else {
          result->NotImplemented();
        }
      });
}

SystemLanguagesHost::~SystemLanguagesHost() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
}
