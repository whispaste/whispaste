/// The outline panel of the editor block (#645): every heading of the open
/// text as a list, indented by level, from which a heading is reached with
/// the keyboard, the mouse or a screen reader.
///
/// The panel only shows and picks; jumping (caret, focus, scrolling) is the
/// host's job ([WpTextEditor]), so the panel works the same over the plain
/// text field and the long-note editor.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsRole;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/text/markdown_outline.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_focus_ring.dart';
import 'wp_icon_button.dart';

/// The outline of the text in [controller], updated [throttle] after the
/// last change while typing goes on (the whole text is read once per pause,
/// never per keystroke).
///
/// Keyboard: the list is one Tab stop (the heading at the caret, or the one
/// chosen last); Up and Down move, Home and End jump to the ends, Enter or
/// Space jumps to the heading, Escape hands the focus back to the text.
///
/// Semantics identifiers: `<testId>-outline` (panel), `<testId>-outline-list`,
/// `<testId>-outline-item-<n>` (n counts from 0 in text order),
/// `<testId>-outline-empty`, `<testId>-outline-close`.
class WpOutlinePanel extends StatefulWidget {
  const WpOutlinePanel({
    super.key,
    required this.testId,
    required this.controller,
    required this.onSelect,
    required this.onClose,
    required this.onLeave,
    this.stepHint,
    this.throttle = defaultThrottle,
  });

  /// The line under the list that names the next/previous heading keys.
  final String? stepHint;

  final String testId;
  final TextEditingController controller;

  /// Jumps to the chosen heading.
  final ValueChanged<OutlineHeading> onSelect;

  /// Closes the panel (its close button).
  final VoidCallback onClose;

  /// Escape in the list: back to the text, the panel stays open.
  final VoidCallback onLeave;

  /// Pause after the last edit before the outline is read again.
  final Duration throttle;

  static const Duration defaultThrottle = Duration(milliseconds: 300);

  /// Highest the list grows at 100 % text size before it scrolls, so the
  /// text below keeps its room in a short window.
  static const double maxListExtent = 200;

  @override
  State<WpOutlinePanel> createState() => WpOutlinePanelState();
}

class WpOutlinePanelState extends State<WpOutlinePanel> {
  List<OutlineHeading> _outline = const [];
  String _readText = '';
  Timer? _pending;
  final List<FocusNode> _nodes = [];
  final ScrollController _scroll = ScrollController();

  /// The heading the caret is in, -1 before the first one.
  int _atCaret = -1;

  /// The list's Tab stop; follows the caret until a row takes focus.
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _read();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(WpOutlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _pending?.cancel();
      _read();
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    widget.controller.removeListener(_onChanged);
    for (final node in _nodes) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _read() {
    _readText = widget.controller.text;
    _outline = markdownOutline(_readText);
    _atCaret = _caretIndex();
  }

  int _caretIndex() {
    final sel = widget.controller.selection;
    if (!sel.isValid) return -1;
    return outlineIndexAt(_outline, sel.extentOffset);
  }

  void _onChanged() {
    final text = widget.controller.text;
    if (text != _readText) {
      // Throttled: typing restarts the pause, the outline follows once the
      // writer stops (#645).
      _pending?.cancel();
      _pending = Timer(widget.throttle, () {
        if (!mounted) return;
        setState(_read);
      });
      return;
    }
    final at = _caretIndex();
    if (at != _atCaret) setState(() => _atCaret = at);
  }

  void _ensureNodes() {
    while (_nodes.length < _outline.length) {
      final index = _nodes.length;
      final node = FocusNode(debugLabel: 'OutlineItem $index');
      node.addListener(() {
        if (node.hasFocus && _current != index && mounted) {
          setState(() => _current = index);
        }
      });
      _nodes.add(node);
    }
    final focusedRow = _nodes.indexWhere((n) => n.hasFocus);
    if (focusedRow == -1 || focusedRow >= _outline.length) {
      // Outside the list the Tab stop is the heading at the caret.
      _current = _atCaret.clamp(0, _outline.isEmpty ? 0 : _outline.length - 1);
    }
    for (var i = 0; i < _nodes.length; i++) {
      // Roving Tab stop, as the toolbar (#652): one stop for the list.
      _nodes[i].skipTraversal = i != _current || i >= _outline.length;
      _nodes[i].canRequestFocus = i < _outline.length;
    }
  }

  /// Moves the keyboard focus into the list, onto the heading at the caret.
  /// Returns false when there is no heading to focus.
  bool focusList() {
    // The text may have changed within the pause: read it now.
    if (widget.controller.text != _readText) {
      _pending?.cancel();
      setState(_read);
    }
    if (_outline.isEmpty) return false;
    final target = _atCaret.clamp(0, _outline.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAt(target);
    });
    setState(() => _current = target);
    return true;
  }

