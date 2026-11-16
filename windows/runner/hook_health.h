// Compare independent RawInput evidence with low-level hook callbacks.
// Message timestamps are wrapping 32-bit milliseconds, not wall-clock time.
#ifndef RUNNER_HOOK_HEALTH_H_
#define RUNNER_HOOK_HEALTH_H_
#include <cstdint>

class HookHealth {
 public:
  void Reset(uint32_t now) { last_seen_ = now; }
  void Seen(uint32_t at) { last_seen_ = at; }
  bool MissingAt(uint32_t raw_at) const {
    // Hook callbacks precede RawInput. Ignore old queued input and allow
    // scheduling/timestamp granularity slack; silence without input is healthy.
    return static_cast<int32_t>(raw_at - last_seen_) > 1000;
  }

 private:
  uint32_t last_seen_ = 0;
};
#endif  // RUNNER_HOOK_HEALTH_H_
