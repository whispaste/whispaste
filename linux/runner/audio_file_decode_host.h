#ifndef FLUTTER_AUDIO_FILE_DECODE_HOST_H_
#define FLUTTER_AUDIO_FILE_DECODE_HOST_H_

#include <flutter_linux/flutter_linux.h>

// MethodChannel host `whispaste/audio_file_decode` (WP-35b): decodes imported
// Ogg/Opus, FLAC and MP3 files to 16 kHz mono int16 PCM for the import queue.
//
// Contract (same as the macOS host, plus an optional limit):
// - `decodeToPcm16`, arguments `inputPath`, `outputPath`, optional `maxFrames`.
// - result: frame count as int.
// - errors: UNSUPPORTED_FORMAT (not decodable here, e.g. M4A/AAC on Linux),
//   DECODE_FAILED (corrupt or empty stream), INPUT_LIMIT (longer than
//   maxFrames), IO_ERROR. Decoding runs on a worker thread via GTask.
class AudioFileDecodeHost {
 public:
  explicit AudioFileDecodeHost(FlBinaryMessenger* messenger);
  ~AudioFileDecodeHost();

  AudioFileDecodeHost(const AudioFileDecodeHost&) = delete;
  AudioFileDecodeHost& operator=(const AudioFileDecodeHost&) = delete;

 private:
  FlMethodChannel* channel_ = nullptr;

  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);
};

#endif  // FLUTTER_AUDIO_FILE_DECODE_HOST_H_
