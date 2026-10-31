// Headless test for the Linux audio import decoder (WP-35b). Runs without GTK:
// test/scripts/audio_file_decode_test.sh compiles it against the core and the
// fixtures in test/fixtures/audio_import/.
//
// Usage: audio_file_decode_test <fixture_dir> <scratch_dir>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>

#include "audio_file_decode_core.h"
#include "audio_file_decode_gst.h"

namespace {

using whispaste::DecodeCompressedToRawPcm16;
using whispaste::DecodeOutcome;
using whispaste::DecodeStatus;

int failures = 0;

void Check(bool ok, const std::string& what) {
  if (!ok) {
    ++failures;
    std::printf("FAIL: %s\n", what.c_str());
  }
}

// RMS of the decoded 16 kHz mono output, in full-scale units.
double RmsOf(const std::string& path, int64_t frames) {
  std::FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return -1.0;
  std::vector<int16_t> pcm(static_cast<size_t>(frames));
  const size_t got = std::fread(pcm.data(), sizeof(int16_t), pcm.size(), f);
  std::fclose(f);
  if (got == 0) return -1.0;
  // Skip the first 0.1 s so codec start-up transients do not count.
  const size_t skip = std::min<size_t>(1600, got / 4);
  double sum = 0.0;
  for (size_t i = skip; i < got; ++i) {
    const double v = pcm[i] / 32768.0;
    sum += v * v;
  }
  return std::sqrt(sum / static_cast<double>(got - skip));
}

// Expected RMS of a 0.5-amplitude sine: 0.5 / sqrt(2).
constexpr double kSineRms = 0.5 / 1.41421356237;

std::string Join(const std::string& a, const std::string& b) {
  return a + "/" + b;
}

// Decodes a full fixture and checks frame count and level of the tone.
void ExpectTone(const std::string& dir, const std::string& scratch,
                const char* name, int64_t expected_frames, double tolerance,
                double level_tolerance = 0.05) {
  const std::string out = Join(scratch, std::string(name) + ".raw");
  const DecodeOutcome o =
      DecodeCompressedToRawPcm16(Join(dir, name), out, 1LL << 40);
  Check(o.status == DecodeStatus::kOk,
        std::string(name) + ": expected OK, got " + o.message);
  if (o.status != DecodeStatus::kOk) return;
  const double rel =
      std::fabs(static_cast<double>(o.frames - expected_frames)) /
      static_cast<double>(expected_frames);
  Check(rel <= tolerance, std::string(name) + ": frames " +
                              std::to_string(o.frames) + " not near " +
                              std::to_string(expected_frames));
  const double rms = RmsOf(out, o.frames);
  Check(std::fabs(rms - kSineRms) / kSineRms < level_tolerance,
        std::string(name) + ": level " + std::to_string(rms) +
            " not near the 440 Hz tone");
  std::remove(out.c_str());
}

// A FLAC file whose only STREAMINFO block declares sample rate 0 (1 channel,
// 16 bit, no samples). libFLAC accepts the header; the decoder must refuse it.
void WriteZeroRateFlac(const std::string& path) {
  const unsigned char bytes[] = {
      'f', 'L', 'a', 'C',
      0x80, 0x00, 0x00, 0x22,  // last metadata block, STREAMINFO, 34 bytes
      0x10, 0x00, 0x10, 0x00,  // min/max block size 4096
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00,  // min/max frame size unknown
      0x00, 0x00, 0x00, 0xF0,  // sample rate 0, channels 1, 16 bit (bits 0-27)
      0x00, 0x00, 0x00, 0x00,  // total samples 0
  };
  std::FILE* f = std::fopen(path.c_str(), "wb");
  Check(f != nullptr, "cannot write " + path);
  std::fwrite(bytes, 1, sizeof(bytes), f);
  const unsigned char md5[16] = {0};  // unset MD5 signature
  std::fwrite(md5, 1, sizeof(md5), f);
  std::fclose(f);
}

void ExpectStatus(const std::string& dir, const std::string& scratch,
                  const char* name, DecodeStatus want) {
  const std::string out = Join(scratch, std::string(name) + ".raw");
  const DecodeOutcome o =
      DecodeCompressedToRawPcm16(Join(dir, name), out, 1LL << 40);
  Check(o.status == want, std::string(name) + ": wrong status, message: " +
                              o.message);
  std::remove(out.c_str());
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 3) {
    std::fprintf(stderr, "usage: %s <fixture_dir> <scratch_dir>\n", argv[0]);
    return 2;
  }
  const std::string dir = argv[1];
  const std::string scratch = argv[2];

