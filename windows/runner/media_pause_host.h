// Pauses system media playback while WhisPaste records and resumes only the
// sessions it paused itself (#563). Uses the Windows system media transport
// controls (SMTC), the same sessions the volume flyout shows. Ducking (#1511)
// turns the Core Audio sessions of other apps down and back to their exact
// previous volume.
//
// Channel "com.whispaste.media_pause" (contract mirrored in
// lib/services/media_pause/media_pause_backends.dart):
//   isAvailable    -> bool
//   pauseIfPlaying -> "paused" | "nothing" | "unavailable"
//   resumePaused   -> null
//   duckAvailable  -> bool                       (#1511, Core Audio sessions)
//   playingVolumes -> [{id, levels:[double]}]    audible foreign sessions
//   setVolumes([{id, levels}]) -> null           skips ended sessions
#ifndef RUNNER_MEDIA_PAUSE_HOST_H_
#define RUNNER_MEDIA_PAUSE_HOST_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>

#include <memory>

class MediaPauseHost {
 public:
  MediaPauseHost(flutter::BinaryMessenger* messenger, HWND window);
  ~MediaPauseHost();

  MediaPauseHost(const MediaPauseHost&) = delete;
  MediaPauseHost& operator=(const MediaPauseHost&) = delete;

  // Runs work posted by worker threads on the platform thread.
  bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::shared_ptr<State> state_;
  HWND window_;
};

#endif  // RUNNER_MEDIA_PAUSE_HOST_H_
