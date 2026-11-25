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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/config/command_shortcut.dart';
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
///
/// The keys of #647 work in the bar and in the text alike ([WpTextEditor]
/// binds them there): [openActivator] opens the bar with the selection as the
/// query (pressed again while open it takes the new selection, or selects
/// the query), [nextActivator] and [previousActivator] step through the hits,
/// and "replace all" names how many it replaced, on screen and read out.
class WpFindReplaceBar extends StatefulWidget {
  const WpFindReplaceBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.testIdPrefix = 'editor',
    this.initialQuery,
    this.initialAnchor,
    this.revealInitial = false,
    this.onReveal,
  });

  /// Ctrl/Cmd+Shift+F: find in this text (#647). Not Ctrl/Cmd+F, which
  /// focuses the list search of the History and Notes pages and keeps doing
  /// that while a caret sits in the editor; the Shift variant is the key
  /// editors use for "find" in a second scope.
  static SingleActivator get openActivator =>
      commandActivator(LogicalKeyboardKey.keyF, shift: true);

  /// F3 on every platform (#647): Ctrl/Cmd+G is the note's "Go to
  /// paragraph", Ctrl/Cmd+Shift+G the outline (#645). Enter in the find
  /// field steps as well, for keyboards where F3 needs Fn.
  static const SingleActivator nextActivator = SingleActivator(
    LogicalKeyboardKey.f3,
  );

  /// Shift+F3, the mirror of [nextActivator] (Shift+Enter in the field).
  static const SingleActivator previousActivator = SingleActivator(
    LogicalKeyboardKey.f3,
    shift: true,
  );

  /// How [openActivator] is spelled for the user.
  static String openShortcutLabel(L10n l10n) =>
      commandShortcutLabel('F', shift: true, l10n: l10n);

  /// How [nextActivator] is spelled for the user.
  static const String nextShortcutLabel = 'F3';

  /// How [previousActivator] is spelled: `⇧F3` on macOS, `Shift+F3`
  /// (localized) elsewhere.
  static String previousShortcutLabel(L10n l10n) =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? '⇧F3'
      : '${l10n.modifierShift}+F3';

  /// Longest selection taken over as the query: past that it is a passage
  /// being worked on, not a word being looked for.
  static const int maxSeedLength = 200;

  /// The selection of [controller] as a query, trimmed (a word selected with
  /// its spaces is looked for as the word), or null when there is none worth
  /// taking: collapsed, blank, spanning lines or very long (#647).
  static String? seedFrom(TextEditingController controller) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return null;
    final text = controller.text;
    if (selection.end > text.length) return null;
    final picked = selection.textInside(text);
    if (picked.trim().isEmpty ||
        picked.length > maxSeedLength ||
        picked.contains('\n')) {
      return null;
    }
    return picked.trim();
  }

  /// Query the bar opens with (the selection, #647); null opens it empty.
  final String? initialQuery;

  /// Offset from which the first hit of [initialQuery] is chosen: where the
  /// selection it came from starts, so the bar opens on that very hit.
  final int? initialAnchor;

  /// Opened for a search hit (#653): the caret stays in the text instead of
  /// moving into the find field, and the first hit is selected there and
  /// handed to [onReveal], which brings it into view.
  final bool revealInitial;

  /// Called with the selected hit after a reveal ([revealInitial], [reveal]).
  final ValueChanged<TextSelection>? onReveal;

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
  State<WpFindReplaceBar> createState() => WpFindReplaceBarState();
}

/// The find keys of one editor (#647): [WpTextEditor] owns the object and
/// binds the keys in its text, the toolbar that shows the bar answers them.
/// The toolbar is remounted per note, so it attaches itself on mount and
/// detaches on dispose instead of the editor holding on to its state.
class WpFindCommands {
  VoidCallback? _open;
  VoidCallback? _next;
  VoidCallback? _previous;
  void Function(String query, int? anchor)? _reveal;
  Object? _owner;

  /// Called by the toolbar on mount; [owner] guards [detach] against a
  /// newer toolbar that attached in the meantime.
  void attach(
    Object owner, {
    required VoidCallback open,
    required VoidCallback next,
    required VoidCallback previous,
    void Function(String query, int? anchor)? reveal,
  }) {
    _owner = owner;
    _open = open;
    _next = next;
    _previous = previous;
    _reveal = reveal;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _open = null;
    _next = null;
    _previous = null;
    _reveal = null;
  }

  /// Opens the bar, the selection becoming the query.
  void open() => _open?.call();

  /// The next hit; opens the bar first when it is closed.
  void next() => _next?.call();

  /// The previous hit; opens the bar first when it is closed.
  void previous() => _previous?.call();

  /// Opens the bar on a search hit (#653): [query] tinted everywhere, the
  /// hit at or after [anchor] selected in the text, the caret left there.
  /// False when no bar is there to answer.
  bool reveal(String query, {int? anchor}) {
    final reveal = _reveal;
    if (reveal == null) return false;
    reveal(query, anchor);
    return true;
  }
}

