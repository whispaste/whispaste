/// Controls of the recording dock (WP-79, ADR 0024): the Dictate button with
/// its keycap, the selectors, the Mehr button and the one popup every dock
/// control opens. One chrome for every control: 48 px tall, a 12 px radius, the
/// stage's control fill with a 3:1 outline, and the same hover, pressed and
/// focus states.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../core/theme/generated/wp_tokens.g.dart'
    show
        WpDockTokens,
        WpShellTokens,
        WpSurfacePalette,
        WpTypeScaleTokens,
        wpStagePalette;
import '../core/theme/tokens.dart';
import '../core/utils/search_fold.dart';
import 'recording_dock_layout.dart';
import 'wp_focus_ring.dart';
import 'wp_search_field.dart';

const WpSurfacePalette _dock = wpStagePalette;

/// Horizontal space a selector spends around its value: padding on both
/// sides, the leading icon with its gap, and the chevron with its gap.
const double dockSelectorChrome =
    2 * WpDockTokens.selectorPaddingX +
    WpIconSize.sm +
    WpSpacing.xs +
    WpSpacing.xxs +
    WpIconSize.sm;

/// Slack added to every measured text so a control never renders wider than
/// its measurement.
const double dockMeasureSlack = 4;

/// Width of [text] on one line in [style], at the current text scale.
double dockTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

/// Label of the Dictate button: 16 px semibold on the record fill.
TextStyle dockDictateLabelStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleMedium!.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: WpColors.onPrimaryRecord,
    );

/// Text of the keycap inside the Dictate button.
TextStyle dockKeycapStyle(BuildContext context) => Theme.of(
  context,
).textTheme.labelMedium!.copyWith(color: WpColors.onPrimaryRecord);

/// Overline of a labelled selector and of every popup group header: 11 px
/// caps, secondary text.
TextStyle dockOverlineStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelSmall!.copyWith(
      fontSize: WpTypeScaleTokens.overline,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.6,
      color: _dock.textSecondary,
    );

/// Value of a selector: 14 px semibold, primary text.
TextStyle dockValueStyle(BuildContext context) =>
    Theme.of(context).textTheme.labelLarge!.copyWith(
      fontSize: WpTypeScaleTokens.label,
      fontWeight: FontWeight.w600,
      color: _dock.textPrimary,
    );

/// The Dictate button: the one filled control of the dock. Cyan in the light
/// and navy modes; amber in Marine (WP-50, an accent surface under the amber
/// rule, WCAG AA). The hotkey is shown once, as a keycap inside the
/// button, when [keycapLabel] is set.
class WpDockDictate extends StatefulWidget {
  const WpDockDictate({
    super.key,
    required this.label,
    required this.recording,
    required this.width,
    this.onPressed,
    this.hotkeyHint,
    this.keycapLabel,
    this.keycapDimmed = false,
  });

  final String label;
  final bool recording;
  final double width;
  final VoidCallback? onPressed;

  /// The hotkey, named in the tooltip and as the button's accessible hint.
  final String? hotkeyHint;

  /// The hotkey keycap drawn inside the button, or null when the row has no
  /// room for it (the hotkey stays in the tooltip and in Mehr).
  final String? keycapLabel;

  /// True while the hotkey is switched off: the keycap is drawn dimmed.
  final bool keycapDimmed;

  @override
  State<WpDockDictate> createState() => _WpDockDictateState();
}

