import 'package:flutter/material.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/text/markdown_checklist.dart';
import '../core/text/markdown_plain_text.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import 'wp_button.dart';
import 'wp_row_checkbox.dart';

/// The read view of Markdown text (#643): headings, bold, italic, lists,
/// quotes, code and checklists show as such instead of as asterisks.
///
/// The text stays the one source of truth (ADR 0035). Ticking a box hands the
/// rewritten source (`- [ ]` ↔ `- [x]`) to [onChanged]; the caller stores it
/// the same way an edit would be stored. With [onChanged] null the boxes are
/// shown but read-only (the trash, an AI-edited version).
///
/// Text without any Markdown renders as one paragraph in [style], exactly as
/// the plain read view did, so switching between reading and editing moves
/// nothing for the transcripts most users have.
///
/// Semantics identifiers: `<testId>-task-<n>` per box (n counts from 0 in text
/// order), `<testId>-check-all`, `<testId>-uncheck-all`, `<testId>-move-done`.
class WpMarkdownView extends StatelessWidget {
  const WpMarkdownView({
    super.key,
    required this.testId,
    required this.source,
    required this.style,
    this.highlight = '',
    this.onChanged,
  });

  final String testId;
  final String source;

  /// Body text style — the field's own, so read and edit view line up.
  final TextStyle style;

  /// A search query whose matches are tinted, as in the plain read view.
  final String highlight;

  /// Receives the new source after a box or a checklist action changed it.
  final ValueChanged<String>? onChanged;

  /// Whether [source] contains anything the view would render differently
  /// from plain text.
  static bool hasMarkdown(String source) =>
      _blockMarker.hasMatch(source) || _inlineMarker.hasMatch(source);

  @override
  Widget build(BuildContext context) {
    final query = highlight.trim();
    if (!hasMarkdown(source)) {
      return Text.rich(
        TextSpan(children: _highlighted(source, query)),
        style: style,
      );
    }
    final blocks = _parse(source);
    final fontSize = style.fontSize ?? WpTypography.heading;
    final lineHeight = fontSize * (style.height ?? 1.0);
    final children = <Widget>[];
    var taskIndex = 0;
    for (final block in blocks) {
      children.add(
        _buildBlock(context, block, query, lineHeight, () => taskIndex++),
      );
    }
    final items = checklistItems(source);
    if (onChanged != null && items.isNotEmpty) {
      children.add(
        _ChecklistActions(
          testId: testId,
          source: source,
          items: items,
          onChanged: onChanged!,
        ),
      );
    }
    return DefaultTextStyle.merge(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    _Block block,
    String query,
    double lineHeight,
    int Function() nextTask,
  ) {
    switch (block.kind) {
      case _Kind.blank:
        return SizedBox(height: lineHeight * block.count);
      case _Kind.rule:
        return SizedBox(
          height: lineHeight,
          child: Center(
            child: Container(height: 1, color: WpColors.borderDefault),
          ),
        );
      case _Kind.heading:
        final factor = switch (block.level) {
          1 => 1.5,
          2 => 1.3,
          3 => 1.15,
          _ => 1.0,
        };
        final base = style.fontSize ?? WpTypography.heading;
        return Semantics(
          header: true,
          child: Text.rich(
            TextSpan(children: _inline(block.text, query)),
            style: style.copyWith(
              fontSize: base * factor,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        );
      case _Kind.paragraph:
        return Text.rich(
          TextSpan(children: _inline(block.text, query)),
          style: style,
        );
      case _Kind.quote:
        return Container(
          padding: const EdgeInsetsDirectional.only(start: WpSpacing.md),
          decoration: BoxDecoration(
            border: BorderDirectional(
              start: BorderSide(color: WpColors.borderDefault, width: 3),
            ),
          ),
          child: Text.rich(
            TextSpan(children: _inline(block.text, query)),
            style: style.copyWith(color: WpColors.textSecondary),
          ),
        );
      case _Kind.code:
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: WpColors.surfaceMutedFill,
            borderRadius: WpRadius.borderSm,
          ),
          child: Text.rich(
            TextSpan(children: _highlighted(block.text, query)),
            style: style.copyWith(
              fontFamily: 'monospace',
              fontSize: (style.fontSize ?? WpTypography.heading) - 2,
            ),
          ),
        );
      case _Kind.bullet:
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: block.level * WpSpacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: WpRowCheckbox.inlineExtent,
                child: Text(
                  block.marker,
                  style: style.copyWith(color: WpColors.textSecondary),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _inline(block.text, query)),
                  style: style,
                ),
              ),
            ],
          ),
        );
      case _Kind.task:
        final index = nextTask();
        final callback = onChanged;
        final label = markdownToPlainText(block.text);
        return Padding(
          padding: EdgeInsetsDirectional.only(
            start: block.level * WpSpacing.xl,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: lineHeight,
                child: Semantics(
                  identifier: '$testId-task-$index',
                  // A read-only box stays visible but must not look like it
                  // could be ticked: no action, announced as disabled.
                  enabled: callback != null,
                  child: IgnorePointer(
                    ignoring: callback == null,
                    child: ExcludeFocus(
                      excluding: callback == null,
                      child: WpRowCheckbox(
                        inline: true,
                        value: block.checked,
                        semanticsLabel: label,
                        onChanged: () {
                          if (callback == null) return;
                          callback(toggleChecklistItem(source, block.line));
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _inline(block.text, query)),
                  style: block.checked
                      ? style.copyWith(
                          color: WpColors.textMuted,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: WpColors.textMuted,
                        )
                      : style,
                ),
              ),
            ],
          ),
        );
    }
  }
}

