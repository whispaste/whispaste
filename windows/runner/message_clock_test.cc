// Test of the growing message-time stamps (message_clock.h).
#include "message_clock.h"

#include <cstdio>

namespace {
int failures = 0;
void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}
}  // namespace

int main() {
  UnwrappedMessageTime t;
  Expect(t.Unwrap(1000) == 1000, "the first stamp is taken as is");
  Expect(t.Unwrap(1250) == 1250, "a later stamp grows");
  Expect(t.Unwrap(1240) == 1240, "a late event steps back, not a wrap");

  UnwrappedMessageTime w;
  w.Unwrap(0xFFFFFF00u);
  const int64_t before = w.Unwrap(0xFFFFFFF0u);
  const int64_t after = w.Unwrap(0x00000010u);
  Expect(after > before, "the stamp keeps growing across the 32-bit wrap");
  Expect(after - before == 0x20, "the step over the wrap is the real gap");

  return failures == 0 ? 0 : 1;
}
