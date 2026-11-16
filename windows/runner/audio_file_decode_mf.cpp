#include "audio_file_decode_mf.h"

#include "../../linux/runner/mp4_gapless.h"

#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdio>
#include <vector>

namespace audio_decode {
namespace {

using Microsoft::WRL::ComPtr;

constexpr UINT32 kOutputRate = 16000;

Outcome Fail(Status status, std::string message, int64_t frames = 0) {
  Outcome o;
  o.status = status;
  o.frames = frames;
  o.message = std::move(message);
  return o;
}

// Codec or container the OS cannot read, as opposed to a read error.
bool IsUnsupported(HRESULT hr) {
  return hr == MF_E_UNSUPPORTED_BYTESTREAM_TYPE ||
         hr == MF_E_UNSUPPORTED_FORMAT || hr == MF_E_TOPO_CODEC_NOT_FOUND ||
         hr == MF_E_INVALIDMEDIATYPE || hr == MF_E_UNSUPPORTED_CHARACTERISTICS;
}

// Scoped MF/COM initialisation for the calling worker thread.
class MediaFoundationSession {
 public:
  MediaFoundationSession()
      : com_(SUCCEEDED(::CoInitializeEx(nullptr, COINIT_MULTITHREADED))),
        mf_(SUCCEEDED(::MFStartup(MF_VERSION))) {}
  ~MediaFoundationSession() {
    if (mf_) ::MFShutdown();
    if (com_) ::CoUninitialize();
  }
  bool ok() const { return com_ && mf_; }

 private:
  bool com_;
  bool mf_;
};

// Gapless info of an MP4/M4A input; nothing (rate 0) for other containers.
whispaste::Mp4Gapless GaplessOf(const std::wstring& input) {
  FILE* f = nullptr;
  if (_wfopen_s(&f, input.c_str(), L"rb") != 0 || !f) return {};
  const whispaste::Mp4Gapless gapless = whispaste::ReadMp4Gapless(f);
  std::fclose(f);
  return gapless;
}

// Frames at the 16 kHz output rate for |samples| at |rate|, rounded.
int64_t ToOutputRate(uint64_t samples, uint32_t rate) {
  return static_cast<int64_t>((samples * kOutputRate + rate / 2) / rate);
}

}  // namespace

Outcome DecodeWithMediaFoundation(const std::wstring& input,
                                  const std::wstring& output,
                                  int64_t max_frames) {
  if (::GetFileAttributesW(input.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return Fail(Status::kIoError, "cannot open input");
  }
  MediaFoundationSession session;
  if (!session.ok()) {
    return Fail(Status::kIoError, "Media Foundation is not available");
  }

  ComPtr<IMFAttributes> attributes;
  ::MFCreateAttributes(&attributes, 0);
  ComPtr<IMFSourceReader> reader;
  HRESULT hr = ::MFCreateSourceReaderFromURL(input.c_str(), attributes.Get(),
                                             &reader);
  if (FAILED(hr)) {
    return IsUnsupported(hr)
               ? Fail(Status::kUnsupportedFormat, "container not supported")
               : Fail(Status::kDecodeFailed, "cannot open audio file");
  }

  reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE);
  hr = reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), TRUE);
  if (FAILED(hr)) {
    return Fail(Status::kUnsupportedFormat, "file has no audio stream");
  }

  // The Source Reader inserts the decoder and the resampler for this type.
  ComPtr<IMFMediaType> pcm;
  ::MFCreateMediaType(&pcm);
  pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
  pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
  pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
  pcm->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kOutputRate);
  pcm->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1);
  pcm->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 2);
  pcm->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
  hr = reader->SetCurrentMediaType(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM),
                                   nullptr, pcm.Get());
  if (FAILED(hr)) {
    return IsUnsupported(hr)
               ? Fail(Status::kUnsupportedFormat, "codec not supported")
               : Fail(Status::kDecodeFailed, "cannot start the decoder");
  }

  FILE* out = nullptr;
  if (_wfopen_s(&out, output.c_str(), L"wb") != 0 || !out) {
    return Fail(Status::kIoError, "cannot create output");
  }

  // Gapless trim (MP4/M4A): the decoder keeps the encoder priming, so drop
  // |skip| leading frames and keep |keep| frames after them, at 16 kHz.
  // Without the info nothing is trimmed.
  const whispaste::Mp4Gapless gapless = GaplessOf(input);
  int64_t skip = 0;
  int64_t keep = 0;
  if (gapless.rate != 0) {
    skip = ToOutputRate(gapless.priming, gapless.rate);
    keep = gapless.total != 0 ? ToOutputRate(gapless.total, gapless.rate) : 0;
  }

  int64_t frames = 0;
  int64_t seen = 0;  // decoded frames so far, before trimming
  bool write_ok = true;
  bool limit_hit = false;
  while (true) {
    DWORD flags = 0;
    ComPtr<IMFSample> sample;
    hr = reader->ReadSample(static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM), 0, nullptr,
                            &flags, nullptr, &sample);
    // A read error after some audio keeps what was decoded (see header).
    if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) break;
    if (!sample) continue;
    ComPtr<IMFMediaBuffer> buffer;
    if (FAILED(sample->ConvertToContiguousBuffer(&buffer))) break;
    BYTE* data = nullptr;
    DWORD current = 0;
    if (FAILED(buffer->Lock(&data, nullptr, &current))) break;
    const int64_t chunk = static_cast<int64_t>(current / sizeof(int16_t));
    int64_t from = skip > seen ? skip - seen : 0;
    int64_t to = chunk;
    if (keep > 0) to = std::min(chunk, skip + keep - seen);
    seen += chunk;
    int64_t take = to > from ? to - from : 0;
    if (frames + take > max_frames) {
      limit_hit = true;
      take = max_frames - frames;
    }
    if (take > 0) {
      const BYTE* first = data + static_cast<size_t>(from) * sizeof(int16_t);
      if (std::fwrite(first, sizeof(int16_t), static_cast<size_t>(take), out) !=
          static_cast<size_t>(take)) {
        write_ok = false;
      }
      frames += take;
    }
    buffer->Unlock();
    if (!write_ok || limit_hit) break;
    if (keep > 0 && seen >= skip + keep) break;  // trimmed tail reached
  }
  std::fclose(out);

  if (!write_ok) return Fail(Status::kIoError, "cannot write decoded audio", frames);
  if (limit_hit) {
    return Fail(Status::kInputLimit, "audio longer than the limit", frames);
  }
  if (frames == 0) return Fail(Status::kDecodeFailed, "no audio decoded");
  Outcome o;
  o.status = Status::kOk;
  o.frames = frames;
  return o;
}

}  // namespace audio_decode
