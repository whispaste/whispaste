#include "secondary_plugin_registrant.h"

// Plugins a secondary engine needs: none today. The secondary render
// entrypoints (lib/*_render_entrypoint.dart) reach no plugin with a Linux
// native side (sentry_flutter's Linux plugin is an empty stub), and they talk
// to the main engine only through their own render MethodChannels.
//
// Add a plugin here only if its native state is per engine, and never one of
// the process-global plugins named in the header.
void fl_register_secondary_plugins(FlPluginRegistry* registry) {
  (void)registry;
}
