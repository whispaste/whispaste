// Onboarding v6: the one selection pattern of the onboarding. A row shows a
// label, the current value and a chevron; a click opens a list anchored to the
// row (below it, above it when the window has no room). Screen 1 uses it for
// the dictation language, the speech model and the app language, so all three
// behave and look the same.
//
// Picking saves at once and closes the list. Escape, a click outside or the
// row again close it without a change. Arrow keys move through the list, Enter
// picks; a list with a search field filters while typing.

import '../../core/theme/floating_surface.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_search_field.dart';

/// Space between the row and its list.
const double _kListGap = 6;

/// Highest the list grows before it scrolls.
const double _kListMaxHeight = 360;

/// The list is never narrower than this, even under a narrow row.
const double _kListMinWidth = 400;

/// Distance the list keeps from the window edge.
const double _kWindowMargin = WpSpacing.md;

/// One entry of an [OnboardingSelect].
@immutable
class OnboardingSelectOption<T> {
  const OnboardingSelectOption({
    required this.value,
    required this.id,
    required this.title,
    this.subtitle,
    this.badge,
    this.enabled = true,
    this.searchTerms = const [],
  });

  final T value;

  /// Stable, language-independent part of the entry's test id.
  final String id;
  final String title;
  final String? subtitle;

  /// A neutral marker such as "Empfohlen". Selection is the check, never this.
  final String? badge;
  final bool enabled;

  /// Extra words the search matches besides [title] and [subtitle], such as
  /// a language code or its native name.
  final List<String> searchTerms;
}

/// A line of text: the label, the current value and a chevron, with an
/// optional quiet line under it. A click opens the list of choices.
class OnboardingSelect<T> extends StatefulWidget {
  const OnboardingSelect({
    super.key,
    required this.testId,
    required this.label,
    required this.valueText,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.detail,
    this.searchHint,
    this.noResultsText,
  });

  final String testId;
  final String label;
  final String valueText;

  /// A quiet line under the value, e.g. "Sehr schnell · 25 europäische
  /// Sprachen".
  final String? detail;
  final List<OnboardingSelectOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  /// Shows a search field on top of the list when set.
  final String? searchHint;
  final String? noResultsText;

  @override
  State<OnboardingSelect<T>> createState() => _OnboardingSelectState<T>();
}

