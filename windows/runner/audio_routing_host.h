// Read-only default capture endpoint lookup (#929).
#ifndef RUNNER_AUDIO_ROUTING_HOST_H_
#define RUNNER_AUDIO_ROUTING_HOST_H_

#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>

#include <memory>

class AudioRoutingHost {
 public:
  explicit AudioRoutingHost(flutter::FlutterEngine* engine);
  ~AudioRoutingHost();

  AudioRoutingHost(const AudioRoutingHost&) = delete;
  AudioRoutingHost& operator=(const AudioRoutingHost&) = delete;

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_AUDIO_ROUTING_HOST_H_
