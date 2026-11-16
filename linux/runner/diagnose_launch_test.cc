// Unit test for diagnose_launch.h. Plain C++17, no GTK/X11, so it builds on
// any host: test/scripts/diagnose_launch_test.sh compiles and runs it (also
// in the Linux CI job).
#include "diagnose_launch.h"

#include <cstdio>
#include <string>
#include <vector>

namespace {

int failures = 0;

void Expect(bool ok, const char* what) {
  if (!ok) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    ++failures;
  }
}

// argv as main() gets it; argv[0] is the binary.
struct Args {
  std::vector<std::string> storage;
  std::vector<char*> argv;
  explicit Args(std::vector<std::string> a) : storage(std::move(a)) {
    for (auto& s : storage) argv.push_back(&s[0]);
    argv.push_back(nullptr);
  }
  int argc() const { return static_cast<int>(storage.size()); }
  char** data() { return argv.data(); }
};

DiagnoseLaunch Classify(std::vector<std::string> a, const char* display,
                        const char* wayland, bool sandboxed) {
  Args args(std::move(a));
  return ClassifyDiagnoseLaunch(args.argc(), args.data(),
                                DiagnoseLaunchEnv{display, wayland, sandboxed});
}

}  // namespace

int main() {
  // Normal starts are never touched, with or without a display.
  Expect(Classify({"whispaste"}, nullptr, nullptr, false) ==
             DiagnoseLaunch::kNormal,
         "plain start without display stays normal");
  Expect(Classify({"whispaste", "--autostart"}, ":0", nullptr, false) ==
             DiagnoseLaunch::kNormal,
         "autostart stays normal");
  // argv[0] is not an argument.
  Expect(Classify({"--diagnose"}, nullptr, nullptr, false) ==
             DiagnoseLaunch::kNormal,
         "argv[0] is ignored");

  // --diagnose with a display: run as before.
  Expect(Classify({"whispaste", "--diagnose"}, ":0", nullptr, false) ==
             DiagnoseLaunch::kNormal,
         "diagnose with DISPLAY runs normally");
  Expect(Classify({"whispaste", "--diagnose"}, nullptr, "wayland-0", false) ==
             DiagnoseLaunch::kNormal,
         "diagnose with WAYLAND_DISPLAY runs normally");

  // --diagnose without a display.
  Expect(Classify({"whispaste", "--diagnose"}, nullptr, nullptr, false) ==
             DiagnoseLaunch::kStartXvfb,
         "diagnose without display starts Xvfb");
  Expect(Classify({"whispaste", "--out", "r.json", "--diagnose"}, "", "",
                  false) == DiagnoseLaunch::kStartXvfb,
         "empty display variables count as missing");
  Expect(Classify({"whispaste", "--diagnose"}, nullptr, nullptr, true) ==
             DiagnoseLaunch::kNoDisplay,
         "sandboxed diagnose never tries Xvfb");

  // Sandbox detection.
  Expect(IsSandboxedPackage("de.whispaste.app", false, nullptr),
         "FLATPAK_ID means sandboxed");
  Expect(IsSandboxedPackage(nullptr, true, nullptr),
         "/.flatpak-info means sandboxed");
  Expect(IsSandboxedPackage(nullptr, false, "/snap/whispaste/12"),
         "SNAP means sandboxed");
  Expect(!IsSandboxedPackage(nullptr, false, nullptr), "plain host");
  Expect(!IsSandboxedPackage("", false, ""), "empty variables are no sandbox");

  // --out path, as the Dart parser reads it.
  {
    Args a({"whispaste", "--diagnose", "--out", "/tmp/r.json"});
    Expect(DiagnoseOutPath(a.argc(), a.data()) == std::string("/tmp/r.json"),
           "--out value is found");
    Args b({"whispaste", "--diagnose", "--out"});
    Expect(DiagnoseOutPath(b.argc(), b.data()) == nullptr,
           "--out without value gives no path");
    Args c({"whispaste", "--diagnose"});
    Expect(DiagnoseOutPath(c.argc(), c.data()) == nullptr, "no --out");
  }

  // Xvfb -displayfd output.
  {
    std::string display;
    Expect(ParseDisplayfdOutput("99\n", &display) && display == ":99",
           "displayfd number becomes :N");
    Expect(ParseDisplayfdOutput("0\n", &display) && display == ":0",
           "display 0 is valid");
    Expect(!ParseDisplayfdOutput("", &display), "no output is a failure");
    Expect(!ParseDisplayfdOutput("12", &display),
           "a number without newline is not complete yet");
    Expect(!ParseDisplayfdOutput("x1\n", &display), "garbage is a failure");
  }

  // Report written instead of Dart's when no display can be had.
  {
    const std::string json =
        NoDisplayReportJson("Xvfb \"not\" found\\here", "1.2.3");
    Expect(json.find("\"ok\": false") != std::string::npos, "report: ok false");
    Expect(json.find("\"version\": \"1.2.3\"") != std::string::npos,
           "report: version");
    Expect(json.find("Xvfb \\\"not\\\" found\\\\here") != std::string::npos,
           "report: error is JSON-escaped");
    Expect(json.find("\"libraries\": []") != std::string::npos,
           "report: empty libraries list");
  }

  if (failures != 0) {
    std::fprintf(stderr, "%d failure(s)\n", failures);
    return 1;
  }
  std::printf("diagnose_launch_test: all passed\n");
  return 0;
}
