#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <string>

#include "diagnose_launch.h"
#include "my_application.h"
#include "xvfb_launcher.h"

namespace {

constexpr int kXvfbStartTimeoutMs = 10000;

PrivateXvfb diagnose_xvfb;

void StopDiagnoseXvfb() { StopPrivateXvfb(&diagnose_xvfb); }

// Prints the report and writes it to `--out`, like Dart's diagnose would.
int ReportNoDisplay(int argc, char** argv, const std::string& error,
                    const char* hint) {
  const std::string json = NoDisplayReportJson(error, WHISPASTE_VERSION);
  if (const char* out_path = DiagnoseOutPath(argc, argv)) {
    if (FILE* f = std::fopen(out_path, "w")) {
      std::fputs(json.c_str(), f);
      std::fclose(f);
    }
  }
  std::fputs(json.c_str(), stdout);
  std::fprintf(stderr, "whispaste: --diagnose needs a display: %s. %s\n",
               error.c_str(), hint);
  return kDiagnoseNoDisplayExitCode;
}

}  // namespace

int main(int argc, char** argv) {
  // `--diagnose` without a display: GTK cannot start, so Dart never runs.
  // Start a private Xvfb (or report why not) before anything else, while
  // this is still the only thread. Normal starts skip this entirely.
  const DiagnoseLaunchEnv launch_env{
      g_getenv("DISPLAY"), g_getenv("WAYLAND_DISPLAY"),
      IsSandboxedPackage(g_getenv("FLATPAK_ID"),
                         access("/.flatpak-info", F_OK) == 0,
                         g_getenv("SNAP"))};
  switch (ClassifyDiagnoseLaunch(argc, argv, launch_env)) {
    case DiagnoseLaunch::kNormal:
      break;
    case DiagnoseLaunch::kNoDisplay:
      return ReportNoDisplay(argc, argv, "no display in the sandbox",
                             "Run it with a display, e.g. under xvfb-run.");
    case DiagnoseLaunch::kStartXvfb: {
      std::string error;
      if (!StartPrivateXvfb(kXvfbStartTimeoutMs, &diagnose_xvfb, &error)) {
        return ReportNoDisplay(
            argc, argv, error,
            "Install Xvfb (package xvfb) or run it under xvfb-run.");
      }
      std::atexit(StopDiagnoseXvfb);
      g_setenv("DISPLAY", diagnose_xvfb.display.c_str(), TRUE);
      g_unsetenv("WAYLAND_DISPLAY");
      g_setenv("GDK_BACKEND", "x11", TRUE);
      break;
    }
  }

  // Force the X11/XWayland GDK backend before GTK initialises.
  //
  // Why: the floating overlay needs two capabilities that native Wayland
  // (via libwayland-client) does NOT provide under GNOME/Mutter:
  //   1. gtk_window_set_keep_above — Mutter ignores this on Wayland; the
  //      compositor controls all stacking and forbids app-driven always-on-top.
  //   2. gtk_window_move — absolute positioning is not available in the
  //      Wayland shell protocol; only the compositor decides where windows go.
  //
  // Under XWayland (Mutter's built-in X11 compatibility layer), both features
  // are available via the EWMH _NET_WM_STATE_ABOVE hint and XMoveWindow,
  // respectively. The main application window also uses XWayland, so there is
  // no visual regression — font rendering and HiDPI scaling behave identically.
  //
  // We only set the variable if the caller has not already overridden it, so
  // that test harnesses or CI environments that explicitly need Wayland can
  // still pass GDK_BACKEND=wayland on the command line or in the environment.
  //
  // COMPILE RISK: on a pure X11 system (no Wayland compositor at all) this
  // env var is a no-op — GDK already picks the X11 backend.
  if (g_getenv("GDK_BACKEND") == nullptr) {
    g_setenv("GDK_BACKEND", "x11", TRUE);
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
