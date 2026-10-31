// Runtime test for keybinder_raw.cc (test/scripts/keybinder_raw_test.sh): binds
// <Control><Shift>d the way the plugin's register handler does (init, then
// bind, once per hotkey), presses it with XTest in several keyboard states
// and checks that the binding fires every time. It also checks that binding a
// combination another client holds fails, which the plugin reports as a
// conflict, and that the keypad keyval Flutter sends for Space is mapped to a
// key that can be grabbed (flutter_keyval.cc). "--cooked" uses the plain keybinder_init() so the script can show
// that the test catches the bug.
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>
#include <gtk/gtk.h>
#include <keybinder.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "../flutter_keyval.h"
#include "../keybinder_raw.h"

namespace {

int fired = 0;
int failures = 0;
size_t step = 0;
int fired_before = 0;

void OnHotkey(const char*, void*) { fired++; }

// A fresh connection per call, so XKeysymToKeycode sees a changed layout.
void Send(const KeySym* down, size_t count) {
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) return;
  for (size_t i = 0; i < count; i++) {
    XTestFakeKeyEvent(display, XKeysymToKeycode(display, down[i]), True, 0);
  }
  for (size_t i = count; i > 0; i--) {
    XTestFakeKeyEvent(display, XKeysymToKeycode(display, down[i - 1]), False,
                      0);
  }
  XCloseDisplay(display);
}

void Tap(KeySym key) { Send(&key, 1); }

void PressHotkey() {
  const KeySym keys[] = {XK_Control_L, XK_Shift_L, XK_d};
  Send(keys, 3);
}

int RunCommand(const char* command) { return std::system(command); }

struct Step {
  const char* name;
  void (*before)();
  void (*after)();
};

const Step kSteps[] = {
    {"plain", [] {}, [] {}},
    {"NumLock on", [] { Tap(XK_Num_Lock); }, [] { Tap(XK_Num_Lock); }},
    {"CapsLock on", [] { Tap(XK_Caps_Lock); }, [] { Tap(XK_Caps_Lock); }},
    {"layout switched to Dvorak",
     [] { RunCommand("setxkbmap -layout us -variant dvorak"); },
     [] { RunCommand("setxkbmap -layout us"); }},
};
constexpr size_t kStepCount = sizeof(kSteps) / sizeof(kSteps[0]);

gboolean Check(gpointer);

// Each phase gets 400 ms of main loop, so keybinder sees MappingNotify and
// the key events before the next phase starts.
gboolean Prepare(gpointer) {
  if (step == kStepCount) {
    gtk_main_quit();
    return G_SOURCE_REMOVE;
  }
  kSteps[step].before();
  g_timeout_add(400, [](gpointer) -> gboolean {
    fired_before = fired;
    PressHotkey();
    g_timeout_add(400, Check, nullptr);
    return G_SOURCE_REMOVE;
  }, nullptr);
  return G_SOURCE_REMOVE;
}

gboolean Check(gpointer) {
  const bool ok = fired == fired_before + 1;
  std::printf("%s: %s (fired %d)\n", ok ? "PASS" : "FAIL", kSteps[step].name,
              fired - fired_before);
  if (!ok) failures++;
  kSteps[step].after();
  step++;
  g_timeout_add(400, Prepare, nullptr);
  return G_SOURCE_REMOVE;
}

}  // namespace

int main(int argc, char** argv) {
  const bool cooked = argc > 1 && std::strcmp(argv[1], "--cooked") == 0;
  gtk_init(&argc, &argv);
  // Two hotkeys, each registered like the plugin does it: the second init
  // must not drop the first binding back to cooked matching.
  const char* bindings[] = {"<Control><Shift>d", "<Alt>F9"};
  for (const char* binding : bindings) {
    if (cooked) {
      keybinder_init();
    } else {
      keybinder_init_raw();
    }
    if (!keybinder_bind(binding, OnHotkey, nullptr)) {
      std::printf("FAIL: keybinder_bind %s\n", binding);
      return 1;
    }
  }
  // Another client holds <Alt>F10: binding it must fail, not report success.
  Display* holder = XOpenDisplay(nullptr);
  XGrabKey(holder, XKeysymToKeycode(holder, XK_F10), Mod1Mask,
           DefaultRootWindow(holder), False, GrabModeAsync, GrabModeAsync);
  XSync(holder, False);
  if (keybinder_bind("<Alt>F10", OnHotkey, nullptr)) {
    std::printf("FAIL: binding a held combination reported success\n");
    failures++;
  } else {
    std::printf("PASS: binding a held combination fails\n");
  }
  XCloseDisplay(holder);

  // Flutter sends GDK_KEY_KP_Space for Space (safe-default Ctrl+Shift+Space).
  const auto mods =
      static_cast<GdkModifierType>(GDK_CONTROL_MASK | GDK_SHIFT_MASK);
  gchar* keypad = gtk_accelerator_name(GDK_KEY_KP_Space, mods);
  gchar* mapped = gtk_accelerator_name(
      hotkey_keyval_from_flutter(GDK_KEY_KP_Space), mods);
  if (keybinder_bind(keypad, OnHotkey, nullptr)) {
    std::printf("FAIL: %s bound, the keyval check proves nothing\n", keypad);
    failures++;
  } else if (!keybinder_bind(mapped, OnHotkey, nullptr)) {
    std::printf("FAIL: the mapped Space hotkey %s does not bind\n", mapped);
    failures++;
  } else {
    std::printf("PASS: Space from Flutter binds as %s\n", mapped);
    keybinder_unbind(mapped, OnHotkey);
  }
  g_free(keypad);
  g_free(mapped);

  g_timeout_add(400, Prepare, nullptr);
  gtk_main();
  return failures == 0 ? 0 : 1;
}