  // One second of tone at 16 kHz output; codec delay gets a wider tolerance.
  ExpectTone(dir, scratch, "tone1s_stereo44.flac", 16000, 0.01);
  ExpectTone(dir, scratch, "tone1s_stereo44.opus", 16000, 0.02);
  // Lossy MP3 with encoder delay: looser level tolerance (about 5 % measured).
  ExpectTone(dir, scratch, "tone1s_stereo44.mp3", 16000, 0.05, 0.08);
  ExpectTone(dir, scratch, "tone1s_mono16.opus", 16000, 0.02);

  // Platform gaps and non-audio input.
  // M4A/AAC needs GStreamer at runtime. Without it the status is
  // kUnavailable, with it the 0.5 s fixture decodes to 8000 frames.
  if (whispaste::GstAacAvailable()) {
    // The 0.5 s fixtures sit at about 0.06 RMS (same generator as the FLAC and
    // MP3 fixtures), so only check the frame count and a non-silent level.
    const std::string out = Join(scratch, "tone_stereo_44k.m4a.raw");
    const DecodeOutcome o = DecodeCompressedToRawPcm16(
        Join(dir, "tone_stereo_44k.m4a"), out, 1LL << 40);
    Check(o.status == DecodeStatus::kOk,
          "tone_stereo_44k.m4a: expected OK, got " + o.message);
    if (o.status == DecodeStatus::kOk) {
      Check(std::llabs(o.frames - 8000) <= 400,
            "tone_stereo_44k.m4a: frames " + std::to_string(o.frames));
      Check(RmsOf(out, o.frames) > 0.05, "tone_stereo_44k.m4a: silent output");
    }
    std::remove(out.c_str());
  } else {
    ExpectStatus(dir, scratch, "tone_stereo_44k.m4a",
                 DecodeStatus::kUnavailable);
  }
  ExpectStatus(dir, scratch, "not_audio.txt",
               DecodeStatus::kUnsupportedFormat);

  // Defective input: no audio at all is a decode failure.
  ExpectStatus(dir, scratch, "corrupt_header.opus",
               DecodeStatus::kDecodeFailed);
  ExpectStatus(dir, scratch, "does_not_exist.opus", DecodeStatus::kIoError);

  // Truncated Ogg/Opus cannot be opened by libopusfile: decode failure.
  ExpectStatus(dir, scratch, "tone1s_stereo44_truncated.opus",
               DecodeStatus::kDecodeFailed);

  // STREAMINFO with sample rate 0 would make the resampler ratio undefined.
  WriteZeroRateFlac(Join(scratch, "zero_rate.flac"));
  ExpectStatus(scratch, scratch, "zero_rate.flac", DecodeStatus::kDecodeFailed);

  // Truncated FLAC keeps the decodable prefix, like truncated WAV data.
  for (const char* name : {"tone1s_stereo44_truncated.flac"}) {
    const std::string out = Join(scratch, std::string(name) + ".raw");
    const DecodeOutcome o =
        DecodeCompressedToRawPcm16(Join(dir, name), out, 1LL << 40);
    Check(o.status == DecodeStatus::kOk && o.frames > 0 && o.frames < 15000,
          std::string(name) + ": expected a partial result, got " +
              std::to_string(o.frames) + " frames");
    std::remove(out.c_str());
  }

  // Duration limit: the output stops and reports INPUT_LIMIT.
  {
    const std::string out = Join(scratch, "limit.raw");
    const DecodeOutcome o = DecodeCompressedToRawPcm16(
        Join(dir, "tone1s_stereo44.flac"), out, 1000);
    Check(o.status == DecodeStatus::kInputLimit,
          "limit: expected INPUT_LIMIT");
    std::remove(out.c_str());
  }

  if (failures == 0) std::puts("audio_file_decode_test: OK");
  return failures == 0 ? 0 : 1;
}