/// "Check all", "Reset" and "Done to the bottom" under a checklist.
class _ChecklistActions extends StatelessWidget {
  const _ChecklistActions({
    required this.testId,
    required this.source,
    required this.items,
    required this.onChanged,
  });

  final String testId;
  final String source;
  final List<ChecklistItem> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final anyOpen = items.any((i) => !i.checked);
    final anyDone = items.any((i) => i.checked);
    final moved = moveCheckedToBottom(source);
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Wrap(
        spacing: WpSpacing.buttonGap,
        runSpacing: WpSpacing.xs,
        children: [
          WpButton(
            testId: '$testId-check-all',
            label: l10n.checklistCheckAll,
            variant: WpButtonVariant.ghost,
            size: WpButtonSize.dense,
            onPressed: anyOpen
                ? () => onChanged(setAllChecklistItems(source, checked: true))
                : null,
          ),
          WpButton(
            testId: '$testId-uncheck-all',
            label: l10n.checklistUncheckAll,
            variant: WpButtonVariant.ghost,
            size: WpButtonSize.dense,
            onPressed: anyDone
                ? () => onChanged(setAllChecklistItems(source, checked: false))
                : null,
          ),
          WpButton(
            testId: '$testId-move-done',
            label: l10n.checklistMoveDoneDown,
            variant: WpButtonVariant.ghost,
            size: WpButtonSize.dense,
            onPressed: moved != source ? () => onChanged(moved) : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Block parsing
// ---------------------------------------------------------------------------

enum _Kind { paragraph, heading, quote, bullet, task, code, rule, blank }

class _Block {
  _Block(
    this.kind, {
    this.text = '',
    this.level = 0,
    this.marker = '',
    this.checked = false,
    this.line = 0,
    this.count = 1,
  });

  final _Kind kind;
  String text;

  /// Heading level, or the nesting depth of a list item.
  final int level;
  final String marker;
  final bool checked;

  /// Source line of a task (for toggling).
  final int line;

  /// Number of blank lines a blank block stands for.
  int count;
}

final _blockMarker = RegExp(
  r'^\s{0,3}(?:#{1,6}(?:\s|$)|>|```|~~~)|^\s*(?:[-*+]|\d{1,9}[.)])[ \t]',
  multiLine: true,
);
final _inlineMarker = RegExp(
  r'\*\*\S|__\S|~~\S|==\S|`[^`]+`|(?<![\w*])\*[^\s*][^*]*\*|\[[^\]]+\]\([^)]*\)',
);
final _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
final _heading = RegExp(r'^\s{0,3}(#{1,6})(?:\s+(.*?))?(?:\s+#+)?\s*$');
final _quote = RegExp(r'^\s{0,3}>\s?(.*)$');
final _rule = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
final _task = RegExp(
  r'^(\s*)(?:[-*+]|\d{1,9}[.)])[ \t]+\[([ xX])\](?:[ \t]+(.*))?$',
);
final _list = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])[ \t]+(.*)$');

List<_Block> _parse(String source) {
  final lines = source.split('\n');
  final blocks = <_Block>[];
  final indents = <int>[];
  String? fence;
  _Block? code;

  int depthFor(String indent) {
    var width = 0;
    for (final c in indent.codeUnits) {
      width += c == 0x09 ? 4 : 1;
    }
    while (indents.isNotEmpty && indents.last > width) {
      indents.removeLast();
    }
    if (indents.isEmpty || indents.last < width) indents.add(width);
    return indents.length - 1;
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);

    if (fence != null) {
      final m = _fence.firstMatch(line);
      if (m != null &&
          m.group(1)!.startsWith(fence) &&
          line.trim().length == m.group(1)!.length) {
        fence = null;
        code = null;
      } else {
        code!.text = code.count == 0 ? line : '${code.text}\n$line';
        code.count++;
      }
      continue;
    }
    final fenceOpen = _fence.firstMatch(line);
    if (fenceOpen != null) {
      fence = fenceOpen.group(1);
      code = _Block(_Kind.code, count: 0);
      blocks.add(code);
      indents.clear();
      continue;
    }

    if (line.trim().isEmpty) {
      final last = blocks.isEmpty ? null : blocks.last;
      if (last != null && last.kind == _Kind.blank) {
        last.count++;
      } else {
        blocks.add(_Block(_Kind.blank));
      }
      continue;
    }

    if (_rule.hasMatch(line)) {
      blocks.add(_Block(_Kind.rule));
      indents.clear();
      continue;
    }
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      blocks.add(
        _Block(
          _Kind.heading,
          text: heading.group(2) ?? '',
          level: heading.group(1)!.length,
        ),
      );
      indents.clear();
      continue;
    }
    final quote = _quote.firstMatch(line);
    if (quote != null) {
      var text = quote.group(1)!;
      // Nested quotes ("> > text") flatten into one bar.
      var inner = _quote.firstMatch(text);
      while (inner != null) {
        text = inner.group(1)!;
        inner = _quote.firstMatch(text);
      }
      final last = blocks.isEmpty ? null : blocks.last;
      if (last != null && last.kind == _Kind.quote) {
        last.text = '${last.text}\n$text';
      } else {
        blocks.add(_Block(_Kind.quote, text: text));
      }
      indents.clear();
      continue;
    }
    final task = _task.firstMatch(line);
    if (task != null) {
      blocks.add(
        _Block(
          _Kind.task,
          text: task.group(3) ?? '',
          level: depthFor(task.group(1)!),
          checked: task.group(2) != ' ',
          line: i,
        ),
      );
      continue;
    }
    final list = _list.firstMatch(line);
    if (list != null) {
      final marker = list.group(2)!;
      blocks.add(
        _Block(
          _Kind.bullet,
          text: list.group(3)!,
          level: depthFor(list.group(1)!),
          marker: RegExp(r'^\d').hasMatch(marker) ? marker : '•',
        ),
      );
      continue;
    }

    // Plain line: continues the paragraph above, or the list item above when
    // it is indented under it (wrapped item text).
    final last = blocks.isEmpty ? null : blocks.last;
    final trimmed = line.trimLeft();
    if (last != null &&
        (last.kind == _Kind.paragraph ||
            ((last.kind == _Kind.bullet || last.kind == _Kind.task) &&
                trimmed.length < line.length))) {
      last.text =
          '${last.text}\n${last.kind == _Kind.paragraph ? line : trimmed}';
      continue;
    }
    blocks.add(_Block(_Kind.paragraph, text: line));
    indents.clear();
  }
  return blocks;
}

