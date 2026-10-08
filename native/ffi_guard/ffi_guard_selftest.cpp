// ffi_guard_selftest.cpp — wpg_selftest_throw, see ffi_guard.h. Kept in its
// own translation unit so it is compiled like the third-party libraries the
// guard protects (default exception model, extern "C" entry point that
// throws from a nested C++ frame with a destructor to unwind).
#include "ffi_guard.h"

#include <stdexcept>
#include <string>

namespace {

struct NotAStdException {
  int code;
};

void throw_from_nested_frame(int kind) {
  std::string scratch = "unwound";  // non-trivial destructor on the path
  if (kind == 1) throw std::runtime_error("wpg selftest");
  if (kind == 2) throw NotAStdException{static_cast<int>(scratch.size())};
}

}  // namespace

extern "C" void wpg_selftest_throw(const void* kind, const void* /*unused*/) {
  throw_from_nested_frame(*static_cast<const int*>(kind));
}
