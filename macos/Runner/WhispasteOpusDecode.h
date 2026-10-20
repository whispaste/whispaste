// C entry point of the Ogg/Opus import decoder on macOS (WP-35b). Swift reaches
// it through Runner-Bridging-Header.h. The decoder is the shared core in
// linux/runner/audio_file_decode_core.cc, built with WP_WITH_FLAC=0 (FLAC
// stays with AVFoundation).
#ifndef WHISPASTE_OPUS_DECODE_H_
#define WHISPASTE_OPUS_DECODE_H_

#include <stddef.h>
#include <stdint.h>

// Mirrors whispaste::DecodeStatus.
#define WP_DECODE_OK 0
#define WP_DECODE_UNSUPPORTED 1
#define WP_DECODE_FAILED 2
#define WP_DECODE_INPUT_LIMIT 3
#define WP_DECODE_IO_ERROR 4
#define WP_DECODE_UNAVAILABLE 5

#ifdef __cplusplus
extern "C" {
#endif

// Decodes [input_path] to mono 16 kHz int16 LE PCM at [output_path]. Writes the
// frame count to [out_frames] and a human-readable note to [message].
int wp_decode_ogg_to_pcm16(const char* input_path, const char* output_path,
                           int64_t max_frames, int64_t* out_frames,
                           char* message, size_t message_size);

#ifdef __cplusplus
}
#endif

#endif  // WHISPASTE_OPUS_DECODE_H_
