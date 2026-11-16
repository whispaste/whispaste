// ---------------------------------------------------------------------------
// WpFavouriteStar — the one favourite toggle of every list (#1498).
//
// Recordings, notes, snippets and the dictionary all put their star through
// this widget, so the star has one glyph pair, one colour, one name and one
// hit area everywhere. Before, each list assembled its own star: different
// glyphs (an icon-font outline is wider than the Lucide one, which made the
// hit areas differ), different names ("Favourite", "Mark as favourite",
// "Add to favourites") and, in the dictionary, a second painted variant.
//
// Off: the Lucide outline in `textMuted`. On: the solid star in
// `pinnedAccent`, the same mark `WpListItemStarMark` shows at rest. The name
// states what a press does ("Add to favourites" / "Remove from favourites"),
// and the toggle carries the `toggled` flag for the current state.
//
// Built on [WpRowAction], so it shares hover, focus ring and the reveal group
// with Copy and Delete. [dense] picks the 28 px item-row box; the standard
// variant has the 48 px target of the dictionary rows.
//
// [WpFavouriteStar.head] is the same star in an editor head (recording
// detail, note, snippet detail): the 32 px compact ghost of its neighbours
// in `WpHeadActions`, so it shares their slot, hover wash and focus ring.
// Before, each head assembled its own star from a bare `WpIconButton`, a
// second look for the same element without the `toggled` state (#1498).
// ---------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import 'wp_icon_button.dart';
import 'wp_row_action.dart';

class WpFavouriteStar extends StatelessWidget {
  const WpFavouriteStar({
    super.key,
    required this.isFavourite,
    required this.onToggle,
    this.testId,
    this.dense = true,
    this.semanticsLabel,
    this.tooltip,
  }) : _head = false,
       shortcut = null;

  /// The star of an editor head: a compact ghost in a `WpHeadActions` slot.
  /// [shortcut] is appended to the tooltip ("(F)" in the recording detail).
  const WpFavouriteStar.head({
    super.key,
    required this.isFavourite,
    required this.onToggle,
    this.testId,
    this.shortcut,
  }) : _head = true,
       dense = false,
       semanticsLabel = null,
       tooltip = null;

  final bool isFavourite;

  /// `null` disables the control.
  final VoidCallback? onToggle;

  /// Stable automation id (`<screen>-favourite-<id>`).
  final String? testId;

  /// 28 px item-row box; `false` gives the 48 px target.
  final bool dense;

  /// Key hint shown in the tooltip of a head star, e.g. `F`.
  final String? shortcut;

  /// Screen-reader name when the star needs its object in it, e.g.
  /// "Favorite: German" on a language tile (#1610). Defaults to the tooltip.
  final String? semanticsLabel;

  /// Replaces the default "add/remove" tooltip, e.g. to say why a disabled
  /// star cannot be set (favorites limit).
  final String? tooltip;

  final bool _head;

  /// Accessible name of the star in [isFavourite] state: what a press does.
  static String labelFor(L10n l10n, {required bool isFavourite}) =>
      isFavourite ? l10n.historyUnpin : l10n.historyPinToTop;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final label = labelFor(l10n, isFavourite: isFavourite);
    if (_head) {
      final key = shortcut;
      // One node: the toggle state merges into the button's own node, which
      // carries the name and the identifier. `selected` would announce it
      // too, but paints the accent wash of a tool toggle, not the star.
      return MergeSemantics(
        child: Semantics(
          toggled: isFavourite,
          child: WpIconButton.ghost(
            compact: true,
            testId: testId,
            icon: isFavourite ? null : LucideIcons.star,
            faIcon: isFavourite ? FontAwesomeIcons.solidStar : null,
            color: isFavourite ? WpSharedColors.pinnedAccent : null,
            tooltip: key == null ? label : '$label ($key)',
            onPressed: onToggle,
          ),
        ),
      );
    }
    return WpRowAction(
      testId: testId,
      faIcon: isFavourite ? FontAwesomeIcons.solidStar : null,
      icon: isFavourite ? null : LucideIcons.star,
      activeColor: isFavourite ? WpSharedColors.pinnedAccent : null,
      tooltip: tooltip ?? label,
      semanticsLabel: semanticsLabel,
      toggled: isFavourite,
      onTap: onToggle,
      dense: dense,
    );
  }
}
