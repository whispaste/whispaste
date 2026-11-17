/// The find-and-replace bar that drops out of [WpMarkdownToolbar].
///
/// One bar, three surfaces: History's transcript editor, the Notes editor and
/// the Snippet dialog all get it because all three host the toolbar. It edits
/// the [TextEditingController] it is handed and owns nothing else — no
/// provider, no persistence, no knowledge of which feature it is sitting in.
///
/// Not to be confused with the app's *list* search (`WpSearchField`, the
/// History search bar): that one filters a list and never rewrites anything.
/// The `findReplace*` ARB keys say "find in text" rather than "search" for
/// exactly that reason.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../core/text/text_undo.dart';
import 'find_replace.dart';
import 'find_throttle.dart';
import 'wp_icon_button.dart';
import 'wp_text_field.dart';

/// Find and replace within a single text field.
///
/// Keyboard, which is how anyone actually uses this: `Enter` steps to the next
/// hit, `Shift+Enter` to the previous one, `Escape` closes the bar. All three
/// are bound on the fields' own [FocusNode]s (`onKeyEvent`), which fire before
/// the ancestor shortcut handlers the panels install — History binds `Escape`
/// at panel level to *save the transcript*, and that must not be what closing
/// a find bar does.
class WpFindReplaceBar extends StatefulWidget {
  const WpFindReplaceBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.testIdPrefix = 'editor',
  });

  /// The `<screen>` half of the bar's identifiers (`notes-editor-find-next`).
  final String testIdPrefix;

  /// The field being searched. Pass a [WpFindHighlightController] to get the
  /// hits tinted; a plain controller works too, minus the tint.
  ///
  /// Note there is no editor [FocusNode] here: the bar never takes focus away
  /// from itself. Handing the caret back to the body is the *host's* job, on
  /// close — see [WpMarkdownToolbar].
  final TextEditingController controller;

  final VoidCallback onClose;

  @override
  State<WpFindReplaceBar> createState() => _WpFindReplaceBarState();
}

class _WpFindReplaceBarState extends State<WpFindReplaceBar> {
  late final TextEditingController _findCtrl;
  late final TextEditingController _replaceCtrl;
  late final FocusNode _findFocus;
  late final FocusNode _replaceFocus;

  WpFindMatches _matches = WpFindMatches.none;
  int _active = -1;
  final WpFindThrottle _throttle = WpFindThrottle();
  String? _lastText;
  String? _lastQuery;

  @override
  void initState() {
    super.initState();
    _findCtrl = TextEditingController();
    _replaceCtrl = TextEditingController();
    _findFocus = FocusNode(
      debugLabel: 'findReplace.find',
      onKeyEvent: (_, event) => _handleKey(event, onEnter: _next),
    );
    _replaceFocus = FocusNode(
      debugLabel: 'findReplace.replace',
      onKeyEvent: (_, event) => _handleKey(event, onEnter: _replaceCurrent),
    );
    // The body can be edited while the bar is open, so the match list is
    // derived from the controller rather than snapshotted on open.
    widget.controller.addListener(_onEditedTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEditedTextChanged);
    _throttle.dispose();
    _clearHighlight();
    _findCtrl.dispose();
    _replaceCtrl.dispose();
    _findFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  // ── Highlight plumbing ────────────────────────────────────────────────

  WpFindHighlightController? get _highlightable {
    final controller = widget.controller;
    return controller is WpFindHighlightController ? controller : null;
  }

  void _pushHighlight() => _highlightable?.setFindHighlight(_matches, _active);

  /// Silent by necessity — see [WpFindHighlightController.clearFindHighlight].
  /// The visible clear happens in the host's close handler, before the bar
  /// leaves the tree.
  void _clearHighlight() => _highlightable?.clearFindHighlight(notify: false);

  // ── Match bookkeeping ─────────────────────────────────────────────────

  /// Re-locates the query and settles on a match index.
  ///
  /// [preferred] is where the caller would like to land (the same slot after a
  /// replace, the first hit after a fresh query); it is clamped into whatever
  /// the new match list actually offers.
  ///
  /// Always rebuilds — the counter and the enabled/disabled state of five
  /// buttons hang off this, and "nothing found either time" is a state change
  /// the row still has to render.
  void _recompute({int? preferred}) {
    final text = widget.controller.text;
    final query = _findCtrl.text;
    // The controller also notifies for caret moves and for this bar's own
    // highlight push; only a changed text or query needs a new search (#640).
    if (preferred == null && text == _lastText && query == _lastQuery) return;
    _lastText = text;
    _lastQuery = query;
    _throttle.run(text, query, (matches) {
      final active = WpFindReplace.clampIndex(
        preferred ?? _active,
        matches.count,
      );
      void assign() {
        _matches = matches;
        _active = active;
      }

      if (mounted) {
        setState(assign);
      } else {
        assign();
      }
      _pushHighlight();
    });
  }

  void _onEditedTextChanged() => _recompute();

  void _onQueryChanged(String _) => _recompute(preferred: 0);

  // ── Navigation ────────────────────────────────────────────────────────

  void _next() {
    if (_matches.isEmpty) return;
    _setActive((_active + 1) % _matches.count);
  }

  void _previous() {
    if (_matches.isEmpty) return;
    _setActive((_active - 1 + _matches.count) % _matches.count);
  }

  void _setActive(int index) {
    setState(() => _active = index);
    _pushHighlight();
    // Park the caret on the hit as well: focus stays here so the tint is what
    // the user sees, but the moment they click back into the body the cursor
    // is already at the match they navigated to.
    widget.controller.selection = TextSelection(
      baseOffset: _matches.starts[index],
      extentOffset: _matches.endOf(index),
    );
  }

  // ── Replacing ─────────────────────────────────────────────────────────

  void _replaceCurrent() {
    if (_matches.isEmpty || _active < 0) return;
    final replacement = _replaceCtrl.text;
    final start = _matches.starts[_active];
    final text = WpFindReplace.replaceOne(
      widget.controller.text,
      _matches,
      _active,
      replacement,
    );
    final landedAt = _active;
    _apply(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      ),
    );
    // One hit fewer, so the same index now points at what used to be the next
    // one — pressing "replace" repeatedly walks forward without re-selecting.
    _recompute(preferred: landedAt);
  }

