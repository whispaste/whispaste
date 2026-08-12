import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'find_replace.dart';
import 'find_replace_bar.dart';

/// The markdown formatting actions themselves — the one place that knows how
/// bold, italic, a heading, a list, a quote or code are applied to a
/// [TextEditingController].
///
/// Both halves of the feature go through here: the buttons in
/// [WpMarkdownToolbar] and the keyboard shortcuts on every surface that offers
/// them (History's transcript editor, the Notes editor). The panels used to
/// carry a second, subtly different copy of the same three operations — bold
/// that could wrap but never unwrap, a list toggle that dropped the selection
/// — so the same keystroke and the same button did not do the same thing. One
/// implementation, reached from both, is the point of this class.
@immutable
class WpMarkdownFormatting {
  const WpMarkdownFormatting({
    required this.controller,
    required this.focusNode,
  });

  /// The field being edited, and the node that gets focus back afterwards —
  /// formatting is only ever a detour from typing.
  final TextEditingController controller;
  final FocusNode focusNode;

  // ── The seven actions ────────────────────────────────────────────────────

  void bold() => _wrapSelection('**');
  void italic() => _wrapSelection('_');
  void code() => _wrapSelection('`');
  void heading() => _toggleLinePrefix('## ');
  void bulletList() => _toggleLinePrefix('- ');
  void numberedList() => _toggleLinePrefix('1. ');
  void quote() => _toggleLinePrefix('> ');

  // ── The keyboard half ────────────────────────────────────────────────────

  /// Ctrl+B on Windows/Linux, Cmd+B on macOS — the platform split every other
  /// shortcut in the app already makes.
  static final SingleActivator boldActivator = SingleActivator(
    LogicalKeyboardKey.keyB,
    control: !Platform.isMacOS,
    meta: Platform.isMacOS,
  );

  static final SingleActivator italicActivator = SingleActivator(
    LogicalKeyboardKey.keyI,
    control: !Platform.isMacOS,
    meta: Platform.isMacOS,
  );

  static final SingleActivator bulletListActivator = SingleActivator(
    LogicalKeyboardKey.keyL,
    control: !Platform.isMacOS,
    meta: Platform.isMacOS,
    shift: true,
  );

  /// The bindings to hand a [CallbackShortcuts] above the field.
  ///
  /// [when] gates them on the surface's own notion of "the editor is live":
  /// History passes its edit-mode flag (outside edit mode Ctrl+B must not
  /// rewrite a transcript that is only being read), Notes passes the editor's
  /// focus (the panel also holds a tag input, and formatting the note body
  /// while typing a tag name would come out of nowhere). Omitted, the
  /// shortcuts are always live.
  Map<ShortcutActivator, VoidCallback> shortcutBindings({
    bool Function()? when,
  }) {
    bool enabled() => when?.call() ?? true;
    return <ShortcutActivator, VoidCallback>{
      boldActivator: () {
        if (enabled()) bold();
      },
      italicActivator: () {
        if (enabled()) italic();
      },
      bulletListActivator: () {
        if (enabled()) bulletList();
      },
    };
  }

  /// How a shortcut is spelled in a tooltip, per platform: `⌘B` on macOS,
  /// `Ctrl+B` elsewhere. The modifier stays a symbol rather than a translated
  /// word — it is what the key cap says, and it matches the shortcut help
  /// overlay in History.
  static String get boldShortcutLabel => _shortcutLabel('B');
  static String get italicShortcutLabel => _shortcutLabel('I');
  static String get bulletListShortcutLabel =>
      Platform.isMacOS ? '⇧⌘L' : 'Ctrl+Shift+L';

  static String _shortcutLabel(String key) =>
      Platform.isMacOS ? '⌘$key' : 'Ctrl+$key';

  // ── Implementation ───────────────────────────────────────────────────────

