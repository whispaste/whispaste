#ifndef RUNNER_DIAGNOSE_LAUNCH_H_
#define RUNNER_DIAGNOSE_LAUNCH_H_

// Launch decision for `whispaste --diagnose` without a display. Pure and free
// of GTK/X11 so diagnose_launch_test.cc can run on any host.
//
// Dart's main() only runs once a GTK FlView is realized: the Flutter Linux
// embedder exports no way to start an engine without one, so GTK needs a
// display before `--diagnose` can reach Dart. Without DISPLAY and
// WAYLAND_DISPLAY the runner therefore starts a private Xvfb for the
// diagnose run (xvfb_launcher.h). Inside a Flatpak or Snap sandbox it does
// not try; it writes a failure report instead (NoDisplayReportJson).

#include <cstdio>
#include <cstring>
#include <string>

enum class DiagnoseLaunch {
  kNormal,     // not a diagnose run, or a display is there: start as usual
  kStartXvfb,  // diagnose without display: start a private Xvfb first
  kNoDisplay,  // diagnose without display in a sandbox: report and exit
};

// Exit code when `--diagnose` cannot get a display (0 = ok, 1 = a library
// failed, 64 = bad command line come from Dart).
constexpr int kDiagnoseNoDisplayExitCode = 2;

struct DiagnoseLaunchEnv {
  const char* display;          // $DISPLAY
  const char* wayland_display;  // $WAYLAND_DISPLAY
  bool sandboxed;               // IsSandboxedPackage()
};

inline bool IsSetAndNotEmpty(const char* value) {
  return value != nullptr && value[0] != '\0';
}

// Same test as PackageDiagnoseOptions.isRequested: the flag anywhere after
// argv[0].
inline bool HasDiagnoseFlag(int argc, char** argv) {
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--diagnose") == 0) return true;
  }
  return false;
}

inline DiagnoseLaunch ClassifyDiagnoseLaunch(int argc, char** argv,
                                             const DiagnoseLaunchEnv& env) {
  if (!HasDiagnoseFlag(argc, argv)) return DiagnoseLaunch::kNormal;
  if (IsSetAndNotEmpty(env.display) || IsSetAndNotEmpty(env.wayland_display)) {
    return DiagnoseLaunch::kNormal;
  }
  return env.sandboxed ? DiagnoseLaunch::kNoDisplay
                       : DiagnoseLaunch::kStartXvfb;
}

// [flatpak_id] = $FLATPAK_ID, [flatpak_info_exists] = /.flatpak-info exists,
// [snap] = $SNAP.
inline bool IsSandboxedPackage(const char* flatpak_id, bool flatpak_info_exists,
                               const char* snap) {
  return IsSetAndNotEmpty(flatpak_id) || flatpak_info_exists ||
         IsSetAndNotEmpty(snap);
}

// The value after `--out`, or nullptr.
inline const char* DiagnoseOutPath(int argc, char** argv) {
  for (int i = 1; i + 1 < argc; ++i) {
    if (std::strcmp(argv[i], "--out") == 0) return argv[i + 1];
  }
  return nullptr;
}

// Xvfb -displayfd writes the display number and a newline once it accepts
// connections. Returns false until a complete, valid line is there.
inline bool ParseDisplayfdOutput(const std::string& output,
                                 std::string* display) {
  const size_t newline = output.find('\n');
  if (newline == std::string::npos || newline == 0) return false;
  for (size_t i = 0; i < newline; ++i) {
    if (output[i] < '0' || output[i] > '9') return false;
  }
  *display = ":" + output.substr(0, newline);
  return true;
}

inline std::string JsonEscape(const std::string& text) {
  std::string out;
  for (const char c : text) {
    switch (c) {
      case '"':
        out += "\\\"";
        break;
      case '\\':
        out += "\\\\";
        break;
      case '\n':
        out += "\\n";
        break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          char buf[8];
          std::snprintf(buf, sizeof(buf), "\\u%04x", c);
          out += buf;
        } else {
          out += c;
        }
    }
  }
  return out;
}

// Same top-level shape as Dart's PackageDiagnoseReport, with no library
// checked.
inline std::string NoDisplayReportJson(const std::string& error,
                                       const std::string& version) {
  return "{\n  \"ok\": false,\n  \"version\": \"" + JsonEscape(version) +
         "\",\n  \"error\": \"" + JsonEscape(error) +
         "\",\n  \"libraries\": []\n}\n";
}

#endif  // RUNNER_DIAGNOSE_LAUNCH_H_