  void _replaceAll() {
    if (_matches.isEmpty) return;
    final text = WpFindReplace.replaceAll(
      widget.controller.text,
      _matches,
      _replaceCtrl.text,
    );
    _apply(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
    _recompute(preferred: 0);
  }

  /// Each replace, and a whole replace-all, is one undo step (#651).
  void _apply(TextEditingValue value) => TextUndoController.command(
    widget.controller,
    () => widget.controller.value = value,
  );

  // ── Keyboard ──────────────────────────────────────────────────────────

  KeyEventResult _handleKey(KeyEvent event, {required VoidCallback onEnter}) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        _previous();
      } else {
        onEnter();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final hasQuery = _findCtrl.text.isNotEmpty;
    final hasMatches = _matches.isNotEmpty;
    final id = '${widget.testIdPrefix}-find';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: WpColors.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: WpRadius.borderSm,
        border: Border.all(color: WpColors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Find row ──
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: '$id-input',
                  child: WpTextField(
                    controller: _findCtrl,
                    focusNode: _findFocus,
                    variant: WpTextFieldVariant.form,
                    maxLines: 1,
                    autofocus: true,
                    autocorrect: false,
                    hintText: l10n.findReplaceFindHint,
                    semanticsLabel: l10n.findReplaceFindLabel,
                    onChanged: _onQueryChanged,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              _MatchCounter(
                total: _matches.count,
                active: _active,
                hasQuery: hasQuery,
                testId: '$id-count',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.chevronUp,
                tooltip: l10n.findReplacePrevious,
                onPressed: hasMatches ? _previous : null,
                testId: '$id-previous',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.chevronDown,
                tooltip: l10n.findReplaceNext,
                onPressed: hasMatches ? _next : null,
                testId: '$id-next',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.x,
                tooltip: l10n.findReplaceClose,
                onPressed: widget.onClose,
                testId: '$id-close',
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.xs),
          // ── Replace row ──
          Row(
            children: [
              Expanded(
                child: Semantics(
                  identifier: '${widget.testIdPrefix}-replace-input',
                  child: WpTextField(
                    controller: _replaceCtrl,
                    focusNode: _replaceFocus,
                    variant: WpTextFieldVariant.form,
                    maxLines: 1,
                    autocorrect: false,
                    hintText: l10n.findReplaceReplaceHint,
                    semanticsLabel: l10n.findReplaceReplaceLabel,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.replace,
                tooltip: l10n.findReplaceReplaceAction,
                onPressed: hasMatches ? _replaceCurrent : null,
                testId: '${widget.testIdPrefix}-replace-one',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.replaceAll,
                tooltip: l10n.findReplaceReplaceAllAction,
                onPressed: hasMatches ? _replaceAll : null,
                testId: '${widget.testIdPrefix}-replace-all',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "3 / 12", or "No matches" once a query has been typed and found nothing.
///
/// [Flexible] with an ellipsis rather than a fixed width: at an accessibility
/// text size the localized "no matches" string is several times wider than the
/// counter it replaces, and the row it sits in is only 280 dp at the narrow
/// end of the detail panel.
class _MatchCounter extends StatelessWidget {
  const _MatchCounter({
    required this.total,
    required this.active,
    required this.hasQuery,
    required this.testId,
  });

  final int total;
  final int active;
  final bool hasQuery;
  final String testId;

  @override
  Widget build(BuildContext context) {
    if (!hasQuery) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final label = total == 0
        ? l10n.findReplaceNoMatches
        : l10n.findReplaceMatchCount(active + 1, total);

    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
        child: Semantics(
          liveRegion: true,
          identifier: testId,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
