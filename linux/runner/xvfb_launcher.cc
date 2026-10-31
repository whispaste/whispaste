#include "xvfb_launcher.h"

#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include <cerrno>
#include <cstdio>
#include <string>

#include "diagnose_launch.h"

namespace {

constexpr int kExecFailed = 127;

long long NowMs() {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return static_cast<long long>(ts.tv_sec) * 1000 + ts.tv_nsec / 1000000;
}

// Waits up to [timeout_ms] for [pid]; true once it is reaped.
bool WaitForExit(pid_t pid, int timeout_ms, int* status) {
  const long long deadline = NowMs() + timeout_ms;
  while (true) {
    const pid_t r = waitpid(pid, status, WNOHANG);
    if (r == pid || (r < 0 && errno != EINTR)) return true;
    if (NowMs() >= deadline) return false;
    usleep(10 * 1000);
  }
}

void KillAndReap(pid_t pid) {
  int status = 0;
  kill(pid, SIGTERM);
  if (!WaitForExit(pid, 2000, &status)) {
    kill(pid, SIGKILL);
    waitpid(pid, &status, 0);
  }
}

}  // namespace

bool StartPrivateXvfb(int timeout_ms, PrivateXvfb* xvfb, std::string* error) {
  int fds[2];
  if (pipe2(fds, O_CLOEXEC) != 0) {
    *error = "could not create a pipe for Xvfb";
    return false;
  }
  const pid_t parent = getpid();
  const pid_t pid = fork();
  if (pid < 0) {
    close(fds[0]);
    close(fds[1]);
    *error = "could not fork for Xvfb";
    return false;
  }
  if (pid == 0) {
    // Child: die with the app, keep stdout (the JSON report) clean.
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() != parent) _exit(1);
    const int devnull = open("/dev/null", O_RDWR);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
    }
    // dup() drops O_CLOEXEC, so only this end survives exec.
    const int display_fd = dup(fds[1]);
    char fd_arg[16];
    std::snprintf(fd_arg, sizeof(fd_arg), "%d", display_fd);
    execlp("Xvfb", "Xvfb", "-displayfd", fd_arg, "-nolisten", "tcp",
           "-screen", "0", "1280x800x24", static_cast<char*>(nullptr));
    _exit(kExecFailed);
  }

  close(fds[1]);
  std::string output;
  std::string display;
  const long long deadline = NowMs() + timeout_ms;
  bool eof = false;
  while (!ParseDisplayfdOutput(output, &display)) {
    const long long left = deadline - NowMs();
    if (left <= 0) break;
    struct pollfd p = {fds[0], POLLIN, 0};
    const int ready = poll(&p, 1, static_cast<int>(left));
    if (ready < 0 && errno == EINTR) continue;
    if (ready <= 0) break;
    char buf[64];
    const ssize_t n = read(fds[0], buf, sizeof(buf));
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) {
      eof = true;
      break;
    }
    output.append(buf, static_cast<size_t>(n));
  }
  close(fds[0]);

  if (ParseDisplayfdOutput(output, &display)) {
    xvfb->pid = pid;
    xvfb->display = display;
    return true;
  }

  int status = 0;
  if (eof && WaitForExit(pid, 1000, &status)) {
    if (WIFEXITED(status) && WEXITSTATUS(status) == kExecFailed) {
      *error = "Xvfb not found in PATH";
    } else {
      *error = "Xvfb exited before it accepted connections";
    }
    return false;
  }
  KillAndReap(pid);
  *error = "Xvfb did not start within " + std::to_string(timeout_ms) + " ms";
  return false;
}

void StopPrivateXvfb(PrivateXvfb* xvfb) {
  if (xvfb->pid <= 0) return;
  KillAndReap(xvfb->pid);
  xvfb->pid = -1;
}
