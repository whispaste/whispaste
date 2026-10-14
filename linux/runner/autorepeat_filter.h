#ifndef RUNNER_AUTOREPEAT_FILTER_H_
#define RUNNER_AUTOREPEAT_FILTER_H_

// X11 autorepeat filter for push-to-talk key-up (XInput2 raw events). Pure
// and free of X11/GLib so autorepeat_filter_test.cc can run on any host.
//
// In non-detectable autorepeat mode a held key emits release/press pairs
// back to back. A release of the watched key therefore only arms a short
// confirmation timer; a press of the same key before it fires was
// autorepeat and disarms it. Only a release that stays unanswered is the
// user letting go.

enum class RawKeyAction {
  kIgnore,
  kScheduleRelease,
  kCancelPendingRelease,
};

// [watched_keycode] 0 means no push-to-talk key is held.
inline RawKeyAction ClassifyRawKeyEvent(unsigned watched_keycode,
                                        unsigned keycode, bool is_release) {
  if (watched_keycode == 0 || keycode != watched_keycode) {
    return RawKeyAction::kIgnore;
  }
  return is_release ? RawKeyAction::kScheduleRelease
                    : RawKeyAction::kCancelPendingRelease;
}

#endif  // RUNNER_AUTOREPEAT_FILTER_H_
