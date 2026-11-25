// Runner-owned MethodChannel `whispaste/spell_check` (#670).
//
// Backs the editor spell check with the Windows Spell Checking API
// (ISpellCheckerFactory, Windows 8+):
//   languages                     -> ["de-DE", "en-US", ...]
//   checkWords {language, words}  -> [bool, ...] (true = spelled correctly)
//   suggest {language, word}      -> ["...", ...]
// Same contract on macOS (NSSpellChecker) and Linux (Enchant).

#ifndef RUNNER_SPELL_CHECK_HOST_H_
#define RUNNER_SPELL_CHECK_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <spellcheck.h>
#include <wrl/client.h>

#include <map>
#include <memory>
#include <string>

class SpellCheckHost {
 public:
  explicit SpellCheckHost(flutter::FlutterEngine* engine);
  ~SpellCheckHost();

  SpellCheckHost(const SpellCheckHost&) = delete;
  SpellCheckHost& operator=(const SpellCheckHost&) = delete;

 private:
  // The checker for [language], created once; nullptr when unsupported.
  ISpellChecker* CheckerFor(const std::wstring& language);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ISpellCheckerFactory> factory_;
  std::map<std::wstring, Microsoft::WRL::ComPtr<ISpellChecker>> checkers_;
};

#endif  // RUNNER_SPELL_CHECK_HOST_H_