// ---------------------------------------------------------------------------
// Inline spans
// ---------------------------------------------------------------------------

class _InlineRule {
  const _InlineRule(this.pattern, this.build);
  final RegExp pattern;
  final List<InlineSpan> Function(RegExpMatch m, String query) build;
}

final List<_InlineRule> _inlineRules = [
  _InlineRule(
    RegExp(r'\\([\\`*_{}\[\]()#+\-.!>~=|<])'),
    (m, q) => _highlighted(m.group(1)!, q),
  ),
  _InlineRule(
    RegExp(r'(`+)(.+?)\1'),
    (m, q) => [
      TextSpan(
        style: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: WpColors.surfaceMutedFill,
        ),
        children: _highlighted(m.group(2)!, q),
      ),
    ],
  ),
  _InlineRule(
    RegExp(r'!?\[([^\]]+)\]\(([^)\s]*)(?:\s+"[^"]*")?\)'),
    (m, q) => [
      TextSpan(
        style: TextStyle(color: WpColors.accent),
        children: _inline(m.group(1)!, q),
      ),
    ],
  ),
  _InlineRule(
    RegExp(r'<((?:https?|mailto):[^>\s]+)>'),
    (m, q) => [
      TextSpan(
        style: TextStyle(color: WpColors.accent),
        children: _highlighted(m.group(1)!, q),
      ),
    ],
  ),
  _InlineRule(
    RegExp(r'\*\*(?=\S)(.+?)(?<=\S)\*\*'),
    (m, q) => [
      _styled(m.group(1)!, q, const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ),
  _InlineRule(
    RegExp(
      r'(?<![\p{L}\p{N}_])__(?=\S)(.+?)(?<=\S)__(?![\p{L}\p{N}_])',
      unicode: true,
    ),
    (m, q) => [
      _styled(m.group(1)!, q, const TextStyle(fontWeight: FontWeight.w700)),
    ],
  ),
  _InlineRule(
    RegExp(r'~~(?=\S)(.+?)(?<=\S)~~'),
    (m, q) => [
      _styled(
        m.group(1)!,
        q,
        const TextStyle(decoration: TextDecoration.lineThrough),
      ),
    ],
  ),
  _InlineRule(
    RegExp(r'==(?=\S)(.+?)(?<=\S)=='),
    (m, q) => [
      _styled(
        m.group(1)!,
        q,
        TextStyle(backgroundColor: WpColors.highlightSoft),
      ),
    ],
  ),
  _InlineRule(
    RegExp(r'(?<!\*)\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?!\*)'),
    (m, q) => [
      _styled(m.group(1)!, q, const TextStyle(fontStyle: FontStyle.italic)),
    ],
  ),
  _InlineRule(
    RegExp(
      r'(?<![\p{L}\p{N}_])_(?=[^\s_])(.+?)(?<=[^\s_])_(?![\p{L}\p{N}_])',
      unicode: true,
    ),
    (m, q) => [
      _styled(m.group(1)!, q, const TextStyle(fontStyle: FontStyle.italic)),
    ],
  ),
];

TextSpan _styled(String inner, String query, TextStyle style) =>
    TextSpan(style: style, children: _inline(inner, query));

/// Splits [text] at its earliest inline marker, renders that span and
/// recurses on the rest; plain stretches get the search tint.
List<InlineSpan> _inline(String text, String query) {
  final spans = <InlineSpan>[];
  var rest = text;
  while (rest.isNotEmpty) {
    RegExpMatch? best;
    _InlineRule? bestRule;
    for (final rule in _inlineRules) {
      final m = rule.pattern.firstMatch(rest);
      if (m != null && (best == null || m.start < best.start)) {
        best = m;
        bestRule = rule;
      }
    }
    if (best == null) {
      spans.addAll(_highlighted(rest, query));
      break;
    }
    if (best.start > 0) {
      spans.addAll(_highlighted(rest.substring(0, best.start), query));
    }
    spans.addAll(bestRule!.build(best, query));
    rest = rest.substring(best.end);
  }
  return spans;
}

/// [text] with every match of [query] tinted the way the History search
/// marks it everywhere else.
List<InlineSpan> _highlighted(String text, String query) {
  // A zero-width space keeps an empty line one line tall.
  if (text.isEmpty) return const [TextSpan(text: '​')];
  if (query.isEmpty) return [TextSpan(text: text)];
  final accent = WpColors.accent;
  final tint = TextStyle(
    backgroundColor: accent.withValues(alpha: 0.28),
    color: accent,
    fontWeight: FontWeight.w700,
  );
  final spans = <InlineSpan>[];
  var start = 0;
  for (final m in RegExp(
    RegExp.escape(query),
    caseSensitive: false,
  ).allMatches(text)) {
    if (m.start > start) {
      spans.add(TextSpan(text: text.substring(start, m.start)));
    }
    spans.add(TextSpan(text: text.substring(m.start, m.end), style: tint));
    start = m.end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans;
}
