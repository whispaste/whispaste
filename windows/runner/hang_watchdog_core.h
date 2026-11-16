// Decision logic of the hang watchdog (#338), shared contract of all three
// runners. Keep windows/runner/hang_watchdog_core.h byte-identical to this
// file; HangWatchdogCore in macos/Runner/HangWatchdogHost.swift mirrors the
// same rules (checked by test/scripts/hang_watchdog_core_test.sh on macOS).
//
// Pure logic on millisecond timestamps, no threads, no clocks, so it can be
// tested with simulated time:
// * Not armed (app still starting) -> never a hang.
// * A tick much later than planned (> kWakeGapMs) means the machine slept:
//   grant kWakeGraceMs, then count the threshold from its end.
// * No beat for thresholdMs -> exactly one hang per armed session.
// * A restart only when the last automatic restart is at least
//   kRestartCooldownMs ago (wall clock, persisted by the runner).

#ifndef RUNNER_HANG_WATCHDOG_CORE_H_
#define RUNNER_HANG_WATCHDOG_CORE_H_

#include <cstdint>

namespace hang_watchdog {

constexpr int64_t kDefaultThresholdMs = 20000;
constexpr int64_t kTickMs = 1000;
constexpr int64_t kWakeGapMs = 5000;
constexpr int64_t kWakeGraceMs = 30000;
constexpr int64_t kRestartCooldownMs = 10 * 60 * 1000;

enum class Verdict { kNone, kHang };

class Core {
 public:
  void Arm(int64_t now_ms, int64_t threshold_ms) {
    armed_ = true;
    fired_ = false;
    threshold_ms_ = threshold_ms > 0 ? threshold_ms : kDefaultThresholdMs;
    last_beat_ms_ = now_ms;
    last_tick_ms_ = now_ms;
    grace_until_ms_ = 0;
  }

  void Disarm() { armed_ = false; }

  void Beat(int64_t now_ms) { last_beat_ms_ = now_ms; }

  // Called by the watchdog thread about every kTickMs.
  Verdict Tick(int64_t now_ms) {
    if (!armed_ || fired_) {
      last_tick_ms_ = now_ms;
      return Verdict::kNone;
    }
    if (now_ms - last_tick_ms_ > kWakeGapMs) {
      // The threshold starts counting only after the grace.
      grace_until_ms_ = now_ms + kWakeGraceMs;
      last_beat_ms_ = grace_until_ms_;
    }
    last_tick_ms_ = now_ms;
    if (now_ms < grace_until_ms_) return Verdict::kNone;
    if (now_ms - last_beat_ms_ < threshold_ms_) return Verdict::kNone;
    fired_ = true;
    return Verdict::kHang;
  }

  int64_t StalledMs(int64_t now_ms) const { return now_ms - last_beat_ms_; }

  static bool MayRestart(int64_t now_wall_ms, int64_t last_restart_wall_ms) {
    if (last_restart_wall_ms <= 0) return true;
    const int64_t since = now_wall_ms - last_restart_wall_ms;
    return since < 0 || since >= kRestartCooldownMs;
  }

 private:
  bool armed_ = false;
  bool fired_ = false;
  int64_t threshold_ms_ = kDefaultThresholdMs;
  int64_t last_beat_ms_ = 0;
  int64_t last_tick_ms_ = 0;
  int64_t grace_until_ms_ = 0;
};

}  // namespace hang_watchdog

#endif  // RUNNER_HANG_WATCHDOG_CORE_H_
