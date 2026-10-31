#ifndef RUNNER_SECONDARY_ENGINE_H_
#define RUNNER_SECONDARY_ENGINE_H_

#include <flutter_linux/flutter_linux.h>

// Project for a secondary Flutter engine (floating button, floating overlay,
// side panel, snippet picker); |entrypoint_arg| selects its Dart entrypoint.
//
// Secondary engines render with Skia, not Impeller. With Flutter 3.47.9 under
// Xwayland (llvmpipe, lab VM ubu) an Impeller secondary view shows its window
// and reports its first frame, yet not one pixel reaches the screen; Skia and
// Flutter 3.44.1 draw it (internal-notes). The trigger is a
// gradient shader: a frame that paints one stays blank, plain fills, text,
// blur and opacity draw. A minimal app with the same gradient in two windows
// draws fine, so no upstream issue is filed. The main window keeps the engine
// default.
// Check on every Flutter update: in a throwaway commit pass TRUE to
// fl_dart_project_set_enable_impeller in secondary_engine.cc, run the render
// proof on ubu (the ticket names the harness ref) and lift the override once
// the floating button, the overlay and the side panel draw.
FlDartProject* secondary_project_new(const gchar* entrypoint_arg);

// Logs a warning naming |name| when |view| is shown but its engine has not
// drawn a first frame within a few seconds, e.g. because its OpenGL context
// failed, so an empty window never stays unexplained.
void secondary_view_watch_first_frame(FlView* view, const gchar* name);

#endif  // RUNNER_SECONDARY_ENGINE_H_
