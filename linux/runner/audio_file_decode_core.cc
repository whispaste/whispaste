// Streaming decode of Ogg/Opus, FLAC and MP3 to 16 kHz mono int16 PCM.
// See audio_file_decode_core.h for the contract.
// libFLAC is linked only where the platform decoder cannot read FLAC. macOS
// (AVFoundation) and Windows (Media Foundation) decode FLAC natively, so their
// builds define WP_WITH_FLAC=0 and only the Ogg/Opus and MP3 paths remain.
#ifndef WP_WITH_FLAC
#define WP_WITH_FLAC 1
#endif

#include "audio_file_decode_core.h"
#include "audio_file_decode_gst.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

#if WP_WITH_FLAC
#include <FLAC/stream_decoder.h>
#endif
#include <opusfile.h>

#define MINIMP3_IMPLEMENTATION
#define MINIMP3_NO_SIMD
// Vendored third-party decoder: its conversion warnings are not ours to fix,
// and the Windows build treats warnings as errors (/WX).
#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4244 4267 4456 4459)
#endif
#include "third_party/minimp3/minimp3_ex.h"
#ifdef _MSC_VER
#pragma warning(pop)
#endif

namespace whispaste {
namespace {

constexpr double kPi = 3.14159265358979323846;
// Half-width of the resampling kernel in output-rate taps (before scaling by
// the downsampling ratio). 8 gives a stopband that is inaudible for speech.
constexpr int kHalfTaps = 8;
// Phases of the fractional input position. Quantisation error at 256 phases is
// far below the 16-bit output resolution.
constexpr int kPhases = 256;
// Largest Opus packet is 120 ms; at the 48 kHz Opus rate that is 5760 samples
// per channel. libopusfile is asked for up to 8 channels (multichannel
// mapping family), so the buffer covers 8 channels in both sample units.
constexpr int kOpusMaxFrames = 5760;
constexpr int kOpusMaxChannels = 8;

// Windowed-sinc streaming resampler from an arbitrary input rate to 16 kHz.
// Keeps only the input samples a pending output sample still needs.
// Opens a UTF-8 path. Windows needs the wide-character CRT, because the ANSI
// code page cannot name every file the user picks.
FILE* OpenUtf8(const std::string& path, const char* mode) {
#ifdef _WIN32
  const int wide_size =
      MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, nullptr, 0);
  if (wide_size <= 0) return nullptr;
  std::wstring wide_path(static_cast<size_t>(wide_size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, path.c_str(), -1, wide_path.data(),
                      wide_size);
  const std::wstring wide_mode(mode, mode + std::strlen(mode));
  FILE* file = nullptr;
  if (_wfopen_s(&file, wide_path.c_str(), wide_mode.c_str()) != 0) return nullptr;
  return file;
#else
  return std::fopen(path.c_str(), mode);
#endif
}

class Resampler {
 public:
  explicit Resampler(double in_rate)
      : ratio_(in_rate / kCoreSampleRate),
        half_(static_cast<int>(
            std::ceil(kHalfTaps * std::max(1.0, ratio_)))) {
    // Cutoff in cycles per input sample, just under the output Nyquist and
    // never above the input Nyquist (upsampling from 8 kHz).
    const double cutoff = 0.5 * std::min(1.0, 1.0 / ratio_) * 0.95;
    taps_ = 2 * half_;
    table_.assign(static_cast<size_t>(kPhases) * taps_, 0.0f);
    for (int p = 0; p < kPhases; ++p) {
      const double frac = static_cast<double>(p) / kPhases;
      double sum = 0.0;
      for (int j = -half_ + 1; j <= half_; ++j) {
        const double d = frac - j;  // distance from the input tap
        double w = 0.0;
        if (std::fabs(d) < half_) {
          const double sinc = std::fabs(d) < 1e-12
                                  ? 2.0 * cutoff
                                  : std::sin(2.0 * kPi * cutoff * d) /
                                        (kPi * d);
          const double hann = 0.5 + 0.5 * std::cos(kPi * d / half_);
          w = sinc * hann;
        }
        table_[static_cast<size_t>(p) * taps_ + (j + half_ - 1)] =
            static_cast<float>(w);
        sum += w;
      }
      // Unity gain at DC per phase.
      for (int t = 0; t < taps_; ++t) {
        table_[static_cast<size_t>(p) * taps_ + t] /=
            static_cast<float>(sum);
      }
    }
  }

