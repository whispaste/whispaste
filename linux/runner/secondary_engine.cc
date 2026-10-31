#include "secondary_engine.h"

namespace {

// Engine boot plus first frame takes about 1.5 s on the software-rendered lab
// VM; a working view never comes close to this.
constexpr guint kFirstFrameTimeoutSeconds = 8;

constexpr char kFirstFrameKey[] = "wp-first-frame";
constexpr char kNameKey[] = "wp-secondary-name";

void OnFirstFrame(FlView* view, gpointer) {
  g_object_set_data(G_OBJECT(view), kFirstFrameKey, GINT_TO_POINTER(1));
}

gboolean OnFirstFrameTimeout(gpointer data) {
  GWeakRef* ref = static_cast<GWeakRef*>(data);
  g_autoptr(GObject) view = static_cast<GObject*>(g_weak_ref_get(ref));
  if (view != nullptr && gtk_widget_get_mapped(GTK_WIDGET(view)) &&
      g_object_get_data(view, kFirstFrameKey) == nullptr) {
    g_warning(
        "%s window is shown but its Flutter engine drew no frame within %u s; "
        "the window stays empty (OpenGL context or renderer failed, see the "
        "warnings above)",
        static_cast<const gchar*>(g_object_get_data(view, kNameKey)),
        kFirstFrameTimeoutSeconds);
  }
  return G_SOURCE_REMOVE;
}

void FreeWeakRef(gpointer data) {
  GWeakRef* ref = static_cast<GWeakRef*>(data);
  g_weak_ref_clear(ref);
  g_free(ref);
}

void OnMap(GtkWidget* view, gpointer) {
  if (g_object_get_data(G_OBJECT(view), kFirstFrameKey) != nullptr) return;
  GWeakRef* ref = g_new0(GWeakRef, 1);
  g_weak_ref_init(ref, view);
  g_timeout_add_seconds_full(G_PRIORITY_DEFAULT, kFirstFrameTimeoutSeconds,
                             OnFirstFrameTimeout, ref, FreeWeakRef);
}

}  // namespace

FlDartProject* secondary_project_new(const gchar* entrypoint_arg) {
  FlDartProject* project = fl_dart_project_new();
  // COMPILE RISK: fl_dart_project_set_dart_entrypoint_arguments expects
  // gchar** (non-const). We cast const away — safe because the embedder
  // copies the strings internally and does not mutate them.
  const gchar* args[] = {entrypoint_arg, nullptr};
  fl_dart_project_set_dart_entrypoint_arguments(project,
                                                const_cast<gchar**>(args));
  fl_dart_project_set_enable_impeller(project, FALSE);
  return project;
}

void secondary_view_watch_first_frame(FlView* view, const gchar* name) {
  g_object_set_data_full(G_OBJECT(view), kNameKey, g_strdup(name), g_free);
  g_signal_connect(view, "first-frame", G_CALLBACK(OnFirstFrame), nullptr);
  g_signal_connect(view, "map", G_CALLBACK(OnMap), nullptr);
}
