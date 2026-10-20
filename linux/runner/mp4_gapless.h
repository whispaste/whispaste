// Gapless information (encoder priming and padding) of an MP4/M4A file
// (WP-35b). Media Foundation does not trim the encoder delay that the container
// describes, so the Windows M4A path trims it with this parser. Flutter-free:
// the native test compiles it too, and the Linux app does not link it.
//
// Sources, in order: the 'elst' edit list of the first audio track
// (media_time = priming, segment durations = length), then the iTunSMPB tag in
// moov/udta/meta/ilst. Damaged or truncated boxes are skipped, never read past.
#ifndef RUNNER_MP4_GAPLESS_H_
#define RUNNER_MP4_GAPLESS_H_

#include <cstddef>
#include <cstdint>
#include <cstdio>

namespace whispaste {

struct Mp4Gapless {
  uint32_t rate = 0;     // sample rate of the audio track; 0 = nothing known
  uint64_t priming = 0;  // leading samples to drop, in |rate| units
  uint64_t total = 0;    // samples to keep after trimming; 0 = not known
};

// Reads the top-level boxes of |file| up to 'moov' and extracts the gapless
// info. Files over 2 GiB or damaged containers give rate 0 (nothing trimmed).
Mp4Gapless ReadMp4Gapless(std::FILE* file);

// Same for an in-memory 'moov' payload (the box body, without its header).
Mp4Gapless ParseMp4GaplessMoov(const uint8_t* moov, size_t size);

}  // namespace whispaste

#endif  // RUNNER_MP4_GAPLESS_H_
