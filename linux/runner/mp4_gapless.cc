#include "mp4_gapless.h"

#include <string>
#include <vector>

namespace whispaste {
namespace {

constexpr size_t kMaxMoovBytes = size_t{16} << 20;
constexpr uint64_t kMaxSamples = uint64_t{1} << 40;
constexpr size_t kMaxEntries = 4096;

constexpr uint32_t Fourcc(const char (&s)[5]) {
  return (uint32_t{static_cast<uint8_t>(s[0])} << 24) |
         (uint32_t{static_cast<uint8_t>(s[1])} << 16) |
         (uint32_t{static_cast<uint8_t>(s[2])} << 8) |
         uint32_t{static_cast<uint8_t>(s[3])};
}
constexpr uint32_t kMoov = Fourcc("moov");
constexpr uint32_t kMvhd = Fourcc("mvhd");
constexpr uint32_t kTrak = Fourcc("trak");
constexpr uint32_t kMdia = Fourcc("mdia");
constexpr uint32_t kMdhd = Fourcc("mdhd");
constexpr uint32_t kHdlr = Fourcc("hdlr");
constexpr uint32_t kEdts = Fourcc("edts");
constexpr uint32_t kElst = Fourcc("elst");
constexpr uint32_t kUdta = Fourcc("udta");
constexpr uint32_t kMeta = Fourcc("meta");
constexpr uint32_t kIlst = Fourcc("ilst");
constexpr uint32_t kFreeform = Fourcc("----");
constexpr uint32_t kName = Fourcc("name");
constexpr uint32_t kData = Fourcc("data");
constexpr uint32_t kSoun = Fourcc("soun");

uint32_t U32(const uint8_t* p) {
  return (uint32_t{p[0]} << 24) | (uint32_t{p[1]} << 16) |
         (uint32_t{p[2]} << 8) | uint32_t{p[3]};
}
uint64_t U64(const uint8_t* p) {
  return (uint64_t{U32(p)} << 32) | U32(p + 4);
}

struct Box {
  uint32_t type = 0;
  const uint8_t* body = nullptr;
  size_t size = 0;  // body bytes
};

// Reads the box at |pos| inside [data, data + n) and sets |end| to its end.
// False when the header or the declared size does not fit the container.
bool ReadBox(const uint8_t* data, size_t n, size_t pos, Box* box, size_t* end) {
  if (pos > n || n - pos < 8) return false;
  uint64_t size = U32(data + pos);
  const uint32_t type = U32(data + pos + 4);
  size_t header = 8;
  if (size == 1) {
    if (n - pos < 16) return false;
    size = U64(data + pos + 8);
    header = 16;
  } else if (size == 0) {
    size = n - pos;  // runs to the end of the container
  }
  if (size < header || size > n - pos) return false;
  box->type = type;
  box->body = data + pos + header;
  box->size = static_cast<size_t>(size) - header;
  *end = pos + static_cast<size_t>(size);
  return true;
}

// First child of type |want|. False when absent or when damage stops the walk.
bool FindBox(const uint8_t* data, size_t n, uint32_t want, Box* out) {
  size_t pos = 0;
  while (pos < n) {
    Box box;
    size_t end = 0;
    if (!ReadBox(data, n, pos, &box, &end)) return false;
    if (box.type == want) {
      *out = box;
      return true;
    }
    pos = end;
  }
  return false;
}

// Timescale of mvhd or mdhd: the timescale follows the creation and
// modification times, 4 bytes each in version 0 and 8 bytes each in version 1.
bool ReadTimescale(const Box& box, uint32_t* timescale) {
  if (box.size < 4) return false;
  const uint8_t version = box.body[0];
  const size_t offset = version == 1 ? 4 + 16 : 4 + 8;
  if (box.size < offset + 4) return false;
  *timescale = U32(box.body + offset);
  return *timescale != 0;
}

bool IsHexToken(const std::string& token) {
  return !token.empty() && token.size() <= 16 &&
         token.find_first_not_of("0123456789abcdefABCDEF") == std::string::npos;
}

// |token| must already pass IsHexToken, so the value fits in 64 bits.
uint64_t HexValue(const std::string& token) {
  uint64_t value = 0;
  for (char c : token) {
    const int digit = (c >= '0' && c <= '9')   ? c - '0'
                      : (c >= 'a' && c <= 'f') ? c - 'a' + 10
                                               : c - 'A' + 10;
    value = (value << 4) | static_cast<uint64_t>(digit);
  }
  return value;
}

// iTunSMPB text: " 00000000 <priming> <padding> <total samples> ...", all hex.
bool ParseItunSmpb(const std::string& text, uint64_t* priming, uint64_t* total) {
  std::vector<std::string> tokens;
  std::string current;
  for (char c : text) {
    if (c == ' ' || c == '\0' || c == '\t' || c == '\n') {
      if (!current.empty()) tokens.push_back(current);
      current.clear();
    } else {
      current.push_back(c);
    }
  }
  if (!current.empty()) tokens.push_back(current);
  if (tokens.size() < 4 || !IsHexToken(tokens[1]) || !IsHexToken(tokens[3])) {
    return false;
  }
  // Priming is a 32-bit field; the total is 64-bit in the format, but it is
  // capped at 2^44 samples so that frames * 16 kHz cannot overflow.
  // Leading zeros do not count, so the check is on the value.
  const uint64_t priming_value = HexValue(tokens[1]);
  const uint64_t total_value = HexValue(tokens[3]);
  if (priming_value > 0xFFFFFFFFu || total_value >= (uint64_t{1} << 44)) {
    return false;
  }
  *priming = priming_value;
  *total = total_value;
  return true;
}

// iTunSMPB from moov/udta/meta/ilst/----[name == "iTunSMPB"]/data.
bool FindItunSmpb(const uint8_t* moov, size_t size, uint64_t* priming,
                  uint64_t* total) {
  Box udta;
  if (!FindBox(moov, size, kUdta, &udta)) return false;
  Box meta;
  if (!FindBox(udta.body, udta.size, kMeta, &meta)) return false;
  if (meta.size < 4) return false;  // full box: version and flags first
  Box ilst;
  if (!FindBox(meta.body + 4, meta.size - 4, kIlst, &ilst)) return false;

  size_t pos = 0;
  while (pos < ilst.size) {
    Box item;
    size_t end = 0;
    if (!ReadBox(ilst.body, ilst.size, pos, &item, &end)) break;
    pos = end;
    if (item.type != kFreeform) continue;
    Box name;
    Box data;
    if (!FindBox(item.body, item.size, kName, &name) || name.size < 4) continue;
    const std::string key(reinterpret_cast<const char*>(name.body + 4),
                          name.size - 4);
    if (key != "iTunSMPB") continue;
    if (!FindBox(item.body, item.size, kData, &data) || data.size < 8) continue;
    const std::string text(reinterpret_cast<const char*>(data.body + 8),
                           data.size - 8);
    return ParseItunSmpb(text, priming, total);
  }
  return false;
}

struct Edit {
  uint64_t duration = 0;  // movie timescale
  int64_t media_time = 0;  // track timescale, -1 = empty edit
};

// Edit list of the track: first entry gives priming, all non-empty entries
// give the length. False when no usable entry exists.
bool ReadEdits(const Box& edts, uint64_t* priming, uint64_t* media_duration,
               bool* has_priming) {
  Box elst;
  if (!FindBox(edts.body, edts.size, kElst, &elst)) return false;
  if (elst.size < 8) return false;
  const uint8_t version = elst.body[0];
  const size_t entry_size = version == 1 ? 20 : 12;
  const uint32_t count = U32(elst.body + 4);
  if (count == 0 || count > kMaxEntries) return false;
  if (elst.size - 8 < uint64_t{count} * entry_size) return false;

  std::vector<Edit> edits(count);
  const uint8_t* p = elst.body + 8;
  for (Edit& e : edits) {
    if (version == 1) {
      e.duration = U64(p);
      e.media_time = static_cast<int64_t>(U64(p + 8));
    } else {
      e.duration = U32(p);
      e.media_time = static_cast<int32_t>(U32(p + 4));
    }
    p += entry_size;
  }

  *has_priming = edits[0].media_time >= 0;
  *priming = *has_priming ? static_cast<uint64_t>(edits[0].media_time) : 0;
  *media_duration = 0;
  for (const Edit& e : edits) {
    if (e.media_time < 0) continue;  // empty edit: nothing decoded for it
    if (e.duration > kMaxSamples) return false;
    *media_duration += e.duration;
    if (*media_duration > kMaxSamples) return false;
  }
  return true;
}

}  // namespace

Mp4Gapless ParseMp4GaplessMoov(const uint8_t* moov, size_t size) {
  Mp4Gapless none;
  if (!moov || size == 0) return none;

  uint32_t movie_timescale = 0;
  Box mvhd;
  if (FindBox(moov, size, kMvhd, &mvhd)) {
    ReadTimescale(mvhd, &movie_timescale);
  }

  // The first audio track carries the gapless info.
  Mp4Gapless result;
  bool found_track = false;
  size_t pos = 0;
  while (pos < size && !found_track) {
    Box trak;
    size_t end = 0;
    if (!ReadBox(moov, size, pos, &trak, &end)) break;
    pos = end;
    if (trak.type != kTrak) continue;

    Box mdia;
    if (!FindBox(trak.body, trak.size, kMdia, &mdia)) continue;
    Box hdlr;
    if (!FindBox(mdia.body, mdia.size, kHdlr, &hdlr) || hdlr.size < 12 ||
        U32(hdlr.body + 8) != kSoun) {
      continue;
    }
    found_track = true;
    Box mdhd;
    uint32_t track_timescale = 0;
    if (!FindBox(mdia.body, mdia.size, kMdhd, &mdhd) ||
        !ReadTimescale(mdhd, &track_timescale)) {
      return none;
    }
    result.rate = track_timescale;

    Box edts;
    uint64_t priming = 0;
    uint64_t media_duration = 0;
    bool has_priming = false;
    if (FindBox(trak.body, trak.size, kEdts, &edts) &&
        ReadEdits(edts, &priming, &media_duration, &has_priming)) {
      result.priming = priming;
      if (movie_timescale != 0 && media_duration != 0) {
        const double total = static_cast<double>(media_duration) *
                             track_timescale / movie_timescale;
        if (total <= static_cast<double>(kMaxSamples)) {
          result.total = static_cast<uint64_t>(total + 0.5);
        }
      }
    }
  }
  if (!found_track) return none;

  // No usable edit list: use the iTunSMPB tag, if there is one.
  if (result.priming == 0 && result.total == 0) {
    uint64_t priming = 0;
    uint64_t total = 0;
    if (FindItunSmpb(moov, size, &priming, &total)) {
      result.priming = priming;
      result.total = total;
    }
  }

  if (result.priming > kMaxSamples || result.total > kMaxSamples ||
      (result.total != 0 && result.priming > result.total)) {
    return none;  // implausible values: trim nothing
  }
  return result;
}

Mp4Gapless ReadMp4Gapless(std::FILE* file) {
  Mp4Gapless none;
  if (!file) return none;
  if (std::fseek(file, 0, SEEK_END) != 0) return none;
  const long end = std::ftell(file);
  if (end <= 0) return none;

  long pos = 0;
  while (pos + 8 <= end) {
    uint8_t head[16] = {0};
    if (std::fseek(file, pos, SEEK_SET) != 0) break;
    const size_t got = std::fread(head, 1, sizeof(head), file);
    if (got < 8) break;
    uint64_t size = U32(head);
    const uint32_t type = U32(head + 4);
    size_t header = 8;
    if (size == 1) {
      if (got < 16) break;
      size = U64(head + 8);
      header = 16;
    } else if (size == 0) {
      size = static_cast<uint64_t>(end - pos);
    }
    if (size < header || size > static_cast<uint64_t>(end - pos)) break;

    if (type == kMoov) {
      const size_t body = static_cast<size_t>(size) - header;
      if (body > kMaxMoovBytes) return none;
      std::vector<uint8_t> buffer(body);
      if (std::fseek(file, pos + static_cast<long>(header), SEEK_SET) != 0) {
        return none;
      }
      if (body > 0 && std::fread(buffer.data(), 1, body, file) != body) {
        return none;
      }
      return ParseMp4GaplessMoov(buffer.data(), body);
    }
    pos += static_cast<long>(size);
  }
  return none;
}

}  // namespace whispaste
