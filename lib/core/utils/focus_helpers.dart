/// Focus-state helpers shared by every feature that binds bare-key shortcuts.
///
/// Lives in `core/` rather than in one feature's widget folder because the
/// question it answers — "is the user typing right now?" — belongs to no
/// domain in particular. History, notes and the detail panel all have to ask
/// it before letting a bare key (Delete, C, E, …) act, and routing that
/// through `features/history/` would make notes depend on history for a fact
/// that has nothing to do with either (`CONTEXT.md` §5.9: no feature-to-feature
/// dependency between `lib/features/notes/` and `lib/features/history/`).
library;

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
