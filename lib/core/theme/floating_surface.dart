/// The one look of everything that floats above a screen: dialogs, select
/// lists and popover panels. Same fill, rim, radius and shadow everywhere, so
/// a list that drops down and a panel that opens read as one family.
library;

import 'package:flutter/widgets.dart';

import 'colors.dart';
import 'tokens.dart';

abstract final class WpFloatingSurface {
  static BorderRadius get radius => WpRadius.borderLg;

  // Card material, pre-composited (see `WpColors.floatingSurface`); the rim
  // is the tinted `cardEdgeHighlight` every card carries, and `elevated` is
  // the one sanctioned shadow for surfaces that really float.
  static BoxDecoration get decoration => BoxDecoration(
    color: WpColors.floatingSurface,
    borderRadius: radius,
    border: Border.all(color: WpColors.cardEdgeHighlight),
    boxShadow: WpShadows.elevated,
  );
}