class _OnboardingSelectState<T> extends State<OnboardingSelect<T>> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _triggerFocus = FocusNode();
  bool _hover = false;
  bool _focused = false;

  bool get _open => _portal.isShowing;

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      HapticFeedback.selectionClick();
      setState(_portal.show);
    }
  }

  /// Closes the list. Only a keyboard close hands the focus back to the line
  /// (and shows its ring); a mouse close leaves nothing focused.
  void _close({bool byKeyboard = false}) {
    if (!_open) return;
    setState(_portal.hide);
    if (byKeyboard) {
      _triggerFocus.requestFocus();
    } else {
      _triggerFocus.unfocus();
    }
  }

  void _pick(T value, {bool byKeyboard = false}) {
    _close(byKeyboard: byKeyboard);
    if (value != widget.selected) widget.onSelected(value);
  }

  @override
  Widget build(BuildContext context) {
    final active = _hover || _focused || _open;
    final body = TextStyle(
      fontSize: WpTypography.body,
      height: 1.45,
      color: WpColors.textSecondary,
    );
    // Text, not a control: the value reads as part of the sentence, the cyan
    // chevron says it can be changed. Hover underlines the value.
    final line = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${widget.label}: '),
          TextSpan(
            text: widget.valueText,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: WpColors.textPrimary,
              decoration: active ? TextDecoration.underline : null,
              decorationColor: WpColors.accent,
            ),
          ),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: WpSpacing.xxs),
              child: AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: WpMotion.fast,
                child: Icon(
                  LucideIcons.chevronDown,
                  size: WpIconSize.sm,
                  color: WpColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
      style: body,
    );

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _OnboardingSelectList<T>(
          link: _link,
          anchorContext: this.context,
          testId: widget.testId,
          options: widget.options,
          selected: widget.selected,
          searchHint: widget.searchHint,
          noResultsText: widget.noResultsText,
          onPick: _pick,
          onDismiss: _close,
        ),
        child: Semantics(
          identifier: widget.testId,
          button: true,
          expanded: _open,
          label: widget.label,
          value: widget.detail == null
              ? widget.valueText
              : '${widget.valueText}, ${widget.detail}',
          excludeSemantics: true,
          child: FocusableActionDetector(
            focusNode: _triggerFocus,
            mouseCursor: SystemMouseCursors.click,
            onShowHoverHighlight: (v) => setState(() => _hover = v),
            onShowFocusHighlight: (v) => setState(() => _focused = v),
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) => _toggle(),
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
                foregroundDecoration: _focused
                    ? BoxDecoration(
                        border: Border.all(color: WpColors.accent, width: 2),
                        borderRadius: WpRadius.borderSm,
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    line,
                    if (widget.detail != null)
                      Text(
                        widget.detail!,
                        style: body.copyWith(
                          fontSize: WpTypography.small,
                          color: WpColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingSelectList<T> extends StatefulWidget {
  const _OnboardingSelectList({
    required this.link,
    required this.anchorContext,
    required this.testId,
    required this.options,
    required this.selected,
    required this.searchHint,
    required this.noResultsText,
    required this.onPick,
    required this.onDismiss,
  });

  final LayerLink link;
  final BuildContext anchorContext;
  final String testId;
  final List<OnboardingSelectOption<T>> options;
  final T selected;
  final String? searchHint;
  final String? noResultsText;
  final void Function(T value, {bool byKeyboard}) onPick;
  final void Function({bool byKeyboard}) onDismiss;

  @override
  State<_OnboardingSelectList<T>> createState() =>
      _OnboardingSelectListState<T>();
}

class _OnboardingSelectListState<T> extends State<_OnboardingSelectList<T>> {
  final _search = TextEditingController();
  final _listFocus = FocusNode();
  final _keys = <int, GlobalKey>{};
  String _query = '';
  int _highlight = -1;

  @override
  void initState() {
    super.initState();
    _highlight = _visible.indexWhere((o) => o.value == widget.selected);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.searchHint == null) _listFocus.requestFocus();
      _reveal(alignment: 0.4);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _listFocus.dispose();
    super.dispose();
  }

  List<OnboardingSelectOption<T>> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if ([
          o.title,
          o.subtitle ?? '',
          ...o.searchTerms,
        ].any((s) => s.toLowerCase().contains(q)))
          o,
    ];
  }

  void _reveal({double alignment = 0.5}) {
    final ctx = _keys[_highlight]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: alignment,
      duration: WpMotion.fast,
    );
  }

  void _move(int delta) {
    final visible = _visible;
    if (visible.isEmpty) return;
    var next = _highlight;
    for (var i = 0; i < visible.length; i++) {
      next = (next + delta) % visible.length;
      if (next < 0) next += visible.length;
      if (visible[next].enabled) break;
    }
    setState(() => _highlight = next);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss(byKeyboard: true);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final visible = _visible;
      if (_highlight >= 0 && _highlight < visible.length) {
        final o = visible[_highlight];
        if (o.enabled) widget.onPick(o.value, byKeyboard: true);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Where the row sits decides whether the list opens below or above it.
    final anchor = widget.anchorContext.findRenderObject() as RenderBox?;
    final window = MediaQuery.sizeOf(context);
    final origin = anchor?.localToGlobal(Offset.zero) ?? Offset.zero;
    final anchorSize = anchor?.size ?? Size.zero;
    final below =
        window.height - origin.dy - anchorSize.height - _kWindowMargin;
    final above = origin.dy - _kWindowMargin;
    final openBelow = below >= math.min(_kListMaxHeight, 240) || below >= above;
    final room = (openBelow ? below : above) - _kListGap;
    final maxHeight = math.max(120.0, math.min(_kListMaxHeight, room));
    final width = math.min(
      math.max(anchorSize.width, _kListMinWidth),
      window.width - origin.dx - _kWindowMargin,
    );

    final visible = _visible;
    final list = ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      itemCount: visible.isEmpty ? 1 : visible.length,
      itemBuilder: (context, i) {
        if (visible.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(WpSpacing.md),
            child: Text(
              widget.noResultsText ?? '',
              style: TextStyle(
                fontSize: WpTypography.body,
                color: WpColors.textMuted,
              ),
            ),
          );
        }
        final o = visible[i];
        return Semantics(
          identifier: '${widget.testId}-option-${o.id}',
          label: o.title,
          hint: o.subtitle,
          button: true,
          selected: o.value == widget.selected,
          enabled: o.enabled,
          child: _OptionRow<T>(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            option: o,
            selected: o.value == widget.selected,
            highlighted: i == _highlight,
            onHover: () {
              if (_highlight != i) setState(() => _highlight = i);
            },
            onTap: () => widget.onPick(o.value),
          ),
        );
      },
    );

    final panel = Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: WpFloatingSurface.decoration,
        child: ClipRRect(
          borderRadius: WpFloatingSurface.radius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.searchHint != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    WpSpacing.xs,
                    WpSpacing.xs,
                    WpSpacing.xs,
                    WpSpacing.xxs,
                  ),
                  child: WpSearchField(
                    testId: '${widget.testId}-search',
                    controller: _search,
                    variant: WpSearchFieldVariant.outlined,
                    hintText: widget.searchHint!,
                    autofocus: true,
                    onChanged: (q) => setState(() {
                      _query = q;
                      _keys.clear();
                      final v = _visible;
                      _highlight = v.indexWhere((o) => o.enabled);
                    }),
                  ),
                ),
              Flexible(child: list),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onDismiss(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          targetAnchor: openBelow
              ? AlignmentDirectional.bottomStart.resolve(
                  Directionality.of(context),
                )
              : AlignmentDirectional.topStart.resolve(
                  Directionality.of(context),
                ),
          followerAnchor: openBelow
              ? AlignmentDirectional.topStart.resolve(
                  Directionality.of(context),
                )
              : AlignmentDirectional.bottomStart.resolve(
                  Directionality.of(context),
                ),
          offset: Offset(0, openBelow ? _kListGap : -_kListGap),
          // The Align fills the overlay, so the follower is window-sized: the
          // panel must hug the edge that touches the trigger.
          child: Align(
            alignment: openBelow
                ? AlignmentDirectional.topStart
                : AlignmentDirectional.bottomStart,
            child: Focus(
              focusNode: _listFocus,
              onKeyEvent: _onKey,
              child: Semantics(
                identifier: '${widget.testId}-list',
                explicitChildNodes: true,
                child: panel,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    super.key,
    required this.option,
    required this.selected,
    required this.highlighted,
    required this.onHover,
    required this.onTap,
  });

  final OnboardingSelectOption<T> option;
  final bool selected;
  final bool highlighted;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = option.enabled;
    final titleColor = enabled ? WpColors.textPrimary : WpColors.textMuted;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: enabled ? (_) => onHover() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: highlighted && enabled ? WpColors.accentRowHover : null,
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              SizedBox(
                width: WpIconSize.sm + WpSpacing.xs,
                child: selected
                    ? Icon(
                        LucideIcons.check,
                        size: WpIconSize.sm,
                        color: WpColors.accent,
                      )
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: titleColor,
                      ),
                    ),
                    if (option.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          option.subtitle!,
                          style: TextStyle(
                            fontSize: WpTypography.small,
                            color: WpColors.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (option.badge != null) ...[
                const SizedBox(width: WpSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: WpSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: WpColors.surfaceChipFill,
                    borderRadius: WpRadius.borderSm,
                    border: Border.all(color: WpColors.borderSubtle),
                  ),
                  child: Text(
                    option.badge!,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: WpColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
