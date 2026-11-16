// Runner-owned MethodChannel `whispaste/system_languages`.
//
// Answers `preferredLanguages` with the user's preferred UI languages in their
// order (GetUserPreferredUILanguages), e.g. ["de-DE", "en-US"]. Dart asks only
// on a first start whose Flutter locale list names no language. Same contract
// on macOS and Linux.

#ifndef RUNNER_SYSTEM_LANGUAGES_HOST_H_
#define RUNNER_SYSTEM_LANGUAGES_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>

class SystemLanguagesHost {
 public:
  explicit SystemLanguagesHost(flutter::FlutterEngine* engine);
  ~SystemLanguagesHost();

  SystemLanguagesHost(const SystemLanguagesHost&) = delete;
  SystemLanguagesHost& operator=(const SystemLanguagesHost&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SYSTEM_LANGUAGES_HOST_H_
