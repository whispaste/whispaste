// Adapter from the shared decoder core to the C entry point in
// WhispasteOpusDecode.h. Keeps the Swift side free of C++ types.
#include "WhispasteOpusDecode.h"

#include <cstdio>

#include "audio_file_decode_core.h"

int wp_decode_ogg_to_pcm16(const char* input_path, const char* output_path,
                           int64_t max_frames, int64_t* out_frames,
                           char* message, size_t message_size) {
  const whispaste::DecodeOutcome outcome =
      whispaste::DecodeCompressedToRawPcm16(input_path, output_path, max_frames);
  if (out_frames) *out_frames = outcome.frames;
  if (message && message_size > 0) {
    std::snprintf(message, message_size, "%s", outcome.message.c_str());
  }
  switch (outcome.status) {
    case whispaste::DecodeStatus::kOk:
      return WP_DECODE_OK;
    case whispaste::DecodeStatus::kUnsupportedFormat:
      return WP_DECODE_UNSUPPORTED;
    case whispaste::DecodeStatus::kDecodeFailed:
      return WP_DECODE_FAILED;
    case whispaste::DecodeStatus::kInputLimit:
      return WP_DECODE_INPUT_LIMIT;
    case whispaste::DecodeStatus::kIoError:
      return WP_DECODE_IO_ERROR;
    case whispaste::DecodeStatus::kUnavailable:
      return WP_DECODE_UNAVAILABLE;
  }
  return WP_DECODE_FAILED;
}
