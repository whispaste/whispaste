#ifndef RUNNER_XVFB_LAUNCHER_H_
#define RUNNER_XVFB_LAUNCHER_H_

#include <sys/types.h>

#include <string>

// A private Xvfb for `whispaste --diagnose` without a display (see
// diagnose_launch.h). Xvfb picks a free display itself (-displayfd) and dies
// with this process (PR_SET_PDEATHSIG), so a crash or signal never leaves
// it running.
struct PrivateXvfb {
  pid_t pid = -1;
  std::string display;  // ":N"
};

// Starts Xvfb from PATH and waits up to [timeout_ms] until it accepts
// connections. Must be called before any other thread exists: the death
// signal follows the forking thread. On failure fills [error] and leaves no
// child behind.
bool StartPrivateXvfb(int timeout_ms, PrivateXvfb* xvfb, std::string* error);

// Terminates and reaps the Xvfb started by StartPrivateXvfb. Safe to call
// twice.
void StopPrivateXvfb(PrivateXvfb* xvfb);

#endif  // RUNNER_XVFB_LAUNCHER_H_
