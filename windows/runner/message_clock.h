// Growing millisecond stamps from Windows message times (GetMessageTime).
// Platform-neutral C++17 so it can be tested off Windows
// (test/scripts/message_clock_test.sh).
#ifndef RUNNER_MESSAGE_CLOCK_H_
#define RUNNER_MESSAGE_CLOCK_H_

#include <cstdint>

// GetMessageTime wraps every ~49 days. Dart compares the stamps of key events
// as differences, so they must not jump at the wrap: every step is the 32-bit
// difference to the previous stamp (like UnwrappedServerTime on Linux). A step
// back of less than half the range is a late event, not a wrap.
class UnwrappedMessageTime {
 public:
  int64_t Unwrap(uint32_t message_ms) {
    if (started_) {
      const auto step = static_cast<int32_t>(message_ms - last_);
      value_ += step;
      if (value_ < 0) value_ = 0;
    } else {
      value_ = message_ms;
      started_ = true;
    }
    last_ = message_ms;
    return value_;
  }

 private:
  bool started_ = false;
  uint32_t last_ = 0;
  int64_t value_ = 0;
};

#endif  // RUNNER_MESSAGE_CLOCK_H_
