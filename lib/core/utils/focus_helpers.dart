/// Focus-state helpers shared by every feature that binds bare-key shortcuts.
///
/// Lives in `core/` rather than in one feature's widget folder because the
/// question it answers — "is the user typing right now?" — belongs to no
/// domain in particular. History, notes and the detail panel all have to ask
/// it before letting a bare key (Delete, C, E, …) act, and routing that
/// through `features/history/` would make notes depend on history for a fact
/// that has nothing to do with either (`internal-notes` §5.9: no feature-to-feature
/// dependency between `lib/features/notes/` and `lib/features/history/`).
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Returns true when the focused widget is an [EditableText] (text input).
///
/// `EditableText.build()` creates an internal `Focus` widget that overwrites
/// the FocusNode context, so `context.widget` ends up being `Focus`, not
/// `EditableText`. We check the widget directly AND walk ancestors as a
/// fallback to cover both cases.
bool isTextFieldFocused() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final context = primary.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Index of the item [delta] steps away from [currentIndex] in a list of
/// [length] items, clamped to the ends. A [currentIndex] of -1 (nothing
/// focused yet) starts at the first item going forward and at the last going
/// backward. [length] must be positive.
int nextFocusIndex(int currentIndex, int delta, int length) {
  if (currentIndex < 0) return delta > 0 ? 0 : length - 1;
  return (currentIndex + delta).clamp(0, length - 1);
}

/// True when no modifier (Ctrl, Cmd, Alt, Shift) is held: a bare letter key
/// belongs to the list, a modified one to the page or the platform.
bool noModifierPressed() {
  final hk = HardwareKeyboard.instance;
  return !hk.isControlPressed &&
      !hk.isMetaPressed &&
      !hk.isAltPressed &&
      !hk.isShiftPressed;
}

/// True when exactly the platform command modifier is held (Cmd on macOS,
/// Ctrl elsewhere), without Alt or Shift: the state in which Cmd/Ctrl+C or +A
/// is a plain "copy" or "select all". Page shortcuts for those keys are
/// handled in a `Focus.onKeyEvent` after an [isTextFieldFocused] check rather
/// than through `CallbackShortcuts`, which would consume the key and keep
/// the text field from copying its own selection.
bool commandOnlyPressed() {
  final hk = HardwareKeyboard.instance;
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  return (mac
          ? hk.isMetaPressed && !hk.isControlPressed
          : hk.isControlPressed && !hk.isMetaPressed) &&
      !hk.isAltPressed &&
      !hk.isShiftPressed;
}

/// Shared step keys of every list (recordings, notes, snippets/replacements;
/// `internal-notes` §5.5.15 list keys, #277): arrow down or a bare J moves one
/// item down (returns 1), arrow up or a bare K one item up (returns -1),
/// anything else returns null. J/K only count without a modifier, so
/// Cmd/Ctrl+J stays free for the platform. Callers check
/// [isTextFieldFocused] first, so J and K still type into a field.
int? listStepFor(LogicalKeyboardKey key) {
  if (key == LogicalKeyboardKey.arrowDown) return 1;
  if (key == LogicalKeyboardKey.arrowUp) return -1;
  if (!noModifierPressed()) return null;
  if (key == LogicalKeyboardKey.keyJ) return 1;
  if (key == LogicalKeyboardKey.keyK) return -1;
  return null;
}
