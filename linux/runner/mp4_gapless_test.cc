// Native tests for the MP4 gapless parser (WP-35b). Built and run by
// test/scripts/audio_file_decode_test.sh together with the fixtures.
//
// Usage: mp4_gapless_test <fixture_dir>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

#include "mp4_gapless.h"

namespace {

using Bytes = std::vector<uint8_t>;
using whispaste::Mp4Gapless;

int failures = 0;

void Check(bool ok, const std::string& what) {
  if (!ok) {
    ++failures;
    std::printf("FAIL: %s\n", what.c_str());
  }
}

void Append(Bytes* out, const Bytes& more) {
  out->insert(out->end(), more.begin(), more.end());
}

Bytes U32(uint32_t v) {
  return {static_cast<uint8_t>(v >> 24), static_cast<uint8_t>(v >> 16),
          static_cast<uint8_t>(v >> 8), static_cast<uint8_t>(v)};
}

Bytes U64(uint64_t v) {
  Bytes out = U32(static_cast<uint32_t>(v >> 32));
  Append(&out, U32(static_cast<uint32_t>(v)));
  return out;
}

Bytes Str(const std::string& s) { return Bytes(s.begin(), s.end()); }

Bytes Cat(std::initializer_list<Bytes> parts) {
  Bytes out;
  for (const Bytes& p : parts) Append(&out, p);
  return out;
}

Bytes Box(const std::string& type, const Bytes& body) {
  Bytes out = U32(static_cast<uint32_t>(8 + body.size()));
  Append(&out, Str(type));
  Append(&out, body);
  return out;
}

// Version-0 full box header (version 0, flags 0).
Bytes FullHeader() { return {0, 0, 0, 0}; }

Bytes Mvhd(uint32_t timescale) {
  // version 0: version/flags, creation, modification, timescale, duration.
  return Box("mvhd", Cat({FullHeader(), U32(0), U32(0), U32(timescale),
                          U32(0)}));
}

Bytes Mdhd(uint32_t timescale) {
  return Box("mdhd", Cat({FullHeader(), U32(0), U32(0), U32(timescale),
                          U32(0)}));
}

Bytes Hdlr(const std::string& handler) {
  return Box("hdlr", Cat({FullHeader(), U32(0), Str(handler), U32(0), U32(0),
                          U32(0), Bytes{0}}));
}

// elst version 0 with one entry per (duration, media_time) pair.
Bytes ElstV0(uint32_t duration, int32_t media_time) {
  return Box("elst", Cat({FullHeader(), U32(1), U32(duration),
                          U32(static_cast<uint32_t>(media_time)), U32(0x10000)}));
}

Bytes ElstV1(uint64_t duration, int64_t media_time) {
  return Box("elst", Cat({Bytes{1, 0, 0, 0}, U32(1), U64(duration),
                          U64(static_cast<uint64_t>(media_time)), U32(0x10000)}));
}

Bytes AudioTrak(uint32_t track_timescale, const Bytes& edts) {
  return Box("trak", Cat({Box("mdia", Cat({Mdhd(track_timescale),
                                           Hdlr("soun")})),
                          edts}));
}

Bytes Moov(uint32_t movie_timescale, const Bytes& trak, const Bytes& udta = {}) {
  return Box("moov", Cat({Mvhd(movie_timescale), trak, udta}));
}

// moov/udta/meta/ilst/----(name iTunSMPB, data text).
Bytes ItunSmpbUdta(const std::string& text) {
  const Bytes name = Box("name", Cat({FullHeader(), Str("iTunSMPB")}));
  const Bytes data = Box("data", Cat({U32(1), U32(0), Str(text)}));
  const Bytes freeform = Box("----", Cat({name, data}));
  return Box("udta", Box("meta", Cat({FullHeader(), Box("ilst", freeform)})));
}

// |moov| is a whole moov box; the parser takes its payload.
Mp4Gapless Parse(const Bytes& moov) {
  if (moov.size() < 8) return Mp4Gapless{};
  return whispaste::ParseMp4GaplessMoov(moov.data() + 8, moov.size() - 8);
}

void TestEdtsV0() {
  const Bytes edts = Box("edts", ElstV0(500, 1024));
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, edts)));
  Check(g.rate == 44100, "edts v0: rate");
  Check(g.priming == 1024, "edts v0: priming");
  Check(g.total == 22050, "edts v0: total (500 ms at 44.1 kHz)");
}

void TestEdtsV1() {
  const Bytes edts = Box("edts", ElstV1(500, 1024));
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, edts)));
  Check(g.rate == 44100 && g.priming == 1024 && g.total == 22050,
        "edts v1: 64-bit entries");
}

void TestItunSmpbFallback() {
  // Hex fields: priming 0x420 = 1056, total 0x5514 = 21780.
  const Bytes udta = ItunSmpbUdta(
      " 00000000 00000420 000001A4 0000000000005514 00000000 00000000");
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, {}), udta));
  Check(g.rate == 44100, "iTunSMPB: rate from the audio track");
  Check(g.priming == 0x420, "iTunSMPB: priming");
  Check(g.total == 0x5514, "iTunSMPB: total");
}

void TestNoAudioTrack() {
  const Bytes video = Box("trak", Box("mdia", Cat({Mdhd(90000),
                                                   Hdlr("vide")})));
  const Mp4Gapless g = Parse(Moov(1000, video));
  Check(g.rate == 0 && g.priming == 0 && g.total == 0,
        "no audio track: nothing trimmed");
}

