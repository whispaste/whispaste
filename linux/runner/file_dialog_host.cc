#include "file_dialog_host.h"

#include <cstring>

namespace {

constexpr char kChannelName[] = "com.whispaste.file_dialog";

// String value of [key] in the map [args], or nullptr when absent or not a
// string.
const gchar* LookupString(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

gboolean LookupBool(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}

// Adds every string of the list [items] to [filter] through [add].
void AddFilterItems(GtkFileFilter* filter, FlValue* items,
                    void (*add)(GtkFileFilter*, const gchar*)) {
  if (items == nullptr || fl_value_get_type(items) != FL_VALUE_TYPE_LIST) {
    return;
  }
  for (size_t i = 0; i < fl_value_get_length(items); i++) {
    FlValue* item = fl_value_get_list_value(items, i);
    if (fl_value_get_type(item) == FL_VALUE_TYPE_STRING) {
      add(filter, fl_value_get_string(item));
    }
  }
}

// One filter per {label, patterns, mimeTypes} map, as file_selector_linux
// builds them: the patterns are globs such as "*.wav".
void AddFilters(GtkFileChooser* chooser, FlValue* filters) {
  if (filters == nullptr || fl_value_get_type(filters) != FL_VALUE_TYPE_LIST) {
    return;
  }
  for (size_t i = 0; i < fl_value_get_length(filters); i++) {
    FlValue* group = fl_value_get_list_value(filters, i);
    if (fl_value_get_type(group) != FL_VALUE_TYPE_MAP) continue;
    GtkFileFilter* filter = gtk_file_filter_new();
    const gchar* label = LookupString(group, "label");
    gtk_file_filter_set_name(filter, label != nullptr ? label : "");
    AddFilterItems(filter, fl_value_lookup_string(group, "patterns"),
                   gtk_file_filter_add_pattern);
    AddFilterItems(filter, fl_value_lookup_string(group, "mimeTypes"),
                   gtk_file_filter_add_mime_type);
    gtk_file_chooser_add_filter(chooser, filter);
  }
}

}  // namespace

FileDialogHost::FileDialogHost(FlBinaryMessenger* messenger, FlView* view)
    : view_(view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  channel_ =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel_, OnMethodCall, this,
                                            nullptr);
}

FileDialogHost::~FileDialogHost() {
  if (channel_ != nullptr) {
    fl_method_channel_set_method_call_handler(channel_, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&channel_);
}

void FileDialogHost::OnMethodCall(FlMethodChannel* /*channel*/,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  auto* self = static_cast<FileDialogHost*>(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  if (strcmp(method, "show") == 0 &&
      args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    response = self->Show(args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

FlMethodResponse* FileDialogHost::Show(FlValue* args) {
  const gchar* action_name = LookupString(args, "action");
  GtkFileChooserAction action = GTK_FILE_CHOOSER_ACTION_OPEN;
  if (g_strcmp0(action_name, "save") == 0) {
    action = GTK_FILE_CHOOSER_ACTION_SAVE;
  } else if (g_strcmp0(action_name, "folder") == 0) {
    action = GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
  }
  GtkWindow* window =
      GTK_WINDOW(gtk_widget_get_toplevel(GTK_WIDGET(view_)));

  g_autoptr(GtkFileChooserNative) dialog = gtk_file_chooser_native_new(
      LookupString(args, "title"), window, action,
      LookupString(args, "accept"), LookupString(args, "cancel"));
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_select_multiple(chooser, LookupBool(args, "multiple"));
  if (action == GTK_FILE_CHOOSER_ACTION_SAVE) {
    gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
  }
  if (action != GTK_FILE_CHOOSER_ACTION_OPEN) {
    gtk_file_chooser_set_create_folders(chooser,
                                        LookupBool(args, "createFolders"));
  }
  const gchar* folder = LookupString(args, "folder");
  if (folder != nullptr) gtk_file_chooser_set_current_folder(chooser, folder);
  const gchar* name = LookupString(args, "name");
  if (name != nullptr) gtk_file_chooser_set_current_name(chooser, name);
  AddFilters(chooser, fl_value_lookup_string(args, "filters"));

  g_autoptr(FlValue) paths = fl_value_new_list();
  if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(dialog)) ==
      GTK_RESPONSE_ACCEPT) {
    GSList* files = gtk_file_chooser_get_filenames(chooser);
    for (GSList* f = files; f != nullptr; f = f->next) {
      fl_value_append_take(paths,
                           fl_value_new_string(static_cast<gchar*>(f->data)));
    }
    g_slist_free_full(files, g_free);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(paths));
}