  void _focusAt(int index) {
    if (_outline.isEmpty) return;
    final target = index.clamp(0, _outline.length - 1);
    if (target >= _nodes.length) return;
    setState(() => _current = target);
    final node = _nodes[target]..requestFocus();
    final ctx = node.context;
    if (ctx != null) Scrollable.ensureVisible(ctx);
  }

  int get _focused {
    final i = _nodes.indexWhere((n) => n.hasFocus);
    return i == -1 ? _current : i;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusAt(_focused + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _focusAt(_focused - 1);
    } else if (key == LogicalKeyboardKey.home) {
      _focusAt(0);
    } else if (key == LogicalKeyboardKey.end) {
      _focusAt(_outline.length - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      // Handled here, before the page's own Escape (History saves on it).
      widget.onLeave();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _select(int index) {
    if (index < 0 || index >= _outline.length) return;
    setState(() => _current = index);
    widget.onSelect(_outline[index]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    _ensureNodes();
    final id = '${widget.testId}-outline';
    final minLevel = _outline.isEmpty
        ? 1
        : _outline.map((h) => h.level).reduce((a, b) => a < b ? a : b);
    final scaler = MediaQuery.textScalerOf(context);

    final Widget body;
    if (_outline.isEmpty) {
      body = Semantics(
        container: true,
        identifier: '$id-empty',
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.xs,
            0,
            WpSpacing.xs,
            WpSpacing.xs,
          ),
          child: Text(
            l10n.editorOutlineEmpty,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textMuted,
            ),
          ),
        ),
      );
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: scaler.scale(WpOutlinePanel.maxListExtent),
        ),
        child: Focus(
          skipTraversal: true,
          canRequestFocus: false,
          includeSemantics: false,
          onKeyEvent: _onKey,
          child: SingleChildScrollView(
            controller: _scroll,
            // The list node sits right above its items: a list item must be
            // the direct child of a list in the semantics tree.
            child: Semantics(
              container: true,
              identifier: '$id-list',
              role: SemanticsRole.list,
              label: l10n.editorOutlineTitle,
              explicitChildNodes: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _outline.length; i++)
                    _OutlineRow(
                      key: ValueKey('$id-item-$i'),
                      testId: '$id-item-$i',
                      heading: _outline[i],
                      indent: _outline[i].level - minLevel,
                      atCaret: i == _atCaret,
                      focusNode: _nodes[i],
                      onTap: () => _select(i),
                      label: _outline[i].title.isEmpty
                          ? l10n.editorOutlineUntitled
                          : _outline[i].title,
                      levelLabel: l10n.editorOutlineLevel(_outline[i].level),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      identifier: id,
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.xxs),
        decoration: BoxDecoration(
          color: WpColors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: WpRadius.borderSm,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: WpSpacing.xs,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        l10n.editorOutlineTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          fontWeight: FontWeight.w600,
                          color: WpColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                WpIconButton.ghost(
                  compact: true,
                  icon: LucideIcons.x,
                  tooltip: l10n.editorOutlineClose,
                  onPressed: widget.onClose,
                  testId: '$id-close',
                ),
              ],
            ),
            body,
            if (widget.stepHint case final hint?)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  WpSpacing.xs,
                  WpSpacing.xxs,
                  WpSpacing.xs,
                  WpSpacing.xxs,
                ),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: WpTypography.caption,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One heading of the list: a list item that acts like a button.
class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    super.key,
    required this.testId,
    required this.heading,
    required this.indent,
    required this.atCaret,
    required this.focusNode,
    required this.onTap,
    required this.label,
    required this.levelLabel,
  });

  final String testId;
  final OutlineHeading heading;

  /// Steps of indentation: the level minus the text's highest level.
  final int indent;

  /// The caret stands in this heading's section.
  final bool atCaret;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final String label;
  final String levelLabel;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = WpColors.accent;
    final highlighted = _hovered || widget.atCaret;
    return Semantics(
      role: SemanticsRole.listItem,
      container: true,
      child: MergeSemantics(
        child: Semantics(
          identifier: widget.testId,
          button: true,
          selected: widget.atCaret,
          label: widget.label,
          hint: widget.levelLabel,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: WpFocusRing(
              focusNode: widget.focusNode,
              radius: WpRadius.sm,
              child: InkWell(
                onTap: widget.onTap,
                focusNode: widget.focusNode,
                borderRadius: BorderRadius.circular(WpRadius.sm),
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: WpLayout.minTouchTarget,
                  ),
                  alignment: AlignmentDirectional.centerStart,
                  padding: EdgeInsetsDirectional.only(
                    start: WpSpacing.xs + widget.indent * WpSpacing.md,
                    end: WpSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: highlighted
                        ? accent.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: WpRadius.borderSm,
                  ),
                  // The name is the node's label above; the text must not
                  // add it a second time.
                  child: ExcludeSemantics(
                    child: Text(
                      widget.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: WpTypography.body,
                        fontWeight: widget.heading.level <= 2
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: widget.atCaret ? accent : WpColors.textPrimary,
                        fontStyle: widget.heading.title.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
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