class _WpDockDictateState extends State<WpDockDictate> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'dock-dictate');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final iconOnly = widget.width <= WpDockTokens.controlHeight;
    final fill = enabled
        ? WpColors.primaryRecordFill
        : WpColors.primaryRecordFill.withValues(alpha: 0.7);
    final radius = BorderRadius.circular(WpDockTokens.controlRadius);
    final labelStyle = dockDictateLabelStyle(context);
    final hotkey = widget.hotkeyHint;
    final keycap = widget.keycapLabel;
    return Tooltip(
      message: hotkey == null ? widget.label : '${widget.label} ($hotkey)',
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        hint: hotkey,
        identifier: 'dock-dictate',
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpDockTokens.controlRadius,
          ringColor: _dock.accent,
          child: Material(
            color: fill,
            borderRadius: radius,
            child: InkWell(
              key: const ValueKey('dock-dictate'),
              focusNode: _focusNode,
              onTap: widget.onPressed,
              borderRadius: radius,
              hoverColor: WpColors.primaryRecordHover.withValues(alpha: 0.25),
              child: SizedBox(
                width: widget.width,
                height: WpDockTokens.controlHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ExcludeSemantics(
                        child: Icon(
                          widget.recording
                              ? LucideIcons.square
                              : LucideIcons.mic,
                          size: WpIconSize.md,
                          color: WpColors.onPrimaryRecord,
                        ),
                      ),
                      // Icon-only at the controlHeight width: the accessible
                      // name still carries the full label.
                      if (!iconOnly) ...[
                        const SizedBox(width: WpSpacing.xs),
                        Flexible(
                          child: ExcludeSemantics(
                            child: Text(
                              widget.label,
                              style: labelStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      if (!iconOnly && keycap != null) ...[
                        const SizedBox(width: WpSpacing.xs),
                        ExcludeSemantics(
                          child: _Keycap(
                            key: const ValueKey('dock-dictate-keycap'),
                            label: keycap,
                            dimmed: widget.keycapDimmed,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hotkey keycap inside the Dictate button: a translucent chip on the
/// record fill. It is only a visual; the tap target is the whole button, and
/// the shortcut itself is changed from Mehr.
class _Keycap extends StatelessWidget {
  const _Keycap({super.key, required this.label, required this.dimmed});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dimmed ? 0.5 : 1,
    child: Container(
      height: WpSpacing.lg,
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: WpColors.onPrimaryRecord.withValues(alpha: 0.18),
        borderRadius: WpRadius.borderSm,
        border: Border.all(
          color: WpColors.onPrimaryRecord.withValues(alpha: 0.5),
        ),
      ),
      child: Text(label, style: dockKeycapStyle(context), maxLines: 1),
    ),
  );
}

/// The visual of a selector: icon, value and chevron. A labelled selector
/// adds its overline; an icon-only one shows the icon alone.
class WpDockSelectorBody extends StatelessWidget {
  const WpDockSelectorBody({
    super.key,
    required this.form,
    required this.icon,
    required this.overline,
    required this.value,
    this.compactValue,
  });

  final WpDockSelectorForm form;
  final IconData icon;
  final String overline;
  final String value;

  /// The value shown where the overline is left out; defaults to [value].
  final String? compactValue;

  @override
  Widget build(BuildContext context) {
    if (form == WpDockSelectorForm.iconOnly) {
      return Center(
        child: Icon(icon, size: WpIconSize.md, color: _dock.textPrimary),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpDockTokens.selectorPaddingX,
      ),
      child: Row(
        children: [
          Icon(icon, size: WpIconSize.sm, color: _dock.textSecondary),
          const SizedBox(width: WpSpacing.xs),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (form == WpDockSelectorForm.labelled)
                  Text(
                    overline.toUpperCase(),
                    style: dockOverlineStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  form == WpDockSelectorForm.labelled
                      ? value
                      : (compactValue ?? value),
                  style: dockValueStyle(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.xxs),
          Icon(
            LucideIcons.chevronDown,
            size: WpIconSize.sm,
            color: _dock.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// The outline and fill every selector wears. A focused selector gets the
/// 2.5 px accent ring, so keyboard focus is visible (WCAG 2.4.7).
class _SelectorChrome extends StatelessWidget {
  const _SelectorChrome({required this.focused, required this.child});

  final bool focused;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(WpDockTokens.controlRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _dock.control,
        borderRadius: radius,
        border: Border.all(
          color: focused ? _dock.accent : _dock.borderControl,
          width: focused ? WpShellTokens.focusRingWidth : 1,
        ),
      ),
      child: ClipRRect(borderRadius: radius, child: child),
    );
  }
}

/// A dock control that either runs [onTap] (Smart Mode, engine, language) or
/// opens a dock popup built by [menu] (output action, microphone). Keyboard
/// focus shows the shared focus ring.
class WpDockSelector extends StatefulWidget {
  const WpDockSelector({
    super.key,
    required this.id,
    required this.form,
    required this.icon,
    required this.overline,
    required this.value,
    this.compactValue,
    this.onTap,
    this.menu,
    this.onMenuOpened,
  });

  /// Stable id; the key and semantics identifier are `dock-<id>`.
  final String id;
  final WpDockSelectorForm form;
  final IconData icon;
  final String overline;
  final String value;

  /// The value shown without the overline (compact stage); defaults to
  /// [value]. The tooltip and semantics always use [overline] and [value].
  final String? compactValue;
  final VoidCallback? onTap;

  /// Builds the entries of the popup this control opens. Used instead of
  /// [onTap] when set.
  final List<WpDockMenuSpec> Function()? menu;

  /// Runs before [menu] is built, e.g. to refresh the microphone list.
  final VoidCallback? onMenuOpened;

  @override
  State<WpDockSelector> createState() => _WpDockSelectorState();
}

class _WpDockSelectorState extends State<WpDockSelector> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool get _hasAction => widget.onTap != null || widget.menu != null;

  void _activate() {
    final menu = widget.menu;
    if (menu == null) {
      widget.onTap?.call();
      return;
    }
    widget.onMenuOpened?.call();
    showWpDockMenu(
      context,
      anchor: dockAnchorOf(context),
      alignEnd: false,
      items: menu(),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = '${widget.overline}: ${widget.value}';
    return Tooltip(
      message: label,
      child: Semantics(
        button: _hasAction,
        enabled: _hasAction,
        label: label,
        identifier: 'dock-${widget.id}',
        child: ExcludeSemantics(
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpDockTokens.controlRadius,
            ringColor: _dock.accent,
            child: _SelectorChrome(
              focused: _focusNode.hasFocus,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  focusNode: _focusNode,
                  onTap: _hasAction ? _activate : null,
                  hoverColor: _dock.controlHover,
                  highlightColor: _dock.pressed,
                  child: WpDockSelectorBody(
                    form: widget.form,
                    icon: widget.icon,
                    overline: widget.overline,
                    value: widget.value,
                    compactValue: widget.compactValue,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Mehr button: every control that does not fit the row, the notices and
/// the sponsor entry. Opens the dock popup above the dock, right-aligned to
/// the button.
class WpDockOverflow extends StatefulWidget {
  const WpDockOverflow({
    super.key,
    required this.entries,
    required this.attention,
    required this.tooltip,
    required this.onOpened,
  });

  final List<WpDockMenuSpec> entries;
  final bool attention;
  final String tooltip;
  final VoidCallback? onOpened;

  @override
  State<WpDockOverflow> createState() => _WpDockOverflowState();
}

class _WpDockOverflowState extends State<WpDockOverflow> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _open() {
    widget.onOpened?.call();
    showWpDockMenu(
      context,
      anchor: dockAnchorOf(context),
      alignEnd: true,
      items: widget.entries,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        identifier: 'dock-overflow',
        child: ExcludeSemantics(
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpDockTokens.controlRadius,
            ringColor: _dock.accent,
            child: _SelectorChrome(
              focused: _focusNode.hasFocus,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('dock-overflow'),
                  focusNode: _focusNode,
                  onTap: _open,
                  hoverColor: _dock.controlHover,
                  highlightColor: _dock.pressed,
                  child: SizedBox(
                    width: WpDockTokens.controlHeight,
                    height: WpDockTokens.controlHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          LucideIcons.ellipsis,
                          size: WpIconSize.md,
                          color: _dock.textPrimary,
                        ),
                        if (widget.attention)
                          Positioned(
                            top: WpSpacing.xs,
                            right: WpSpacing.xs,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: cs.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rectangle of the trigger of a dock control, and the top edge of the
/// dock above it: the popup is placed against both.
Rect dockAnchorOf(BuildContext context) {
  final box = context.findRenderObject()! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

// --- Dock popup ------------------------------------------------------------

/// Gap between the dock's top edge and the popup, and the margin kept to the
/// window edges.
const double _popupGap = WpSpacing.xs;
const double _popupEdge = WpSpacing.xs;

/// Every dock popup is this wide, so labels line up across popups.
const double _popupWidth = 280;

/// One entry of a dock popup. Every dock popup, the Mehr menu and the
/// output and microphone selectors alike, is built from these.
sealed class WpDockMenuSpec {
  const WpDockMenuSpec();
}

/// Overline header of a group of entries.
final class WpDockMenuHeader extends WpDockMenuSpec {
  const WpDockMenuHeader(this.text);

  final String text;
}

/// Status information: a non-interactive row, visually distinct from actions.
final class WpDockMenuInfo extends WpDockMenuSpec {
  const WpDockMenuInfo({
    required this.id,
    required this.icon,
    required this.label,
  });

  /// Semantics identifier, `dock-menu-<name>`.
  final String id;
  final IconData icon;
  final String label;
}

/// An action row. With [checked] it marks the current choice of a radio group.
final class WpDockMenuAction extends WpDockMenuSpec {
  const WpDockMenuAction({
    required this.id,
    required this.icon,
    required this.label,
    this.onTap,
    this.checked = false,
    this.tooltip,
    this.searchText,
  });

  /// Semantics identifier and key, `dock-menu-<name>`.
  final String id;
  final IconData icon;
  final String label;

  /// Null disables the row.
  final VoidCallback? onTap;
  final bool checked;
  final String? tooltip;

  /// The text a search query is matched against. Null keeps the row listed
  /// whatever the query.
  final String? searchText;
}

/// A list with a search field above its [entries]. The query narrows the
/// actions (see [filterDockMenuEntries]); the list is kept in the popup's
/// state, so it works at the top level and inside a Mehr submenu alike.
final class WpDockMenuSearchable extends WpDockMenuSpec {
  const WpDockMenuSearchable({
    required this.id,
    required this.searchHint,
    required this.noMatchesLabel,
    required this.entries,
  });

  /// Stable id of the list, `dock-menu-<name>`: the search field is
  /// `<id>-search` and the no-match text `<id>-empty`.
  final String id;
  final String searchHint;
  final String noMatchesLabel;
  final List<WpDockMenuSpec> entries;
}

/// The entries that remain for [query]: an action stays when its
/// [WpDockMenuAction.searchText] contains the query, ignoring case and
/// accents; an action without searchText always stays. A group header stays
/// only while one of its actions does. An empty query keeps everything.
List<WpDockMenuSpec> filterDockMenuEntries(
  List<WpDockMenuSpec> entries,
  String query,
) {
  final needle = foldForSearch(query.trim());
  if (needle.isEmpty) return entries;
  final kept = <WpDockMenuSpec>[];
  WpDockMenuHeader? pendingHeader;
  for (final entry in entries) {
    switch (entry) {
      case WpDockMenuHeader():
        pendingHeader = entry;
      case WpDockMenuAction(searchText: final text?):
        if (!foldForSearch(text).contains(needle)) continue;
        final header = pendingHeader;
        if (header != null) kept.add(header);
        pendingHeader = null;
        kept.add(entry);
      default:
        kept.add(entry);
    }
  }
  return kept;
}

/// A row that expands in place to show [children], used for the Mehr submenus
/// (Smart Mode, language, speech recognition).
final class WpDockMenuSubmenu extends WpDockMenuSpec {
  const WpDockMenuSubmenu({
    required this.id,
    required this.icon,
    required this.label,
    required this.children,
  });

  /// Semantics identifier, `dock-menu-<name>`.
  final String id;
  final IconData icon;
  final String label;
  final List<WpDockMenuSpec> children;
}

/// A thin separator between groups.
final class WpDockMenuDivider extends WpDockMenuSpec {
  const WpDockMenuDivider();
}

/// Opens the shared dock popup above the dock. The card's bottom edge sits
/// [_popupGap] above the dock's top edge; its right edge (or left edge, when
/// [alignEnd] is false) lines up with the trigger's anchor.
Future<void> showWpDockMenu(
  BuildContext context, {
  required Rect anchor,
  required bool alignEnd,
  required List<WpDockMenuSpec> items,
  required String barrierLabel,
}) {
  final dockTop =
      anchor.top - (WpShellTokens.dockHeight - WpDockTokens.controlHeight) / 2;
  return Navigator.of(context).push<void>(
    _WpDockMenuRoute(
      anchor: anchor,
      dockTop: dockTop,
      alignEnd: alignEnd,
      items: items,
      barrierLabel: barrierLabel,
    ),
  );
}

class _WpDockMenuRoute extends PopupRoute<void> {
  _WpDockMenuRoute({
    required this.anchor,
    required this.dockTop,
    required this.alignEnd,
    required this.items,
    required this.barrierLabel,
  });

  final Rect anchor;
  final double dockTop;
  final bool alignEnd;
  final List<WpDockMenuSpec> items;
  @override
  final String? barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  // The generated duration group was dropped as unread (UIA-FND-08); the
  // hand-written motion scale is the one source for durations.
  Duration get transitionDuration => WpMotion.fast;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CustomSingleChildLayout(
        delegate: _WpDockMenuLayout(
          anchor: anchor,
          dockTop: dockTop,
          alignEnd: alignEnd,
          textDirection: Directionality.of(context),
        ),
        child: _WpDockMenuPanel(items: items),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

/// Places the card above the dock. Horizontal: aligned to the anchor's end
/// (right in LTR, left in RTL) when [alignEnd], otherwise to its start.
class _WpDockMenuLayout extends SingleChildLayoutDelegate {
  _WpDockMenuLayout({
    required this.anchor,
    required this.dockTop,
    required this.alignEnd,
    required this.textDirection,
  });

  final Rect anchor;
  final double dockTop;
  final bool alignEnd;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: _popupWidth,
        maxWidth: _popupWidth,
        maxHeight: math.max(0, dockTop - _popupGap - _popupEdge),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final rightAligned = alignEnd == (textDirection == TextDirection.ltr);
    final wanted = rightAligned ? anchor.right - childSize.width : anchor.left;
    final x = math.min(
      math.max(wanted, _popupEdge),
      math.max(_popupEdge, size.width - _popupEdge - childSize.width),
    );
    final wantedY = dockTop - _popupGap - childSize.height;
    final y = math.max(_popupEdge, wantedY);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_WpDockMenuLayout old) =>
      anchor != old.anchor ||
      dockTop != old.dockTop ||
      alignEnd != old.alignEnd ||
      textDirection != old.textDirection;
}

/// The card: navy, one step above the dock surface, outlined, with the
/// popup radius and elevation shared by every dock popup.
class _WpDockMenuPanel extends StatelessWidget {
  const _WpDockMenuPanel({required this.items});

  final List<WpDockMenuSpec> items;

  @override
  Widget build(BuildContext context) {
    // A searchable list starts on its search field. Otherwise focus starts on
    // the checked choice of a radio group, else on the first enabled action,
    // so arrow keys and Enter work at once.
    final searchIndex = items.indexWhere((i) => i is WpDockMenuSearchable);
    final checkedIndex = items.indexWhere(
      (i) => i is WpDockMenuAction && i.checked && i.onTap != null,
    );
    final firstIndex = items.indexWhere(
      (i) => i is WpDockMenuAction && i.onTap != null,
    );
    final focusIndex = searchIndex >= 0
        ? searchIndex
        : checkedIndex >= 0
        ? checkedIndex
        : firstIndex;
    return FocusTraversalGroup(
      child: Material(
        key: const ValueKey('dock-menu-panel'),
        color: _dock.card,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: WpRadius.borderSm,
          side: BorderSide(color: _dock.borderDefault),
        ),
        clipBehavior: Clip.antiAlias,
        // A long menu scrolls inside the card instead of overflowing the window.
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                _buildItem(context, items[i], autofocus: i == focusIndex),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    WpDockMenuSpec item, {
    required bool autofocus,
  }) => switch (item) {
    WpDockMenuHeader(:final text) => Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.sm,
        WpSpacing.md,
        WpSpacing.xxs,
      ),
      child: Semantics(
        header: true,
        child: Text(text.toUpperCase(), style: dockOverlineStyle(context)),
      ),
    ),
    WpDockMenuInfo() => _WpDockMenuInfoRow(item: item),
    WpDockMenuAction() => _WpDockMenuActionRow(
      item: item,
      autofocus: autofocus,
    ),
    WpDockMenuSubmenu() => _WpDockMenuSubmenuRow(
      item: item,
      children: [
        for (final child in item.children)
          _buildItem(context, child, autofocus: false),
      ],
    ),
    WpDockMenuSearchable() => _WpDockMenuSearchableView(
      item: item,
      autofocus: autofocus,
      buildItem: (child) => _buildItem(context, child, autofocus: false),
    ),
    WpDockMenuDivider() => Divider(
      height: WpSpacing.md,
      indent: WpSpacing.md,
      endIndent: WpSpacing.md,
      color: _dock.borderSubtle,
    ),
  };
}

class _WpDockMenuInfoRow extends StatelessWidget {
  const _WpDockMenuInfoRow({required this.item});

  final WpDockMenuInfo item;

  @override
  Widget build(BuildContext context) => Semantics(
    identifier: item.id,
    label: item.label,
    child: Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.md,
        vertical: WpSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(item.icon, size: WpIconSize.sm, color: _dock.textSecondary),
          const SizedBox(width: WpSpacing.sm),
          Flexible(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: _dock.textSecondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// The search field and the filtered entries of a [WpDockMenuSearchable].
///
/// The field's own focus node handles the keys, so they win over the text
/// field's caret movement: arrow down moves into the results, Enter runs the
/// first matching option, and Escape clears a query. With no query, Escape is
/// left to the popup, which closes.
class _WpDockMenuSearchableView extends StatefulWidget {
  const _WpDockMenuSearchableView({
    required this.item,
    required this.autofocus,
    required this.buildItem,
  });

  final WpDockMenuSearchable item;
  final bool autofocus;
  final Widget Function(WpDockMenuSpec item) buildItem;

  @override
  State<_WpDockMenuSearchableView> createState() =>
      _WpDockMenuSearchableViewState();
}

class _WpDockMenuSearchableViewState extends State<_WpDockMenuSearchableView> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _fieldFocus = FocusNode(onKeyEvent: _onFieldKey);
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _setQuery(String query) => setState(() => _query = query);

  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      return node.focusInDirection(TraversalDirection.down)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (_query.trim().isEmpty) return KeyEventResult.ignored;
      final target = filterDockMenuEntries(widget.item.entries, _query)
          .whereType<WpDockMenuAction>()
          .where((action) => action.onTap != null)
          .firstOrNull;
      if (target != null) {
        // Same order as a row: the popup closes, then the choice applies.
        Navigator.of(context).pop();
        target.onTap!();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape && _query.isNotEmpty) {
      _controller.clear();
      _setQuery('');
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final visible = filterDockMenuEntries(item.entries, _query);
    final searching = foldForSearch(_query.trim()).isNotEmpty;
    final noMatches = visible.whereType<WpDockMenuAction>().isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          key: ValueKey('${item.id}-search'),
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.md,
            WpSpacing.xs,
            WpSpacing.md,
            WpSpacing.xs,
          ),
          child: Semantics(
            identifier: '${item.id}-search',
            child: WpSearchField(
              controller: _controller,
              focusNode: _fieldFocus,
              hintText: item.searchHint,
              semanticsLabel: item.searchHint,
              variant: WpSearchFieldVariant.outlined,
              autofocus: widget.autofocus,
              onChanged: _setQuery,
              onClear: () => _setQuery(''),
            ),
          ),
        ),
        for (final entry in visible) widget.buildItem(entry),
        if (searching && noMatches)
          Padding(
            key: ValueKey('${item.id}-empty'),
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            child: Text(
              item.noMatchesLabel,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: _dock.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _WpDockMenuActionRow extends StatefulWidget {
  const _WpDockMenuActionRow({required this.item, required this.autofocus});

  final WpDockMenuAction item;
  final bool autofocus;

  @override
  State<_WpDockMenuActionRow> createState() => _WpDockMenuActionRowState();
}

class _WpDockMenuActionRowState extends State<_WpDockMenuActionRow> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Closes the popup, then runs the entry: a choice or a footer link is the
  /// end of the menu's job.
  void _activate() {
    Navigator.of(context).pop();
    widget.item.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final enabled = item.onTap != null;
    _focusNode.canRequestFocus = enabled;
    final color = enabled ? _dock.textPrimary : _dock.textDisabled;
    final markColor = item.checked ? _dock.accent : color;
    final row = Semantics(
      identifier: item.id,
      button: true,
      enabled: enabled,
      checked: item.checked ? true : null,
      child: WpFocusRing(
        focusNode: _focusNode,
        radius: WpRadius.sm,
        ringColor: _dock.accent,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            focusNode: _focusNode,
            autofocus: widget.autofocus,
            onTap: enabled ? _activate : null,
            hoverColor: _dock.controlHover,
            highlightColor: _dock.pressed,
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: WpIconSize.sm, color: markColor),
                  const SizedBox(width: WpSpacing.sm),
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: item.checked
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: color,
                      ),
                    ),
                  ),
                  if (item.checked) ...[
                    const SizedBox(width: WpSpacing.sm),
                    Icon(
                      LucideIcons.check,
                      size: WpIconSize.sm,
                      color: markColor,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = item.tooltip;
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
      child: tooltip == null ? row : Tooltip(message: tooltip, child: row),
    );
  }
}

/// A dock dropdown with more options than this shows a search field above them.
/// Up to ten options are scanned at a glance in the popup; from eleven on
/// (the language list has about a hundred) typing a name is faster than
/// scrolling for it.
const int kDockChoiceSearchThreshold = 10;

/// One option of a dock dropdown. [group] (when set) heads a run of options
/// that share it.
class WpDockChoice {
  const WpDockChoice({
    required this.value,
    required this.label,
    this.group,
    this.unavailableReason,
  });

  final String value;
  final String label;
  final String? group;

  /// Why this option cannot be picked right now (e.g. a Smart Mode preset
  /// without a text model). Set, the option is shown disabled, and the reason
  /// is its tooltip and the menu's note. Null, the option is pickable.
  final String? unavailableReason;
}

/// A dock dropdown: its options, the current one, and what picking an option
/// does. The dock is a view of the settings, so [current] and [currentLabel]
/// come from the same provider that [onChanged] writes.
class WpDockChoiceSet {
  const WpDockChoiceSet({
    required this.id,
    required this.menuId,
    required this.overline,
    required this.icon,
    required this.choices,
    required this.current,
    required this.currentLabel,
    required this.onChanged,
    required this.searchHint,
    required this.noMatchesLabel,
    this.footerLabel,
    this.onFooterTap,
    this.lockedWhileBusy = false,
    this.lockedReason,
    this.note,
    this.favoriteValues = const [],
    this.favoritesLabel,
    this.allLabel,
  });

  /// The row selector's id: `dock-<id>` for the control.
  final String id;

  /// The menu id: `dock-menu-<menuId>` for the Mehr submenu and
  /// `dock-menu-<menuId>-<value>` for each option.
  final String menuId;
  final String overline;
  final IconData icon;
  final List<WpDockChoice> choices;
  final String current;
  final String currentLabel;
  final ValueChanged<String> onChanged;

  /// Placeholder of the search field, shown when there are more than
  /// [kDockChoiceSearchThreshold] options.
  final String searchHint;

  /// Shown in place of the options when the search matches none.
  final String noMatchesLabel;

  /// A footer link under the options, e.g. to the Settings page.
  final String? footerLabel;
  final VoidCallback? onFooterTap;

  /// Disables the options while a dictation is recording or transcribing.
  final bool lockedWhileBusy;

  /// Shown as the reason in the menu and on each disabled option while
  /// [lockedWhileBusy] holds.
  final String? lockedReason;

  /// A non-interactive line at the top of the menu, e.g. when a change applies.
  final String? note;

  /// Values of [choices] the user starred, in the order to list them. They
  /// head the list under [favoritesLabel] and are left out of the full list
  /// below under [allLabel], so each option appears exactly once. Search still
  /// finds them, in that top block.
  final List<String> favoriteValues;

  /// Heading of the favorites block. Null (or no favorites) keeps one flat list.
  final String? favoritesLabel;

  /// Heading of the full list below the favorites block.
  final String? allLabel;
}

/// The menu entries of [set]: its options, then the footer link. Disabled
/// entries keep their place so the menu does not change shape.
List<WpDockMenuSpec> dockChoiceEntries(
  WpDockChoiceSet set, {
  required bool enabled,
}) {
  final entries = <WpDockMenuSpec>[];
  final note = _dockChoiceNote(set, enabled: enabled);
  if (note != null) entries.add(note);
  final options = _dockChoiceOptions(set, enabled: enabled);
  if (set.choices.length > kDockChoiceSearchThreshold) {
    entries.add(
      WpDockMenuSearchable(
        id: 'dock-menu-${set.menuId}',
        searchHint: set.searchHint,
        noMatchesLabel: set.noMatchesLabel,
        entries: options,
      ),
    );
  } else {
    entries.addAll(options);
  }
  final footer = set.footerLabel;
  final footerTap = set.onFooterTap;
  if (footer != null && footerTap != null) {
    entries
      ..add(const WpDockMenuDivider())
      ..add(
        WpDockMenuAction(
          id: 'dock-menu-${set.menuId}-footer',
          icon: LucideIcons.settings,
          label: footer,
          onTap: enabled ? footerTap : null,
        ),
      );
  }
  return entries;
}

/// The note on top of the menu, or null when there is nothing to explain.
WpDockMenuInfo? _dockChoiceNote(WpDockChoiceSet set, {required bool enabled}) {
  // The first option's reason for being unavailable, if any, is the note: it
  // says why the menu cannot be used as usual.
  String? unavailable;
  for (final choice in set.choices) {
    unavailable = choice.unavailableReason;
    if (unavailable != null) break;
  }
  final reason = !enabled
      ? (set.lockedReason ?? set.note)
      : (unavailable ?? set.note);
  if (reason == null) return null;
  return WpDockMenuInfo(
    id: 'dock-menu-${set.menuId}-note',
    icon: enabled && unavailable == null ? LucideIcons.info : LucideIcons.lock,
    label: reason,
  );
}

WpDockMenuAction _dockChoiceOption(
  WpDockChoiceSet set,
  WpDockChoice choice, {
  required bool enabled,
}) {
  final choiceReason = choice.unavailableReason;
  final pickable = enabled && choiceReason == null;
  return WpDockMenuAction(
    id: 'dock-menu-${set.menuId}-${choice.value}',
    icon: set.icon,
    label: choice.label,
    checked: choice.value == set.current,
    onTap: pickable ? () => set.onChanged(choice.value) : null,
    tooltip: choiceReason ?? (enabled ? null : set.lockedReason),
    searchText: '${choice.label} ${choice.value}',
  );
}

/// The choice rows: the favourites block first when there are favourites,
/// then the full list grouped by [WpDockChoice.group].
List<WpDockMenuSpec> _dockChoiceOptions(
  WpDockChoiceSet set, {
  required bool enabled,
}) {
  WpDockMenuAction optionFor(WpDockChoice choice) =>
      _dockChoiceOption(set, choice, enabled: enabled);

  final options = <WpDockMenuSpec>[];
  final favoritesLabel = set.favoritesLabel;
  final starred = <WpDockChoice>[
    for (final value in set.favoriteValues)
      for (final choice in set.choices)
        if (choice.value == value) choice,
  ];
  final withFavorites = favoritesLabel != null && starred.isNotEmpty;
  if (withFavorites) {
    options.add(WpDockMenuHeader(favoritesLabel));
    for (final choice in starred) {
      options.add(optionFor(choice));
    }
    final allLabel = set.allLabel;
    if (allLabel != null) options.add(WpDockMenuHeader(allLabel));
  }
  final starredValues = {for (final choice in starred) choice.value};
  String? group;
  for (final choice in set.choices) {
    if (withFavorites && starredValues.contains(choice.value)) continue;
    if (choice.group != group) {
      group = choice.group;
      if (group != null) options.add(WpDockMenuHeader(group));
    }
    options.add(optionFor(choice));
  }
  return options;
}

/// A Mehr submenu: the row toggles its children in place.
class _WpDockMenuSubmenuRow extends StatefulWidget {
  const _WpDockMenuSubmenuRow({required this.item, required this.children});

  final WpDockMenuSubmenu item;
  final List<Widget> children;

  @override
  State<_WpDockMenuSubmenuRow> createState() => _WpDockMenuSubmenuRowState();
}

class _WpDockMenuSubmenuRowState extends State<_WpDockMenuSubmenuRow> {
  final FocusNode _focusNode = FocusNode();
  bool _open = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final header = Semantics(
      identifier: item.id,
      button: true,
      expanded: _open,
      child: WpFocusRing(
        focusNode: _focusNode,
        radius: WpRadius.sm,
        ringColor: _dock.accent,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            focusNode: _focusNode,
            onTap: () => setState(() => _open = !_open),
            hoverColor: _dock.controlHover,
            highlightColor: _dock.pressed,
            borderRadius: WpRadius.borderSm,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.md,
                vertical: WpSpacing.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: WpIconSize.sm,
                    color: _dock.textPrimary,
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Flexible(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        color: _dock.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.sm),
                  Icon(
                    _open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                    size: WpIconSize.sm,
                    color: _dock.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Padding(
      key: ValueKey(item.id),
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_open)
            Padding(
              padding: const EdgeInsets.only(left: WpSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
        ],
      ),
    );
  }
}
