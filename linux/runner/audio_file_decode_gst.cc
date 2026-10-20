// M4A/AAC decoding through GStreamer. The libraries are opened with dlopen,
// so the build has no GStreamer dependency and GPL codecs are never linked
// into the app. The pipeline is
//   filesrc ! decodebin ! audioconvert ! audioresample ! appsink (S16LE 16 kHz mono).
#include "audio_file_decode_gst.h"

#include <dlfcn.h>

#include <cstdio>
#include <vector>

namespace whispaste {
namespace {

constexpr int kStateNull = 1;     // GST_STATE_NULL
constexpr int kStatePlaying = 4;  // GST_STATE_PLAYING
constexpr int kStateChangeFailure = 0;
constexpr int kMessageError = 2;  // GST_MESSAGE_ERROR
constexpr uint64_t kPullTimeoutNs = 5ULL * 1000 * 1000 * 1000;
constexpr int kMaxStalls = 6;  // 30 s without data ends the decode

constexpr const char kPipeline[] =
    "filesrc name=src ! decodebin ! audioconvert ! audioresample ! "
    "appsink name=sink sync=false "
    "caps=\"audio/x-raw,format=S16LE,rate=16000,channels=1,layout=interleaved\"";

using InitFn = void (*)(int*, char***);
using ParseLaunchFn = void* (*)(const char*, void**);
using BinGetByNameFn = void* (*)(void*, const char*);
using ObjectSetFn = void (*)(void*, const char*, ...);
using SetStateFn = int (*)(void*, int);
using GetBusFn = void* (*)(void*);
using PopFilteredFn = void* (*)(void*, int);
using ReleaseFn = void (*)(void*);
using FactoryFindFn = void* (*)(const char*);
using TryPullFn = void* (*)(void*, uint64_t);
using IsEosFn = int (*)(void*);
using SampleBufferFn = void* (*)(void*);
using BufferSizeFn = size_t (*)(void*);
using BufferExtractFn = size_t (*)(void*, size_t, void*, size_t);
using ErrorFreeFn = void (*)(void*);

struct Api {
  InitFn init = nullptr;
  ParseLaunchFn parse_launch = nullptr;
  BinGetByNameFn bin_get_by_name = nullptr;
  ObjectSetFn object_set = nullptr;
  SetStateFn set_state = nullptr;
  GetBusFn get_bus = nullptr;
  PopFilteredFn pop_filtered = nullptr;
  ReleaseFn message_unref = nullptr;
  ReleaseFn object_unref = nullptr;
  ReleaseFn sample_unref = nullptr;
  FactoryFindFn factory_find = nullptr;
  TryPullFn try_pull = nullptr;
  IsEosFn is_eos = nullptr;
  SampleBufferFn sample_get_buffer = nullptr;
  BufferSizeFn buffer_get_size = nullptr;
  BufferExtractFn buffer_extract = nullptr;
  ErrorFreeFn error_free = nullptr;
};

template <typename Fn>
bool Sym(void* handle, const char* name, Fn* out) {
  void* p = handle ? dlsym(handle, name) : nullptr;
  if (!p) return false;
  *out = reinterpret_cast<Fn>(p);
  return true;
}

// Resolves every symbol. Returns false when a library or symbol is missing.
bool LoadApi(Api* a) {
  void* gst = dlopen("libgstreamer-1.0.so.0", RTLD_NOW | RTLD_LOCAL);
  void* app = dlopen("libgstapp-1.0.so.0", RTLD_NOW | RTLD_LOCAL);
  void* gobject = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
  void* glib = dlopen("libglib-2.0.so.0", RTLD_NOW | RTLD_LOCAL);
  return Sym(gst, "gst_init", &a->init) &&
         Sym(gst, "gst_parse_launch", &a->parse_launch) &&
         Sym(gst, "gst_bin_get_by_name", &a->bin_get_by_name) &&
         Sym(gst, "gst_element_set_state", &a->set_state) &&
         Sym(gst, "gst_element_get_bus", &a->get_bus) &&
         Sym(gst, "gst_bus_pop_filtered", &a->pop_filtered) &&
         Sym(gst, "gst_message_unref", &a->message_unref) &&
         Sym(gst, "gst_object_unref", &a->object_unref) &&
         Sym(gst, "gst_element_factory_find", &a->factory_find) &&
         Sym(app, "gst_app_sink_try_pull_sample", &a->try_pull) &&
         Sym(app, "gst_app_sink_is_eos", &a->is_eos) &&
         Sym(gst, "gst_sample_get_buffer", &a->sample_get_buffer) &&
         Sym(gst, "gst_sample_unref", &a->sample_unref) &&
         Sym(gst, "gst_buffer_get_size", &a->buffer_get_size) &&
         Sym(gst, "gst_buffer_extract", &a->buffer_extract) &&
         Sym(gobject, "g_object_set", &a->object_set) &&
         Sym(glib, "g_error_free", &a->error_free);
}

bool FactoryExists(const Api& a, const char* name) {
  void* f = a.factory_find(name);
  if (!f) return false;
  a.object_unref(f);
  return true;
}

bool HasDecoders(const Api& a) {
  for (const char* name : {"decodebin", "audioconvert", "audioresample",
                           "appsink", "filesrc", "qtdemux"}) {
    if (!FactoryExists(a, name)) return false;
  }
  for (const char* aac : {"avdec_aac", "faad", "fdkaacdec", "voaacdec"}) {
    if (FactoryExists(a, aac)) return true;
  }
  return false;
}

struct Loaded {
  bool available = false;
  Api api;
};

const Loaded& Load() {
  static const Loaded loaded = [] {
    Loaded l;
    if (!LoadApi(&l.api)) return l;
    int argc = 0;
    char** argv = nullptr;
    l.api.init(&argc, &argv);
    l.available = HasDecoders(l.api);
    return l;
  }();
  return loaded;
}

DecodeOutcome Fail(DecodeStatus status, const std::string& message,
                   int64_t frames = 0) {
  DecodeOutcome o;
  o.status = status;
  o.frames = frames;
  o.message = message;
  return o;
}

}  // namespace

bool GstAacAvailable() { return Load().available; }

DecodeOutcome DecodeAacWithGstreamer(const std::string& input_path,
                                     const std::string& output_path,
                                     int64_t max_frames) {
  if (!GstAacAvailable()) {
    return Fail(DecodeStatus::kUnavailable,
                "AAC decoder (GStreamer) not installed");
  }
  const Api& a = Load().api;

  void* err = nullptr;
  void* pipeline = a.parse_launch(kPipeline, &err);
  if (err) a.error_free(err);
  if (!pipeline) return Fail(DecodeStatus::kDecodeFailed, "cannot build pipeline");
  void* src = a.bin_get_by_name(pipeline, "src");
  void* sink = a.bin_get_by_name(pipeline, "sink");
  void* bus = a.get_bus(pipeline);
  FILE* out = std::fopen(output_path.c_str(), "wb");
  if (!src || !sink || !bus || !out) {
    if (out) std::fclose(out);
    if (bus) a.object_unref(bus);
    if (sink) a.object_unref(sink);
    if (src) a.object_unref(src);
    a.set_state(pipeline, kStateNull);
    a.object_unref(pipeline);
    return Fail(DecodeStatus::kIoError, "cannot set up GStreamer pipeline");
  }
  a.object_set(src, "location", input_path.c_str(), nullptr);

  DecodeOutcome outcome;
  int64_t frames = 0;
  bool limit_hit = false;
  bool write_ok = true;
  if (a.set_state(pipeline, kStatePlaying) == kStateChangeFailure) {
    outcome = Fail(DecodeStatus::kDecodeFailed, "GStreamer did not start");
  } else {
    std::vector<int16_t> pcm;
    int stalls = 0;
    bool done = false;
    while (!done) {
      void* sample = a.try_pull(sink, kPullTimeoutNs);
      if (!sample) {
        if (a.is_eos(sink)) break;
        if (void* msg = a.pop_filtered(bus, kMessageError)) {
          a.message_unref(msg);
          outcome = Fail(DecodeStatus::kDecodeFailed,
                         "GStreamer could not decode the file", frames);
          break;
        }
        if (++stalls >= kMaxStalls) {
          outcome = Fail(DecodeStatus::kDecodeFailed,
                         "GStreamer stopped delivering audio", frames);
          break;
        }
        continue;
      }
      stalls = 0;
      void* buffer = a.sample_get_buffer(sample);
      size_t samples = buffer ? a.buffer_get_size(buffer) / sizeof(int16_t) : 0;
      if (frames + static_cast<int64_t>(samples) > max_frames) {
        samples = static_cast<size_t>(max_frames - frames);
        limit_hit = true;
        done = true;
      }
      pcm.resize(samples);
      if (samples > 0) {
        a.buffer_extract(buffer, 0, pcm.data(), samples * sizeof(int16_t));
        if (std::fwrite(pcm.data(), sizeof(int16_t), samples, out) != samples) {
          write_ok = false;
          done = true;
        }
      }
      frames += static_cast<int64_t>(samples);
      a.sample_unref(sample);
    }
  }

  a.set_state(pipeline, kStateNull);
  a.object_unref(bus);
  a.object_unref(sink);
  a.object_unref(src);
  a.object_unref(pipeline);
  if (std::fclose(out) != 0) write_ok = false;

  if (outcome.status != DecodeStatus::kOk && !outcome.message.empty()) {
    return outcome;
  }
  if (!write_ok) return Fail(DecodeStatus::kIoError, "cannot write decoded audio");
  if (limit_hit) {
    return Fail(DecodeStatus::kInputLimit, "audio longer than the limit", frames);
  }
  if (frames == 0) return Fail(DecodeStatus::kDecodeFailed, "no audio decoded");
  DecodeOutcome ok;
  ok.status = DecodeStatus::kOk;
  ok.frames = frames;
  return ok;
}

}  // namespace whispaste
