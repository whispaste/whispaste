#include "audio_file_decode_host.h"

#include <cstdint>
#include <string>

#include "audio_file_decode_core.h"

namespace {

constexpr char kChannelName[] = "whispaste/audio_file_decode";
// Six hours at 16 kHz, the Dart-side import limit.
constexpr int64_t kDefaultMaxFrames = 6LL * 3600 * whispaste::kCoreSampleRate;

struct DecodeJob {
  std::string input_path;
  std::string output_path;
  int64_t max_frames = kDefaultMaxFrames;
  whispaste::DecodeOutcome outcome;
  FlMethodCall* method_call = nullptr;  // owned reference
};

void FreeJob(gpointer data) {
  auto* job = static_cast<DecodeJob*>(data);
  g_clear_object(&job->method_call);
  delete job;
}

void DecodeThread(GTask*, gpointer, gpointer task_data, GCancellable*) {
  auto* job = static_cast<DecodeJob*>(task_data);
  job->outcome = whispaste::DecodeCompressedToRawPcm16(
      job->input_path, job->output_path, job->max_frames);
}

void Respond(GObject*, GAsyncResult* result, gpointer) {
  // The GTask lives on the main context, so this runs on the GTK thread that
  // owns the method call.
  // The callback borrows the task; its reference is released by the caller.
  GTask* task = G_TASK(result);
  auto* job = static_cast<DecodeJob*>(g_task_get_task_data(task));
  g_autoptr(FlMethodResponse) response = nullptr;
  const auto& o = job->outcome;
  switch (o.status) {
    case whispaste::DecodeStatus::kOk:
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(
          fl_value_new_int(o.frames)));
      break;
    case whispaste::DecodeStatus::kUnsupportedFormat:
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "UNSUPPORTED_FORMAT", o.message.c_str(), nullptr));
      break;
    case whispaste::DecodeStatus::kUnavailable:
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "UNAVAILABLE", o.message.c_str(), nullptr));
      break;
    case whispaste::DecodeStatus::kDecodeFailed:
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "DECODE_FAILED", o.message.c_str(), nullptr));
      break;
    case whispaste::DecodeStatus::kInputLimit:
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INPUT_LIMIT", o.message.c_str(), nullptr));
      break;
    case whispaste::DecodeStatus::kIoError:
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "IO_ERROR", o.message.c_str(), nullptr));
      break;
  }
  fl_method_call_respond(job->method_call, response, nullptr);
}

}  // namespace

AudioFileDecodeHost::AudioFileDecodeHost(FlBinaryMessenger* messenger) {
  channel_ = fl_method_channel_new(messenger, kChannelName,
                                   FL_METHOD_CODEC(fl_standard_method_codec_new()));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
}

AudioFileDecodeHost::~AudioFileDecodeHost() {
  if (channel_) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&channel_);
}

void AudioFileDecodeHost::OnMethodCall(FlMethodChannel*,
                                       FlMethodCall* method_call,
                                       gpointer) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "decodeToPcm16") != 0) {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* input = args ? fl_value_lookup_string(args, "inputPath") : nullptr;
  FlValue* output = args ? fl_value_lookup_string(args, "outputPath") : nullptr;
  if (!input || fl_value_get_type(input) != FL_VALUE_TYPE_STRING || !output ||
      fl_value_get_type(output) != FL_VALUE_TYPE_STRING) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("INVALID_ARGS",
                                     "Missing inputPath or outputPath", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  auto* job = new DecodeJob();
  job->input_path = fl_value_get_string(input);
  job->output_path = fl_value_get_string(output);
  FlValue* max = fl_value_lookup_string(args, "maxFrames");
  if (max && fl_value_get_type(max) == FL_VALUE_TYPE_INT) {
    job->max_frames = fl_value_get_int(max);
  }
  job->method_call = FL_METHOD_CALL(g_object_ref(method_call));

  g_autoptr(GTask) task = g_task_new(nullptr, nullptr, Respond, nullptr);
  g_task_set_task_data(task, job, FreeJob);
  g_task_run_in_thread(task, DecodeThread);
}
