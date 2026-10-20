// Media Foundation decoder for imported audio files on Windows (WP-35b).
//
// Uses IMFSourceReader, which picks the system's own demuxers and decoders:
// MP3, FLAC (where the OS ships the FLAC decoder) and M4A/AAC. Output is
// 16 kHz mono 16-bit PCM, resampled by the Source Reader. Ogg/Opus has no
// Media Foundation demuxer and is reported as unsupported. Kept free of the
// Flutter types so the decode can run on a worker thread.
#ifndef RUNNER_AUDIO_FILE_DECODE_MF_H_
#define RUNNER_AUDIO_FILE_DECODE_MF_H_

#include <cstdint>
#include <string>

namespace audio_decode {

enum class Status {
  kOk,
  kUnsupportedFormat,
  kDecodeFailed,
  kInputLimit,
  kIoError,
  kUnavailable,
};

struct Outcome {
  Status status = Status::kIoError;
  int64_t frames = 0;
  std::string message;
};

// Decodes |input| into raw mono 16 kHz int16 LE PCM at |output|. Stops with
// kInputLimit once more than |max_frames| frames would be written. A stream
// that fails after some audio keeps the decoded prefix; no audio at all is
// kDecodeFailed.
Outcome DecodeWithMediaFoundation(const std::wstring& input,
                                  const std::wstring& output,
                                  int64_t max_frames);

}  // namespace audio_decode

#endif  // RUNNER_AUDIO_FILE_DECODE_MF_H_