  void _wrapSelection(String prefix, [String? suffix]) {
    suffix ??= prefix;
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    final before = text.substring(0, sel.start);
    final selected = text.substring(sel.start, sel.end);
    final after = text.substring(sel.end);

    // If already wrapped, unwrap
    if (selected.startsWith(prefix) && selected.endsWith(suffix)) {
      final unwrapped = selected.substring(
        prefix.length,
        selected.length - suffix.length,
      );
      controller.value = TextEditingValue(
        text: '$before$unwrapped$after',
        selection: TextSelection(
          baseOffset: sel.start,
          extentOffset: sel.start + unwrapped.length,
        ),
      );
    } else {
      final wrapped = '$prefix$selected$suffix';
      controller.value = TextEditingValue(
        text: '$before$wrapped$after',
        selection: TextSelection(
          baseOffset: sel.start,
          extentOffset: sel.start + wrapped.length,
        ),
      );
    }

    focusNode.requestFocus();
  }

  void _toggleLinePrefix(String prefix) {
    final text = controller.text;
    final sel = controller.selection;

    if (!sel.isValid) return;

    // Find the start of the current line
    final lineStart = text.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0);
    final actualStart = lineStart == -1 ? 0 : lineStart + 1;
    final lineEnd = text.indexOf('\n', sel.end);
    final actualEnd = lineEnd == -1 ? text.length : lineEnd;

    final lines = text.substring(actualStart, actualEnd).split('\n');
    final allPrefixed = lines.every((l) => l.startsWith(prefix));

    final transformed = lines
        .map((l) {
          if (allPrefixed) {
            return l.startsWith(prefix) ? l.substring(prefix.length) : l;
          }
          return l.startsWith(prefix) ? l : '$prefix$l';
        })
        .join('\n');

    final before = text.substring(0, actualStart);
    final after = text.substring(actualEnd);

    final diff = transformed.length - (actualEnd - actualStart);
    controller.value = TextEditingValue(
      text: '$before$transformed$after',
      selection: TextSelection(
        baseOffset: sel.start + (sel.start > actualStart ? diff : 0),
        extentOffset: sel.end + diff,
      ),
    );

    focusNode.requestFocus();
  }
}

/// Markdown formatting toolbar for text editing, plus find-and-replace.
///
/// Every formatting button calls the matching method on
/// [WpMarkdownFormatting], which is also what the keyboard shortcuts call, so
/// the tooltip that promises `Ctrl+B` and the key that answers it can no
/// longer disagree. The button row is horizontally scrollable, because at the
/// 280 dp the detail panels render down to, eight buttons do not fit and the
/// panel must not be the thing that scrolls.
///
/// ## Why find-and-replace lives here
///
/// It is the one widget History's transcript editor, the Notes editor and the
/// Snippet dialog already share, so hanging the bar off it lights the feature
/// up on all three at once and keeps a single copy of the interaction. The bar
/// itself is [WpFindReplaceBar]; this widget only owns whether it is open.
///
/// Deliberately **not** bound to `Ctrl/Cmd+F`: that combination is already the
/// "focus the list search field" shortcut on the History and the Notes page
/// (`history_page.dart`, `notes_page.dart`), and quietly changing what it does
/// while a caret sits in the editor would break a shortcut people already use
/// to filter their list. The toggle button and `Escape`-to-close are the whole
/// keyboard story until that conflict is resolved on purpose.
class WpMarkdownToolbar extends StatefulWidget {
  const WpMarkdownToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<WpMarkdownToolbar> createState() => _WpMarkdownToolbarState();
}

class _WpMarkdownToolbarState extends State<WpMarkdownToolbar> {
  bool _findOpen = false;

  void _toggleFind() {
    if (_findOpen) {
      // Tapping the lit button is a close like any other — same tint teardown,
      // same caret handover.
      _closeFind();
      return;
    }
    setState(() => _findOpen = true);
  }

