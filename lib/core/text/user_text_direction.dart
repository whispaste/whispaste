import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart' show Bidi;

/// The direction of text a user wrote, from its first strong letter, the
/// way `dir="auto"` works on the web (#1845).
///
/// A German recording inside the Hebrew UI keeps its full stop and its
/// overflow ellipsis at its own end instead of the UI's. Null when the text
/// has no strong letter (digits, punctuation): it then follows the UI.
TextDirection? userTextDirection(String text) {
  if (Bidi.startsWithRtl(text)) return TextDirection.rtl;
  if (Bidi.startsWithLtr(text)) return TextDirection.ltr;
  return null;
}

/// Keeps user text at the start edge of the surrounding UI whatever its own
/// direction, so a list stays aligned when rows mix scripts.
TextAlign userTextAlign(BuildContext context) =>
    Directionality.of(context) == TextDirection.rtl
    ? TextAlign.right
    : TextAlign.left;
