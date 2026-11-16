#ifndef RUNNER_AUTOREPEAT_FILTER_H_
#define RUNNER_AUTOREPEAT_FILTER_H_

#include <cstdint>
#include <optional>

// X11 autorepeat filter for push-to-talk key-up (XInput2 raw events). Pure
// and free of X11/GLib so autorepeat_filter_test.cc can run on any host.
//
// In non-detectable autorepeat mode a held key emits release/press pairs
// back to back. A release of the watched key therefore only arms a short
// confirmation timer; a press of the same key before it fires was
// autorepeat and disarms it. Only a release that stays unanswered is the
// user letting go.

enum class RawKeyAction {
  kIgnore,
  kScheduleRelease,
  kCancelPendingRelease,
};

// [watched_keycode] 0 means no push-to-talk key is held.
inline RawKeyAction ClassifyRawKeyEvent(unsigned watched_keycode,
                                        unsigned keycode, bool is_release) {
  if (watched_keycode == 0 || keycode != watched_keycode) {
    return RawKeyAction::kIgnore;
  }
  return is_release ? RawKeyAction::kScheduleRelease
                    : RawKeyAction::kCancelPendingRelease;
}

// Longest press that is still reported with its length; a longer gap is not
// a tap and is passed on as unknown.
constexpr std::uint64_t kMaxPressMs = 60000;

// Press length in ms from two X server times (ms, 32-bit, wraps). Unsigned
// subtraction stays right across a wrap. Empty when the press start was not
// seen or the length is implausible.
inline std::optional<long> PressDurationMs(bool down_known,
                                           unsigned int down_ms,
                                           unsigned int up_ms) {
  if (!down_known) return std::nullopt;
  const auto elapsed = static_cast<std::uint64_t>(up_ms - down_ms);
  if (elapsed > kMaxPressMs) return std::nullopt;
  return static_cast<long>(elapsed);
}

// X server time (ms, 32-bit, wraps about every 49 days) as a growing 64-bit
// value, so the Dart side can subtract two stamps without knowing the wrap.
// Every step is a difference to the previous stamp, so a late-fed event is
// fine as long as it is less than half the range away; a step back of that
// size is a late event, not a wrap.
class UnwrappedServerTime {
 public:
  std::uint64_t Unwrap(std::uint32_t server_ms) {
    if (started_) {
      const auto step = static_cast<std::int32_t>(server_ms - last_);
      const auto next = static_cast<std::int64_t>(value_) + step;
      value_ = next < 0 ? 0 : static_cast<std::uint64_t>(next);
    } else {
      value_ = server_ms;
      started_ = true;
    }
    last_ = server_ms;
    return value_;
  }

 private:
  bool started_ = false;
  std::uint32_t last_ = 0;
  std::uint64_t value_ = 0;
};

// Portal timestamps of Activated and Deactivated. ASSUMED to be microseconds
// (GlobalShortcuts spec); verify on linux-vm before relying on it.
constexpr std::uint64_t kPortalTimeUnitsPerMs = 1000;

inline std::optional<long> PortalPressDurationMs(bool down_known,
                                                 std::uint64_t down_units,
                                                 std::uint64_t up_units) {
  if (!down_known || up_units < down_units) return std::nullopt;
  const std::uint64_t elapsed_ms =
      (up_units - down_units) / kPortalTimeUnitsPerMs;
  if (elapsed_ms > kMaxPressMs) return std::nullopt;
  return static_cast<long>(elapsed_ms);
}

#endif  // RUNNER_AUTOREPEAT_FILTER_H_