  void _closeFind() {
    if (!_findOpen) return;
    // Before the bar leaves the tree, not after: the bar's own dispose runs
    // while the framework is locked and can only clear the tint silently, so
    // this is the call that actually repaints the field.
    final controller = widget.controller;
    if (controller is WpFindHighlightController) {
      controller.clearFindHighlight();
    }
    setState(() => _findOpen = false);
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // The button row keeps shrink-wrapping (and left-aligning) exactly as it
    // did; the column around it is what the find bar can stretch across, so
    // its two fields get a bounded width on a panel that is otherwise happy to
    // hand out an unbounded one.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _ButtonRow(
            controller: widget.controller,
            focusNode: widget.focusNode,
            findOpen: _findOpen,
            onToggleFind: _toggleFind,
          ),
        ),
        if (_findOpen) ...[
          const SizedBox(height: WpSpacing.xs),
          WpFindReplaceBar(controller: widget.controller, onClose: _closeFind),
        ],
      ],
    );
  }
}

class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.controller,
    required this.focusNode,
    required this.findOpen,
    required this.onToggleFind,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool findOpen;
  final VoidCallback onToggleFind;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final format = WpMarkdownFormatting(
      controller: controller,
      focusNode: focusNode,
    );
    const mutedColor = WpColors.textMuted;
    const accent = WpColors.accent;
    final divColor = mutedColor.withValues(alpha: 0.2);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xs,
        vertical: WpSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: (WpColors.surfaceVariant).withValues(alpha: 0.6),
        borderRadius: WpRadius.borderSm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.bold,
              tooltip: l10n.markdownToolbarBold(
                WpMarkdownFormatting.boldShortcutLabel,
              ),
              accent: accent,
              muted: mutedColor,
              onTap: format.bold,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.italic,
              tooltip: l10n.markdownToolbarItalic(
                WpMarkdownFormatting.italicShortcutLabel,
              ),
              accent: accent,
              muted: mutedColor,
              onTap: format.italic,
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              color: divColor,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.heading,
              tooltip: l10n.markdownToolbarHeading,
              accent: accent,
              muted: mutedColor,
              onTap: format.heading,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.list,
              tooltip: l10n.markdownToolbarBulletList(
                WpMarkdownFormatting.bulletListShortcutLabel,
              ),
              accent: accent,
              muted: mutedColor,
              onTap: format.bulletList,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.listOrdered,
              tooltip: l10n.markdownToolbarNumberedList,
              accent: accent,
              muted: mutedColor,
              onTap: format.numberedList,
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              color: divColor,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.quote,
              tooltip: l10n.markdownToolbarQuote,
              accent: accent,
              muted: mutedColor,
              onTap: format.quote,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.code,
              tooltip: l10n.markdownToolbarCode,
              accent: accent,
              muted: mutedColor,
              onTap: format.code,
            ),
            Container(
              width: 1,
              height: 16,
              margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xxs),
              color: divColor,
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ToolbarButton.build
            _ToolbarButton(
              icon: LucideIcons.textSearch,
              tooltip: l10n.findReplaceToggle,
              accent: accent,
              muted: mutedColor,
              isActive: findOpen,
              onTap: onToggleFind,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatefulWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.muted,
    required this.onTap,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final Color accent;
  final Color muted;
  final VoidCallback onTap;

  /// Sticky pressed state — only the find toggle has one, because only it
  /// opens something that stays open. The formatting buttons act and are done.
  final bool isActive;

  @override
  State<_ToolbarButton> createState() => _ToolbarButtonState();
}

class _ToolbarButtonState extends State<_ToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = _hovered || widget.isActive;
    return Semantics(
      label: widget.tooltip,
      button: true,
      toggled: widget.isActive ? true : null,
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: WpMotion.durationFor(context, WpMotion.hoverOut),
              padding: const EdgeInsets.all(WpSpacing.xs),
              decoration: BoxDecoration(
                color: highlighted
                    ? widget.accent.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: WpRadius.borderSm,
              ),
              child: Icon(
                widget.icon,
                size: 14,
                color: highlighted ? widget.accent : widget.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