/// Public so the toolbar that owns the bar can forward the editor's keys to
/// it ([seed], [next], [previous]).
class WpFindReplaceBarState extends State<WpFindReplaceBar> {
  late final TextEditingController _findCtrl;
  late final TextEditingController _replaceCtrl;
  late final FocusNode _findFocus;
  late final FocusNode _replaceFocus;

  WpFindMatches _matches = WpFindMatches.none;
  int _active = -1;

  /// Set by a reveal (#653) until the search it started has answered.
  bool _revealPending = false;
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
      onKeyEvent: (_, event) => _handleKey(event, onEnter: next),
    );
    _replaceFocus = FocusNode(
      debugLabel: 'findReplace.replace',
      onKeyEvent: (_, event) => _handleKey(event, onEnter: _replaceCurrent),
    );
    // The body can be edited while the bar is open, so the match list is
    // derived from the controller rather than snapshotted on open.
    widget.controller.addListener(_onEditedTextChanged);
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _findCtrl.value = TextEditingValue(
        text: initial,
        selection: TextSelection(baseOffset: 0, extentOffset: initial.length),
      );
    }
    // Opening the bar puts the caret into the find field. `autofocus` alone
    // does not: it only acts while nothing in the scope has focus, and the
    // toggle button (keyboard) or the text (mouse) always has it, so typed
    // letters went nowhere or into the text (#1372, VoiceOver run).
    // A reveal keeps the caret in the text: the hit is selected there, and
    // F3 / Shift+F3 step on from it.
    _revealPending = widget.revealInitial;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.revealInitial) _findFocus.requestFocus();
      // After the first frame: the search tints the text and reads the
      // count out, neither of which may happen while the tree is built.
      if (_findCtrl.text.isNotEmpty) {
        _recompute(preferred: 0, anchor: widget.initialAnchor);
      }
    });
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
  /// [anchor] instead picks the first hit starting at or after that offset.
  void _recompute({int? preferred, int? anchor}) {
    final text = widget.controller.text;
    final query = _findCtrl.text;
    // The controller also notifies for caret moves and for this bar's own
    // highlight push; only a changed text or query needs a new search (#640).
    if (preferred == null && text == _lastText && query == _lastQuery) return;
    _lastText = text;
    _lastQuery = query;
    _throttle.run(text, query, (matches) {
      final active = WpFindReplace.clampIndex(
        anchor != null
            ? _firstAtOrAfter(matches, anchor)
            : (preferred ?? _active),
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
      _announceCount();
      if (_revealPending) {
        _revealPending = false;
        _selectActive(reveal: true);
      }
    });
  }

  /// The hit starting at or after [offset]; the first one when none does.
  static int _firstAtOrAfter(WpFindMatches matches, int offset) {
    for (var i = 0; i < matches.count; i++) {
      if (matches.starts[i] >= offset) return i;
    }
    return 0;
  }

  void _onEditedTextChanged() {
    // An edit after a replace-all (typing, undo) ends its notice: the
    // counter goes back to counting hits.
    if (_replaced != null && widget.controller.text != _replacedText) {
      _replaced = null;
    }
    _recompute();
  }

  void _onQueryChanged(String _) {
    _replaced = null;
    _recompute(preferred: 0);
  }

  /// The editor's find key while the bar is already open (#647): a usable
  /// selection becomes the new query, starting on its hit at [anchor];
  /// without one the current query is selected, ready to be typed over.
  /// Either way the caret goes into the find field.
  void seed(String? query, {int? anchor}) {
    if (query != null && query.isNotEmpty) {
      _replaced = null;
      _findCtrl.value = TextEditingValue(
        text: query,
        selection: TextSelection(baseOffset: 0, extentOffset: query.length),
      );
      _recompute(preferred: 0, anchor: anchor);
    } else {
      _findCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findCtrl.text.length,
      );
    }
    _findFocus.requestFocus();
  }

  /// A search hit opened in the open bar's text (#653): [query] becomes the
  /// query, the hit at or after [anchor] is selected in the text and handed
  /// to [WpFindReplaceBar.onReveal]; the focus is left where it is.
  void reveal(String query, {int? anchor}) {
    if (query.isEmpty) return;
    _replaced = null;
    _revealPending = true;
    _findCtrl.value = TextEditingValue(
      text: query,
      selection: TextSelection(baseOffset: 0, extentOffset: query.length),
    );
    _recompute(preferred: 0, anchor: anchor);
  }

  // ── Navigation ────────────────────────────────────────────────────────

  /// The next hit, wrapping at the end: F3, Enter in the find field.
  void next() {
    if (_matches.isEmpty) return;
    _replaced = null;
    _setActive((_active + 1) % _matches.count);
  }

  /// The previous hit, wrapping at the start: Shift+F3, Shift+Enter.
  void previous() {
    if (_matches.isEmpty) return;
    _replaced = null;
    _setActive((_active - 1 + _matches.count) % _matches.count);
  }

  void _setActive(int index) {
    setState(() => _active = index);
    _pushHighlight();
    _announceCount();
    // Stepped from the text (F3 after a reveal, #653): the text has the
    // focus, so the hit is brought into view there as well.
    _selectActive(reveal: !_focusInBar);
  }

  /// Whether the focus sits anywhere in this bar: a field or a button.
  bool get _focusInBar {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    if (identical(focused, context)) return true;
    var inside = false;
    focused.visitAncestorElements((element) {
      if (identical(element, context)) {
        inside = true;
        return false;
      }
      return true;
    });
    return inside;
  }

  /// Parks the caret on the active hit: with the focus in this bar the tint
  /// is what the user sees, but the moment they click back into the body
  /// the cursor is already at the match they navigated to. A [reveal] hands
  /// the hit on to be brought into view.
  void _selectActive({bool reveal = false}) {
    if (_active < 0 || _active >= _matches.count) return;
    final selection = TextSelection(
      baseOffset: _matches.starts[_active],
      extentOffset: _matches.endOf(_active),
    );
    widget.controller.selection = selection;
    if (reveal) widget.onReveal?.call(selection);
  }

  /// The counter text last read out, so an unchanged count stays silent.
  String? _announced;

  /// Reads the counter out when it changes ("2 of 5", "No matches").
  ///
  /// An explicit announcement, not a live region: VoiceOver read none of the
  /// counter's changes as a live region (#1372), the same as in #668.
  void _announceCount() {
    if (!mounted) return;
    final text = _MatchCounter.labelFor(
      L10n.of(context),
      total: _matches.count,
      active: _active,
      hasQuery: _findCtrl.text.isNotEmpty,
      replaced: _replaced,
    );
    if (text == null || text == _announced) {
      _announced = text;
      return;
    }
    _announced = text;
    announce(View.of(context), text, Directionality.of(context));
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

  /// How many hits the last replace-all swapped: the counter shows and reads
  /// it until the query, the hit or the text changes (#647).
  int? _replaced;

  /// The text right after that replace-all.
  String? _replacedText;

  void _replaceAll() {
    if (_matches.isEmpty) return;
    final text = WpFindReplace.replaceAll(
      widget.controller.text,
      _matches,
      _replaceCtrl.text,
    );
    if (text == widget.controller.text) return;
    _replaced = _matches.count;
    _replacedText = text;
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
    final keyboard = HardwareKeyboard.instance;
    // The editor's keys answer here too, so stepping does not depend on
    // where the caret is (#647).
    if (WpFindReplaceBar.previousActivator.accepts(event, keyboard)) {
      previous();
      return KeyEventResult.handled;
    }
    if (WpFindReplaceBar.nextActivator.accepts(event, keyboard)) {
      next();
      return KeyEventResult.handled;
    }
    if (WpFindReplaceBar.openActivator.accepts(event, keyboard)) {
      seed(null);
      return KeyEventResult.handled;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        previous();
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
                child: WpTextField(
                  testId: '$id-input',
                  controller: _findCtrl,
                  focusNode: _findFocus,
                  variant: WpTextFieldVariant.form,
                  maxLines: 1,
                  autocorrect: false,
                  hintText: l10n.findReplaceFindHint,
                  semanticsLabel: l10n.findReplaceFindLabel,
                  onChanged: _onQueryChanged,
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              _MatchCounter(
                total: _matches.count,
                active: _active,
                hasQuery: hasQuery,
                replaced: _replaced,
                testId: '$id-count',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.chevronUp,
                tooltip: l10n.findReplacePrevious(
                  WpFindReplaceBar.previousShortcutLabel(l10n),
                ),
                onPressed: hasMatches ? previous : null,
                testId: '$id-previous',
              ),
              WpIconButton.ghost(
                compact: true,
                icon: LucideIcons.chevronDown,
                tooltip: l10n.findReplaceNext(
                  WpFindReplaceBar.nextShortcutLabel,
                ),
                onPressed: hasMatches ? next : null,
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
                child: WpTextField(
                  testId: '${widget.testIdPrefix}-replace-input',
                  controller: _replaceCtrl,
                  focusNode: _replaceFocus,
                  variant: WpTextFieldVariant.form,
                  maxLines: 1,
                  autocorrect: false,
                  hintText: l10n.findReplaceReplaceHint,
                  semanticsLabel: l10n.findReplaceReplaceLabel,
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
    this.replaced,
  });

  final int total;
  final int active;
  final bool hasQuery;
  final String testId;

  /// Hits the last replace-all swapped, while its notice stands.
  final int? replaced;

  /// The counter's text; null while no query is typed. Right after a
  /// replace-all it names how many were replaced instead (#647).
  static String? labelFor(
    L10n l10n, {
    required int total,
    required int active,
    required bool hasQuery,
    int? replaced,
  }) {
    if (replaced != null) return l10n.findReplaceReplacedCount(replaced);
    if (!hasQuery) return null;
    return total == 0
        ? l10n.findReplaceNoMatches
        : l10n.findReplaceMatchCount(active + 1, total);
  }

  @override
  Widget build(BuildContext context) {
    final label = labelFor(
      L10n.of(context),
      total: total,
      active: active,
      hasQuery: hasQuery,
      replaced: replaced,
    );
    if (label == null) return const SizedBox.shrink();

    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
        // Read out by the bar itself (`_announceCount`); here only the text
        // a screen reader finds when it walks the bar.
        child: Semantics(
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
