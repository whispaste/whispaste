#include "spell_check_host.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>
#include <objbase.h>
#include <windows.h>

#include <string>
#include <vector>

#include "utils.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::MethodCall;
using flutter::MethodResult;
using Microsoft::WRL::ComPtr;

namespace {

constexpr char kChannelName[] = "whispaste/spell_check";

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) return std::wstring();
  const int length = ::MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) return std::wstring();
  std::wstring out(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                        static_cast<int>(utf8.size()), out.data(), length);
  return out;
}

const std::string* StringArg(const EncodableMap& args, const char* key) {
  const auto it = args.find(EncodableValue(key));
  if (it == args.end()) return nullptr;
  return std::get_if<std::string>(&it->second);
}

// Drains an enumerator of strings (languages, suggestions).
EncodableList Strings(IEnumString* list, size_t limit) {
  EncodableList out;
  if (list == nullptr) return out;
  LPOLESTR item = nullptr;
  while (out.size() < limit && list->Next(1, &item, nullptr) == S_OK) {
    out.emplace_back(Utf8FromUtf16(item));
    ::CoTaskMemFree(item);
  }
  return out;
}

}  // namespace

SpellCheckHost::SpellCheckHost(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  // The runner's main thread is an STA (main.cpp); the factory lives there.
  if (FAILED(::CoCreateInstance(__uuidof(SpellCheckerFactory), nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&factory_)))) {
    factory_.Reset();
  }
  channel_->SetMethodCallHandler(
      [this](const MethodCall<EncodableValue>& call,
             std::unique_ptr<MethodResult<EncodableValue>> result) {
        const auto& name = call.method_name();
        if (name == "languages") {
          ComPtr<IEnumString> list;
          if (!factory_ ||
              FAILED(factory_->get_SupportedLanguages(&list))) {
            result->Success(EncodableValue(EncodableList()));
            return;
          }
          result->Success(EncodableValue(Strings(list.Get(), 256)));
          return;
        }
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        const std::string* language =
            args == nullptr ? nullptr : StringArg(*args, "language");
        if (language == nullptr) {
          result->Error("bad_args", "language missing");
          return;
        }
        ISpellChecker* checker = CheckerFor(Utf16FromUtf8(*language));
        if (name == "checkWords") {
          const auto it = args->find(EncodableValue("words"));
          const auto* words = it == args->end()
                                  ? nullptr
                                  : std::get_if<EncodableList>(&it->second);
          if (words == nullptr) {
            result->Error("bad_args", "words missing");
            return;
          }
          EncodableList out;
          out.reserve(words->size());
          for (const auto& value : *words) {
            const auto* word = std::get_if<std::string>(&value);
            bool correct = true;
            if (checker != nullptr && word != nullptr && !word->empty()) {
              const std::wstring w = Utf16FromUtf8(*word);
              ComPtr<IEnumSpellingError> errors;
              if (SUCCEEDED(checker->Check(w.c_str(), &errors)) && errors) {
                ComPtr<ISpellingError> error;
                // Any error (misspelled, repeated, auto-replace) marks it.
                correct = errors->Next(&error) != S_OK;
              }
            }
            out.emplace_back(correct);
          }
          result->Success(EncodableValue(out));
        } else if (name == "suggest") {
          const std::string* word = StringArg(*args, "word");
          ComPtr<IEnumString> list;
          if (checker == nullptr || word == nullptr ||
              FAILED(checker->Suggest(Utf16FromUtf8(*word).c_str(), &list))) {
            result->Success(EncodableValue(EncodableList()));
            return;
          }
          result->Success(EncodableValue(Strings(list.Get(), 10)));
        } else {
          result->NotImplemented();
        }
      });
}

SpellCheckHost::~SpellCheckHost() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  checkers_.clear();
  factory_.Reset();
}

ISpellChecker* SpellCheckHost::CheckerFor(const std::wstring& language) {
  if (!factory_ || language.empty()) return nullptr;
  const auto it = checkers_.find(language);
  if (it != checkers_.end()) return it->second.Get();
  ComPtr<ISpellChecker> checker;
  BOOL supported = FALSE;
  if (SUCCEEDED(factory_->IsSupported(language.c_str(), &supported)) &&
      supported) {
    if (FAILED(factory_->CreateSpellChecker(language.c_str(), &checker))) {
      checker.Reset();
    }
  }
  // Unsupported tags are cached as nullptr, so they are not asked again.
  checkers_[language] = checker;
  return checker.Get();
}
