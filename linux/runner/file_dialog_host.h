// Owns the public MethodChannel com.whispaste.file_dialog (XP-5-13).
//
// Shows the open, save and folder dialogs with a title and button labels in
// the app language. file_selector_linux hard-codes "Open File", "_Open" and
// "_Cancel" and takes no title, so every dialog showed English text whatever
// the app language was. Same GtkFileChooserNative as the plugin, so desktop
// portals (Flatpak/Snap, GNOME, KDE) are used the same way.

#ifndef FLUTTER_FILE_DIALOG_HOST_H_
#define FLUTTER_FILE_DIALOG_HOST_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

class FileDialogHost {
 public:
  FileDialogHost(FlBinaryMessenger* messenger, FlView* view);
  ~FileDialogHost();

  FileDialogHost(const FileDialogHost&) = delete;
  FileDialogHost& operator=(const FileDialogHost&) = delete;

 private:
  static void OnMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data);

  FlMethodResponse* Show(FlValue* args);

  FlMethodChannel* channel_ = nullptr;
  FlView* view_ = nullptr;
};

#endif  // FLUTTER_FILE_DIALOG_HOST_H_
