// M4A/AAC import on Linux through GStreamer, loaded at runtime with dlopen
// (WP-35b). No build-time dependency: when the GStreamer libraries or an AAC
// decoder are missing on the host, GstAacAvailable() is false and the core
// reports DecodeStatus::kUnavailable.
#ifndef WHISPASTE_AUDIO_FILE_DECODE_GST_H_
#define WHISPASTE_AUDIO_FILE_DECODE_GST_H_

#include <cstdint>
#include <string>

#include "audio_file_decode_core.h"

namespace whispaste {

// True when libgstreamer, libgstapp and the elements filesrc, decodebin,
// audioconvert, audioresample, appsink, qtdemux and an AAC decoder exist.
bool GstAacAvailable();

// Decodes [input_path] to mono 16 kHz int16 LE PCM at [output_path].
DecodeOutcome DecodeAacWithGstreamer(const std::string& input_path,
                                     const std::string& output_path,
                                     int64_t max_frames);

}  // namespace whispaste

#endif  // WHISPASTE_AUDIO_FILE_DECODE_GST_H_
