#include "audio_file_decode_host.h"

#include <flutter/standard_method_codec.h>

#include <cstdio>
#include <cstring>
#include <functional>
#include <string>
#include <thread>

#include "audio_file_decode_mf.h"
#include "audio_file_decode_core.h"

using flutter::EncodableMap;
using flutter::EncodableValue;
using Result = flutter::MethodResult<EncodableValue>;
using SharedResult = std::shared_ptr<Result>;

namespace {

constexpr char kChannelName[] = "whispaste/audio_file_decode";
// Six hours at 16 kHz, the Dart-side import limit.
constexpr int64_t kDefaultMaxFrames = 6LL * 3600 * 16000;
// Private message that carries a std::function to the platform thread.
constexpr UINT kPostedWorkMessage = WM_APP + 0x53;

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return std::wstring();
  const int size = ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                                         static_cast<int>(text.size()),
                                         nullptr, 0);
  std::wstring wide(static_cast<size_t>(size), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), wide.data(), size);
  return wide;
}

// The shared core decodes Ogg/Opus (libopusfile) and MP3 (minimp3, which trims
// the encoder delay of the Xing/LAME tag). Everything else goes to Media
// Foundation. MP3 is recognised by its MPEG layer III header bits, so ADTS AAC
// (same 0xFF sync byte, layer bits 00) stays with Media Foundation.
bool IsCoreFormat(const std::wstring& path) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"rb") != 0 || !f) return false;
  unsigned char head[4] = {0, 0, 0, 0};
  const size_t got = std::fread(head, 1, sizeof(head), f);
  std::fclose(f);
  if (got >= 4 && std::memcmp(head, "OggS", 4) == 0) return true;
  if (got >= 3 && std::memcmp(head, "ID3", 3) == 0) return true;
  return got >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0 &&
         (head[1] & 0x06) == 0x02;
}

audio_decode::Outcome FromCore(const whispaste::DecodeOutcome& o) {
  audio_decode::Outcome out;
  out.frames = o.frames;
  out.message = o.message;
  switch (o.status) {
    case whispaste::DecodeStatus::kOk:
      out.status = audio_decode::Status::kOk;
      break;
    case whispaste::DecodeStatus::kUnsupportedFormat:
      out.status = audio_decode::Status::kUnsupportedFormat;
      break;
    case whispaste::DecodeStatus::kDecodeFailed:
      out.status = audio_decode::Status::kDecodeFailed;
      break;
    case whispaste::DecodeStatus::kInputLimit:
      out.status = audio_decode::Status::kInputLimit;
      break;
    case whispaste::DecodeStatus::kIoError:
      out.status = audio_decode::Status::kIoError;
      break;
    case whispaste::DecodeStatus::kUnavailable:
      out.status = audio_decode::Status::kUnavailable;
      break;
  }
  return out;
}

const EncodableValue* Lookup(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

void Respond(const SharedResult& result, const audio_decode::Outcome& o) {
  switch (o.status) {
    case audio_decode::Status::kOk:
      result->Success(EncodableValue(o.frames));
      return;
    case audio_decode::Status::kUnsupportedFormat:
      result->Error("UNSUPPORTED_FORMAT", o.message);
      return;
    case audio_decode::Status::kDecodeFailed:
      result->Error("DECODE_FAILED", o.message);
      return;
    case audio_decode::Status::kInputLimit:
      result->Error("INPUT_LIMIT", o.message);
      return;
    case audio_decode::Status::kIoError:
      result->Error("IO_ERROR", o.message);
      return;
    case audio_decode::Status::kUnavailable:
      result->Error("UNAVAILABLE", o.message);
      return;
  }
}

}  // namespace

// Runs |work| on the platform thread (the runner window's message loop). The
// worker captures only the HWND by value, so a host destroyed mid-decode never
// leaves the thread holding a dangling pointer.
void PostToPlatformThread(HWND owner, std::function<void()> work) {
  auto* boxed = new std::function<void()>(std::move(work));
  if (!::PostMessage(owner, kPostedWorkMessage, 0,
                     reinterpret_cast<LPARAM>(boxed))) {
    delete boxed;  // window is gone; nobody is waiting any more
  }
}

class AudioFileDecodeHost::Impl {
 public:
  explicit Impl(HWND owner) : owner_(owner) {}

  void Decode(std::string input_utf8, std::string output_utf8,
              int64_t max_frames, SharedResult result) {
    const HWND owner = owner_;
    std::thread([owner, input_utf8 = std::move(input_utf8),
                 output_utf8 = std::move(output_utf8), max_frames,
                 result = std::move(result)]() mutable {
      const std::wstring input = Utf8ToWide(input_utf8);
      const std::wstring output = Utf8ToWide(output_utf8);
      const audio_decode::Outcome outcome =
          IsCoreFormat(input)
              ? FromCore(whispaste::DecodeCompressedToRawPcm16(
                    input_utf8, output_utf8, max_frames))
              : audio_decode::DecodeWithMediaFoundation(input, output,
                                                        max_frames);
      PostToPlatformThread(owner, [result, outcome] {
        Respond(result, outcome);
      });
    }).detach();
  }

 private:
  HWND owner_;
};

AudioFileDecodeHost::AudioFileDecodeHost(flutter::FlutterEngine* engine,
                                         HWND owner)
    : channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          engine->messenger(), kChannelName,
          &flutter::StandardMethodCodec::GetInstance())),
      impl_(std::make_unique<Impl>(owner)) {
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "decodeToPcm16") {
      result->NotImplemented();
      return;
    }
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    const EncodableValue* input = args ? Lookup(*args, "inputPath") : nullptr;
    const EncodableValue* output = args ? Lookup(*args, "outputPath") : nullptr;
    const auto* in = input ? std::get_if<std::string>(input) : nullptr;
    const auto* out = output ? std::get_if<std::string>(output) : nullptr;
    if (!in || !out) {
      result->Error("INVALID_ARGS", "Missing inputPath or outputPath");
      return;
    }
    int64_t max_frames = kDefaultMaxFrames;
    if (const auto* m = args ? Lookup(*args, "maxFrames") : nullptr) {
      if (const auto* v = std::get_if<int64_t>(m)) max_frames = *v;
    }
    impl_->Decode(*in, *out, max_frames, SharedResult(std::move(result)));
  });
}

AudioFileDecodeHost::~AudioFileDecodeHost() { Destroy(); }

void AudioFileDecodeHost::Destroy() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  channel_.reset();
}

bool AudioFileDecodeHost::HandleWindowMessage(UINT message, WPARAM,
                                              LPARAM lparam) {
  if (message != kPostedWorkMessage) return false;
  std::unique_ptr<std::function<void()>> work(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*work)();
  return true;
}