  // Appends mono input and emits every output sample that is complete.
  void Push(const float* samples, size_t n, std::vector<float>* out) {
    buf_.insert(buf_.end(), samples, samples + n);
    total_in_ += static_cast<int64_t>(n);
    while (true) {
      const double t = static_cast<double>(next_out_) * ratio_;
      const int64_t base = static_cast<int64_t>(std::floor(t));
      if (base + half_ >= total_in_) break;  // need more input
      out->push_back(Interpolate(t));
      ++next_out_;
    }
    Trim();
  }

  // Emits the trailing outputs, padding the input with silence.
  void Finish(std::vector<float>* out) {
    while (static_cast<double>(next_out_) * ratio_ < total_in_) {
      out->push_back(Interpolate(static_cast<double>(next_out_) * ratio_));
      ++next_out_;
    }
  }

 private:
  float Interpolate(double t) {
    int64_t base = static_cast<int64_t>(std::floor(t));
    const double frac = t - static_cast<double>(base);
    int phase = static_cast<int>(std::floor(frac * kPhases + 0.5));
    if (phase == kPhases) {
      phase = 0;
      ++base;
    }
    const float* w = &table_[static_cast<size_t>(phase) * taps_];
    float acc = 0.0f;
    for (int j = -half_ + 1; j <= half_; ++j) {
      acc += w[j + half_ - 1] * Sample(base + j);
    }
    return acc;
  }

  float Sample(int64_t index) const {
    const int64_t pos = index - origin_;
    if (pos < 0 || pos >= static_cast<int64_t>(buf_.size())) return 0.0f;
    return buf_[static_cast<size_t>(pos)];
  }

  // Drops input that no later output sample can reach.
  void Trim() {
    const double t = static_cast<double>(next_out_) * ratio_;
    const int64_t keep_from =
        static_cast<int64_t>(std::floor(t)) - half_ + 1;
    const int64_t drop = keep_from - origin_;
    if (drop > 65536) {
      buf_.erase(buf_.begin(), buf_.begin() + drop);
      origin_ += drop;
    }
  }

  double ratio_;
  int half_;
  int taps_ = 0;
  std::vector<float> table_;
  std::vector<float> buf_;
  int64_t origin_ = 0;  // absolute input index of buf_[0]
  int64_t total_in_ = 0;
  int64_t next_out_ = 0;
};

// Downmixes interleaved float input to mono, resamples to 16 kHz and writes
// int16 LE PCM. Enforces the frame limit.
class Mono16kWriter {
 public:
  Mono16kWriter(FILE* out, double in_rate, int64_t max_frames)
      : out_(out), resampler_(in_rate), max_frames_(max_frames) {}

  // Returns false when writing failed or the frame limit was exceeded.
  bool Write(const float* interleaved, size_t frames, int channels) {
    mono_.resize(frames);
    const float scale = 1.0f / static_cast<float>(channels);
    for (size_t i = 0; i < frames; ++i) {
      float sum = 0.0f;
      for (int c = 0; c < channels; ++c) {
        sum += interleaved[i * channels + c];
      }
      mono_[i] = sum * scale;
    }
    resampled_.clear();
    resampler_.Push(mono_.data(), mono_.size(), &resampled_);
    return Emit();
  }

  bool Finish() {
    resampled_.clear();
    resampler_.Finish(&resampled_);
    return Emit();
  }

  int64_t frames() const { return frames_; }
  bool limit_hit() const { return limit_hit_; }

 private:
  bool Emit() {
    if (resampled_.empty()) return true;
    if (frames_ + static_cast<int64_t>(resampled_.size()) > max_frames_) {
      const int64_t room = max_frames_ - frames_;
      resampled_.resize(static_cast<size_t>(std::max<int64_t>(room, 0)));
      limit_hit_ = true;
    }
    pcm_.resize(resampled_.size());
    for (size_t i = 0; i < resampled_.size(); ++i) {
      const float v = std::round(resampled_[i] * 32767.0f);
      pcm_[i] = static_cast<int16_t>(std::clamp(v, -32768.0f, 32767.0f));
    }
    if (!pcm_.empty() &&
        std::fwrite(pcm_.data(), sizeof(int16_t), pcm_.size(), out_) !=
            pcm_.size()) {
      return false;
    }
    frames_ += static_cast<int64_t>(pcm_.size());
    return !limit_hit_;
  }

