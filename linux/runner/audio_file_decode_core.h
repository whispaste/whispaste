// Flutter-free decoder core for imported audio files on Linux (WP-35b).
//
// Decodes Ogg/Opus (libopusfile), FLAC (libFLAC) and MP3 (minimp3, vendored)
// into mono 16 kHz 16-bit little-endian PCM, the STT input format. Streaming:
// the input is never held in memory as a whole. Kept free of GTK and Flutter
// so that audio_file_decode_test.cc runs on any host
// (test/scripts/audio_file_decode_test.sh).
#ifndef WHISPASTE_AUDIO_FILE_DECODE_CORE_H_
#define WHISPASTE_AUDIO_FILE_DECODE_CORE_H_

#include <cstdint>
#include <string>

namespace whispaste {

enum class DecodeStatus {
  kOk,
  // Not an container/codec this core decodes (M4A/AAC, Ogg/Vorbis, unknown).
  kUnsupportedFormat,
  // Recognised format, but the stream is corrupt or cannot be read.
  kDecodeFailed,
  // The output would exceed max_frames (duration limit).
  kInputLimit,
  kIoError,
  // The format is known, but a platform decoder for it is not installed.
  kUnavailable,
};

struct DecodeOutcome {
  DecodeStatus status = DecodeStatus::kIoError;
  // Frames written at 16 kHz mono (valid for kOk, partial otherwise).
  int64_t frames = 0;
  std::string message;
};

// Output rate of every decode path; matches kSttSampleRate in Dart.
constexpr int kCoreSampleRate = 16000;

// Decodes [input_path] into raw mono 16 kHz int16 LE PCM at [output_path].
// Format is chosen from the file's magic bytes, not from its extension.
DecodeOutcome DecodeCompressedToRawPcm16(const std::string& input_path,
                                         const std::string& output_path,
                                         int64_t max_frames);

}  // namespace whispaste

#endif  // WHISPASTE_AUDIO_FILE_DECODE_CORE_H_