void TestCountTooLarge() {
  Bytes elst = Box("elst", Cat({FullHeader(), U32(0xFFFFFFFFu), U32(500),
                                U32(1024), U32(0x10000)}));
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, Box("edts", elst))));
  Check(g.rate == 44100 && g.priming == 0 && g.total == 0,
        "elst entry count beyond the box: ignored");
}

void TestNonHexItunSmpb() {
  const Bytes udta = ItunSmpbUdta(" 00000000 0000042Z 00000000 000000000000");
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, {}), udta));
  Check(g.priming == 0 && g.total == 0, "iTunSMPB with non-hex text: ignored");
}

void TestWideItunSmpbFieldIgnored() {
  // A 16-digit priming field and a 16-digit total both overflow the frame
  // arithmetic: each is refused.
  const Bytes wide_priming = ItunSmpbUdta(
      " 00000000 FFFFFFFFFFFFFFFF 00000000 0000000000005514");
  const Mp4Gapless a = Parse(Moov(1000, AudioTrak(44100, {}), wide_priming));
  Check(a.priming == 0 && a.total == 0,
        "iTunSMPB with a 64-bit priming field: ignored");
  const Bytes wide_total = ItunSmpbUdta(
      " 00000000 00000420 00000000 FFFFFFFFFFFFFFFF");
  const Mp4Gapless b = Parse(Moov(1000, AudioTrak(44100, {}), wide_total));
  Check(b.priming == 0 && b.total == 0,
        "iTunSMPB with a total beyond 2^44 samples: ignored");
}

void TestPrimingBeyondTotal() {
  const Bytes edts = Box("edts", ElstV0(10, 5000));  // 10 ms of audio
  const Mp4Gapless g = Parse(Moov(1000, AudioTrak(44100, edts)));
  Check(g.rate == 0, "priming larger than the length: nothing trimmed");
}

void TestOversizedBox() {
  Bytes moov = Moov(1000, AudioTrak(44100, Box("edts", ElstV0(500, 1024))));
  // The trak box is the second child: its size field claims far more bytes
  // than the container holds. The walk must stop there, not read past it.
  const size_t trak_at = 8 + Mvhd(1000).size();  // moov header + mvhd box
  moov[trak_at] = 0xFF;
  moov[trak_at + 1] = 0xFF;
  const Mp4Gapless g = Parse(moov);
  Check(g.rate == 0, "oversized trak box: nothing trimmed, no overread");
}

// Every truncation of a valid moov must parse without reading past the end
// (AddressSanitizer checks this when the test is built with it).
void TestTruncations() {
  const Bytes edts = Box("edts", ElstV0(500, 1024));
  const Bytes moov = Moov(1000, AudioTrak(44100, edts),
                          ItunSmpbUdta(" 00000000 00000420 0 0000000000005514"));
  for (size_t n = 0; n < moov.size(); ++n) {
    const Bytes prefix(moov.begin(), moov.begin() + static_cast<long>(n));
    const Mp4Gapless g = Parse(prefix);
    if (g.rate != 0 && g.total != 0) {
      Check(g.priming <= g.total, "truncated moov: priming within total");
    }
  }
  Check(Parse(moov).rate == 44100, "untruncated moov still parses");
}

void TestFile(const std::string& dir) {
  const std::string m4a = dir + "/tone_stereo_44k.m4a";
  std::FILE* f = std::fopen(m4a.c_str(), "rb");
  Check(f != nullptr, "fixture present: tone_stereo_44k.m4a");
  if (f) {
    const Mp4Gapless g = whispaste::ReadMp4Gapless(f);
    std::fclose(f);
    // The fixture is a 0.5 s AAC file at 44.1 kHz with 1024 samples priming.
    Check(g.rate == 44100, "fixture m4a: rate");
    Check(g.priming == 1024, "fixture m4a: priming");
    Check(g.total == 22050, "fixture m4a: total");
  }

  // A cut-off copy of the same file: the moov is missing, so nothing trimmed.
  const std::string cut = dir + "/../mp4_gapless_cut.m4a";
  std::FILE* in = std::fopen(m4a.c_str(), "rb");
  if (in) {
    std::FILE* out = std::fopen(cut.c_str(), "wb");
    Check(out != nullptr, "scratch file for the cut-off test");
    if (out) {
      unsigned char buf[64];
      const size_t got = std::fread(buf, 1, sizeof(buf), in);
      std::fwrite(buf, 1, got, out);
      std::fclose(out);
      std::FILE* again = std::fopen(cut.c_str(), "rb");
      if (again) {
        Check(whispaste::ReadMp4Gapless(again).rate == 0,
              "cut-off m4a: nothing trimmed");
        std::fclose(again);
      }
      std::remove(cut.c_str());
    }
    std::fclose(in);
  }
  Check(whispaste::ReadMp4Gapless(nullptr).rate == 0, "null file: nothing trimmed");
}

}  // namespace

int main(int argc, char** argv) {
  if (argc != 2) {
    std::fprintf(stderr, "usage: mp4_gapless_test <fixture_dir>\n");
    return 2;
  }
  TestEdtsV0();
  TestEdtsV1();
  TestItunSmpbFallback();
  TestNoAudioTrack();
  TestCountTooLarge();
  TestNonHexItunSmpb();
  TestWideItunSmpbFieldIgnored();
  TestPrimingBeyondTotal();
  TestOversizedBox();
  TestTruncations();
  TestFile(argv[1]);
  if (failures == 0) std::printf("mp4_gapless_test: OK\n");
  return failures == 0 ? 0 : 1;
}