  FILE* out_;
  Resampler resampler_;
  int64_t max_frames_;
  int64_t frames_ = 0;
  bool limit_hit_ = false;
  std::vector<float> mono_;
  std::vector<float> resampled_;
  std::vector<int16_t> pcm_;
};

DecodeOutcome Fail(DecodeStatus status, const std::string& message,
                   int64_t frames = 0) {
  DecodeOutcome o;
  o.status = status;
  o.frames = frames;
  o.message = message;
  return o;
}

// A stream that decodes to nothing (header only, or corrupt from the first
// packet) is a failure; a stream that stops early keeps its decoded prefix,
// the same way truncated WAV data is handled.
DecodeOutcome Finalise(Mono16kWriter* writer, bool write_ok) {
  if (!writer->Finish() || !write_ok) {
    if (writer->limit_hit()) {
      return Fail(DecodeStatus::kInputLimit, "audio longer than the limit",
                  writer->frames());
    }
    return Fail(DecodeStatus::kIoError, "cannot write decoded audio",
                writer->frames());
  }
  if (writer->limit_hit()) {
    return Fail(DecodeStatus::kInputLimit, "audio longer than the limit",
                writer->frames());
  }
  if (writer->frames() == 0) {
    return Fail(DecodeStatus::kDecodeFailed, "no audio decoded");
  }
  DecodeOutcome o;
  o.status = DecodeStatus::kOk;
  o.frames = writer->frames();
  return o;
}

#ifdef _WIN32
int StreamRead(void* stream, unsigned char* ptr, int bytes) {
  FILE* f = static_cast<FILE*>(stream);
  const size_t got = std::fread(ptr, 1, static_cast<size_t>(bytes), f);
  return got == 0 && std::ferror(f) ? -1 : static_cast<int>(got);
}

int StreamSeek(void* stream, opus_int64 offset, int whence) {
  return _fseeki64(static_cast<FILE*>(stream), offset, whence);
}

opus_int64 StreamTell(void* stream) {
  return _ftelli64(static_cast<FILE*>(stream));
}

int StreamClose(void* stream) {
  return std::fclose(static_cast<FILE*>(stream));
}

const OpusFileCallbacks kFileCallbacks = {StreamRead, StreamSeek, StreamTell,
                                          StreamClose};

// op_open_callbacks does not close the stream when it fails, so the caller
// does (op_open_file would use the ANSI code page on Windows).
OggOpusFile* OpenOpusFile(const std::string& path, int* err) {
  FILE* f = OpenUtf8(path, "rb");
  if (!f) {
    *err = OP_EFAULT;
    return nullptr;
  }
  OggOpusFile* of = op_open_callbacks(f, &kFileCallbacks, nullptr, 0, err);
  if (!of) std::fclose(f);
  return of;
}
#else
OggOpusFile* OpenOpusFile(const std::string& path, int* err) {
  return op_open_file(path.c_str(), err);
}
#endif

DecodeOutcome DecodeOpus(const std::string& path, FILE* out,
                         int64_t max_frames) {
  // libopusfile needs the stream's last granule position to open a file, so a
  // truncated Ogg/Opus file is refused here (OP_EBADTIMESTAMP) rather than
  // decoded partially. Known limitation, see docs/adr for WP-35b.
  int err = 0;
  OggOpusFile* of = OpenOpusFile(path, &err);
  if (!of) {
    // A valid Ogg/Vorbis stream is recognised by its Vorbis identification
    // header and reported as unsupported; any other Ogg data is corrupt.
    static const char kVorbisId[] = "\x01vorbis";
    unsigned char head[512] = {0};
    if (FILE* f = OpenUtf8(path, "rb")) {
      const size_t got = std::fread(head, 1, sizeof(head), f);
      std::fclose(f);
      const auto end = head + got;
      if (std::search(head, end, kVorbisId, kVorbisId + 7) != end) {
        return Fail(DecodeStatus::kUnsupportedFormat,
                    "Ogg/Vorbis is not supported");
      }
    }
    return Fail(DecodeStatus::kDecodeFailed, "cannot open Opus stream");
  }
  const int channels = op_channel_count(of, -1);
  if (channels <= 0 || channels > kOpusMaxChannels) {
    op_free(of);
    return Fail(DecodeStatus::kDecodeFailed, "invalid Opus channel count");
  }
  Mono16kWriter writer(out, 48000.0, max_frames);
  // Opus always decodes to 48 kHz regardless of the original input rate.
  std::vector<float> buf(static_cast<size_t>(kOpusMaxFrames) *
                         kOpusMaxChannels * kOpusMaxChannels);
  bool write_ok = true;
  while (write_ok && !writer.limit_hit()) {
    const int n = op_read_float(of, buf.data(),
                                kOpusMaxFrames * kOpusMaxChannels, nullptr);
    if (n == 0) break;  // end of stream
    if (n == OP_HOLE) continue;  // lost packet: keep going, like playback
    if (n < 0) break;            // decoding error: keep the prefix
    write_ok = writer.Write(buf.data(), static_cast<size_t>(n), channels);
  }
  op_free(of);
  return Finalise(&writer, write_ok);
}

#if WP_WITH_FLAC
struct FlacContext {
  FILE* out = nullptr;
  int64_t max_frames = 0;
  std::unique_ptr<Mono16kWriter> writer;
  int channels = 0;
  int bits = 0;
  bool write_ok = true;
  // STREAMINFO with no usable rate or channel count: the stream is refused.
  bool bad_stream_info = false;
  std::vector<float> tmp;
};

void FlacMetadata(const FLAC__StreamDecoder*, const FLAC__StreamMetadata* md,
                  void* client) {
  if (md->type != FLAC__METADATA_TYPE_STREAMINFO) return;
  auto* ctx = static_cast<FlacContext*>(client);
  // A zero rate would make the resampler ratio zero or infinite.
  if (md->data.stream_info.sample_rate == 0 ||
      md->data.stream_info.channels == 0) {
    ctx->bad_stream_info = true;
    return;
  }
  ctx->channels = static_cast<int>(md->data.stream_info.channels);
  ctx->bits = static_cast<int>(md->data.stream_info.bits_per_sample);
  ctx->writer = std::make_unique<Mono16kWriter>(
      ctx->out, static_cast<double>(md->data.stream_info.sample_rate),
      ctx->max_frames);
}

FLAC__StreamDecoderWriteStatus FlacWrite(const FLAC__StreamDecoder*,
                                         const FLAC__Frame* frame,
                                         const FLAC__int32* const buffer[],
                                         void* client) {
  auto* ctx = static_cast<FlacContext*>(client);
  if (!ctx->writer || ctx->channels <= 0) {
    return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
  }
  const size_t blocksize = frame->header.blocksize;
  const int channels = ctx->channels;
  ctx->tmp.resize(blocksize * channels);
  const float scale = 1.0f / static_cast<float>(1LL << (ctx->bits - 1));
  for (size_t i = 0; i < blocksize; ++i) {
    for (int c = 0; c < channels; ++c) {
      ctx->tmp[i * channels + c] = static_cast<float>(buffer[c][i]) * scale;
    }
  }
  ctx->write_ok = ctx->writer->Write(ctx->tmp.data(), blocksize, channels);
  return ctx->write_ok ? FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE
                       : FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
}

void FlacError(const FLAC__StreamDecoder*, FLAC__StreamDecoderErrorStatus,
               void*) {
  // Errors end the stream; the decoded prefix is kept (see Finalise).
}

DecodeOutcome DecodeFlac(const std::string& path, FILE* out,
                         int64_t max_frames) {
  FlacContext ctx;
  ctx.out = out;
  ctx.max_frames = max_frames;
  FLAC__StreamDecoder* dec = FLAC__stream_decoder_new();
  if (!dec) return Fail(DecodeStatus::kIoError, "cannot allocate FLAC decoder");
  FLAC__stream_decoder_set_md5_checking(dec, false);
  FLAC__StreamDecoderInitStatus init = FLAC__stream_decoder_init_file(
      dec, path.c_str(), FlacWrite, FlacMetadata, FlacError, &ctx);
  if (init != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
    FLAC__stream_decoder_delete(dec);
    return Fail(DecodeStatus::kDecodeFailed, "cannot open FLAC stream");
  }
  FLAC__stream_decoder_process_until_end_of_stream(dec);
  FLAC__stream_decoder_finish(dec);
  FLAC__stream_decoder_delete(dec);
  if (ctx.bad_stream_info) {
    return Fail(DecodeStatus::kDecodeFailed, "invalid FLAC sample rate or channels");
  }
  if (!ctx.writer) return Fail(DecodeStatus::kDecodeFailed, "no FLAC header");
  return Finalise(ctx.writer.get(), ctx.write_ok);
}

#endif  // WP_WITH_FLAC

size_t Mp3Read(void* buf, size_t size, void* user) {
  return std::fread(buf, 1, size, static_cast<FILE*>(user));
}

int Mp3Seek(uint64_t position, void* user) {
  return std::fseek(static_cast<FILE*>(user), static_cast<long>(position),
                    SEEK_SET);
}

DecodeOutcome DecodeMp3(const std::string& path, FILE* out,
                        int64_t max_frames) {
  FILE* in = OpenUtf8(path, "rb");
  if (!in) return Fail(DecodeStatus::kIoError, "cannot reopen input");
  mp3dec_io_t io{};
  io.read = Mp3Read;
  io.seek = Mp3Seek;
  io.read_data = in;
  io.seek_data = in;
  auto dec = std::make_unique<mp3dec_ex_t>();
  if (mp3dec_ex_open_cb(dec.get(), &io, MP3D_DO_NOT_SCAN) != 0) {
    std::fclose(in);
    return Fail(DecodeStatus::kDecodeFailed, "cannot open MP3 stream");
  }
  const int channels = dec->info.channels;
  const double rate = static_cast<double>(dec->info.hz);
  if (channels <= 0 || rate <= 0) {
    mp3dec_ex_close(dec.get());
    std::fclose(in);
    return Fail(DecodeStatus::kDecodeFailed, "invalid MP3 header");
  }
  Mono16kWriter writer(out, rate, max_frames);
  std::vector<mp3d_sample_t> pcm(MINIMP3_MAX_SAMPLES_PER_FRAME * 4);
  std::vector<float> tmp;
  bool write_ok = true;
  while (write_ok && !writer.limit_hit()) {
    const size_t n = mp3dec_ex_read(dec.get(), pcm.data(), pcm.size());
    if (n == 0) break;
    const size_t frames = n / channels;
    tmp.resize(frames * channels);
    for (size_t i = 0; i < frames * channels; ++i) {
      tmp[i] = static_cast<float>(pcm[i]) / 32768.0f;
    }
    write_ok = writer.Write(tmp.data(), frames, channels);
  }
  mp3dec_ex_close(dec.get());
  std::fclose(in);
  return Finalise(&writer, write_ok);
}

}  // namespace

DecodeOutcome DecodeCompressedToRawPcm16(const std::string& input_path,
                                         const std::string& output_path,
                                         int64_t max_frames) {
  FILE* in = OpenUtf8(input_path, "rb");
  if (!in) return Fail(DecodeStatus::kIoError, "cannot open input");
  unsigned char head[64] = {0};
  const size_t got = std::fread(head, 1, sizeof(head), in);
  std::fclose(in);

  enum class Kind { kOpus, kFlac, kMp3, kUnknown } kind = Kind::kUnknown;
  if (got >= 4 && std::memcmp(head, "OggS", 4) == 0) {
    kind = Kind::kOpus;
  } else if (got >= 4 && std::memcmp(head, "fLaC", 4) == 0) {
#if WP_WITH_FLAC
    kind = Kind::kFlac;
#else
    return Fail(DecodeStatus::kUnsupportedFormat,
                "FLAC is decoded by the platform in this build");
#endif
  } else if (got >= 3 && std::memcmp(head, "ID3", 3) == 0) {
    kind = Kind::kMp3;
  } else if (got >= 2 && head[0] == 0xFF && (head[1] & 0xE0) == 0xE0) {
    kind = Kind::kMp3;
  }
  if (kind == Kind::kUnknown) {
    if (got >= 8 && std::memcmp(head + 4, "ftyp", 4) == 0) {
#ifdef _WIN32
      // Windows sends M4A/AAC to Media Foundation in the host; GStreamer is not built here.
      return Fail(DecodeStatus::kUnsupportedFormat,
                  "M4A/AAC is decoded by the platform in this build");
#else
      // M4A/AAC: GStreamer at runtime, never linked (see audio_file_decode_gst.h).
      return DecodeAacWithGstreamer(input_path, output_path, max_frames);
#endif
    }
    return Fail(DecodeStatus::kUnsupportedFormat, "unrecognised audio format");
  }

  FILE* out = OpenUtf8(output_path, "wb");
  if (!out) return Fail(DecodeStatus::kIoError, "cannot create output");
  DecodeOutcome outcome;
  switch (kind) {
    case Kind::kOpus:
      outcome = DecodeOpus(input_path, out, max_frames);
      break;
    case Kind::kFlac:
#if WP_WITH_FLAC
      outcome = DecodeFlac(input_path, out, max_frames);
#endif
      break;
    case Kind::kMp3:
      outcome = DecodeMp3(input_path, out, max_frames);
      break;
    case Kind::kUnknown:
      break;
  }
  if (std::fclose(out) != 0 && outcome.status == DecodeStatus::kOk) {
    outcome = Fail(DecodeStatus::kIoError, "cannot finish output file");
  }
  return outcome;
}

}  // namespace whispaste
