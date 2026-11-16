#ifndef RUNNER_SECONDARY_PLUGIN_REGISTRANT_H_
#define RUNNER_SECONDARY_PLUGIN_REGISTRANT_H_

#include <flutter_linux/flutter_linux.h>

// Registers the native plugins that a secondary Flutter engine (floating
// button, floating overlay, side panel, snippet picker) needs. It deliberately
// never registers the process-global plugins tray_manager, local_notifier or
// hotkey_manager_linux: each of them keeps a single native instance that every
// registration overwrites, so a secondary engine would take over the tray
// (issue #154). Only the main engine registers the full generated registrant.
void fl_register_secondary_plugins(FlPluginRegistry* registry);

#endif  // RUNNER_SECONDARY_PLUGIN_REGISTRANT_H_
