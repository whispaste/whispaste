// Runner-owned MethodChannel `whispaste/audio_file_decode` (WP-35b): decodes
// imported audio files with Media Foundation. Not a Flutter plugin; owned by
// FlutterWindow. The decode runs on a worker thread and the result is posted
// back to the platform thread, the same way SupportStoreChannel does it.
//
// Contract (same as macOS and Linux): `decodeToPcm16` with `inputPath`,
// `outputPath` and optional `maxFrames`; result is the frame count as int;
// errors UNSUPPORTED_FORMAT, DECODE_FAILED, INPUT_LIMIT, IO_ERROR.

#ifndef RUNNER_AUDIO_FILE_DECODE_HOST_H_
#define RUNNER_AUDIO_FILE_DECODE_HOST_H_

#include <flutter/encodable_value.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

class AudioFileDecodeHost {
 public:
  AudioFileDecodeHost(flutter::FlutterEngine* engine, HWND owner);
  ~AudioFileDecodeHost();

  AudioFileDecodeHost(const AudioFileDecodeHost&) = delete;
  AudioFileDecodeHost& operator=(const AudioFileDecodeHost&) = delete;

  void Destroy();

  // Handles the private window message that carries a finished decode back to
  // the platform thread. Returns true when the message was consumed.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  class Impl;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_AUDIO_FILE_DECODE_HOST_H_
