import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_command_box.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../../widgets/wp_search_field.dart';
import 'manual_chapters.dart';
import 'manual_model.dart';

/// Width from which the chapter list sits beside the chapter. Narrower, the
/// chapters become a horizontal chip row above it.
const double _sideBySideMinWidth = 640;

const double _chapterListWidth = 220;

/// The in-app handbook as the Help hub's first tab: a search field, then the
/// chapter list next to (or above, when narrow) the selected chapter.
///
/// The search matches chapter titles, section headings and all text of the
/// chapter. A chapter that a search hides is no longer selectable; the view
/// then shows the first match.
class UserManualView extends StatefulWidget {
  const UserManualView({
    super.key,
    this.chapters,
    this.initialSlug,
    this.initialQuery,
  });

  /// Chapters to show. `null` means the shipped handbook; tests may pass a
  /// subset.
  final List<ManualChapter>? chapters;

  /// The chapter to open first. `null`, or a slug that no chapter has, opens
  /// the first chapter.
  final String? initialSlug;

  /// Search text the view opens with, e.g. handed over from Settings.
  final String? initialQuery;

  @override
  State<UserManualView> createState() => _UserManualViewState();
}

class _UserManualViewState extends State<UserManualView> {
  late String? _slug = widget.initialSlug;
  late final _search = TextEditingController(text: widget.initialQuery);
  late String _query = widget.initialQuery?.trim() ?? '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(ManualChapter chapter) => setState(() => _slug = chapter.slug);

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final chapters = widget.chapters ?? manualChapters;
    assert(chapters.isNotEmpty, 'a handbook needs at least one chapter');
    final visible = [
      for (final chapter in chapters)
        if (_matches(chapter, l10n, _query)) chapter,
    ];

    return Column(
      key: const ValueKey('manual-view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CallbackShortcuts(
          // Escape empties the search, the way it does in the other lists.
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): _clearSearch,
          },
          child: WpSearchField(
            key: const ValueKey('manual-search'),
            controller: _search,
            hintText: l10n.manualSearchHint,
            variant: WpSearchFieldVariant.outlined,
            onChanged: (value) => setState(() => _query = value.trim()),
            onClear: _clearSearch,
          ),
        ),
        if (_query.isNotEmpty) ...[
          const SizedBox(height: WpSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              key: const ValueKey('manual-search-count'),
              l10n.manualSearchResultCount(visible.length),
              style: TextStyle(
                color: WpColors.textSecondary,
                fontSize: WpTypography.caption,
              ),
            ),
          ),
        ],
        const SizedBox(height: WpSpacing.md),
        Expanded(
          child: visible.isEmpty
              ? _NoMatch(l10n: l10n)
              : _Reader(
                  l10n: l10n,
                  chapters: visible,
                  slug: _slug,
                  onSelected: _select,
                ),
        ),
      ],
    );
  }
}

/// Whether [chapter] contains [query] (already trimmed), ignoring case. An
/// empty query matches every chapter.
bool _matches(ManualChapter chapter, L10n l10n, String query) {
  if (query.isEmpty) return true;
  return _chapterText(chapter, l10n).contains(query.toLowerCase());
}

/// All words of [chapter] in lower case, for searching.
String _chapterText(ManualChapter chapter, L10n l10n) {
  final buffer = StringBuffer(chapter.title(l10n));
  for (final section in chapter.sections) {
    buffer.write(' ${section.heading(l10n)}');
    for (final block in section.blocks) {
      buffer.write(' ${_blockText(block, l10n)}');
    }
  }
  return buffer.toString().toLowerCase();
}

String _blockText(ManualBlock block, L10n l10n) => switch (block) {
  ManualParagraph(:final text) => text(l10n),
  ManualBullets(:final items) => items.map((item) => item(l10n)).join(' '),
  ManualTip(:final text) => text(l10n),
  ManualNotice(:final text) => text(l10n),
  ManualLabelled(:final label, :final text) => '${label(l10n)} ${text(l10n)}',
  ManualCode(:final text) => text(l10n),
};

/// The chapter list and the selected chapter, side by side when there is
/// room. [slug] picks the chapter; when it is not among [chapters] (hidden by
/// a search, or unknown) the first of [chapters] is shown.
class _Reader extends StatelessWidget {
  const _Reader({
    required this.l10n,
    required this.chapters,
    required this.slug,
    required this.onSelected,
  });

  final L10n l10n;
  final List<ManualChapter> chapters;
  final String? slug;
  final ValueChanged<ManualChapter> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = chapters.indexWhere((c) => c.slug == slug);
    final index = selected < 0 ? 0 : selected;
    final content = _ChapterContent(chapter: chapters[index]);
    void select(int i) => onSelected(chapters[i]);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _sideBySideMinWidth) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _chapterListWidth,
                child: _ChapterList(
                  l10n: l10n,
                  chapters: chapters,
                  selected: index,
                  onSelected: select,
                ),
              ),
              const SizedBox(width: WpSpacing.lg),
              Expanded(child: content),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ChapterChips(
              l10n: l10n,
              chapters: chapters,
              selected: index,
              onSelected: select,
            ),
            const SizedBox(height: WpSpacing.md),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('manual-search-empty'),
      padding: const EdgeInsets.only(top: WpSpacing.lg),
      child: Text(
        l10n.manualSearchEmpty,
        style: TextStyle(
          color: WpColors.textSecondary,
          fontSize: WpTypography.body,
        ),
      ),
    );
  }
}

// ─── Chapter navigation ──────────────────────────────────────────────────────

class _ChapterList extends StatelessWidget {
  const _ChapterList({
    required this.l10n,
    required this.chapters,
    required this.selected,
    required this.onSelected,
  });

  final L10n l10n;
  final List<ManualChapter> chapters;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('manual-chapter-list'),
      padding: const EdgeInsets.only(bottom: WpSpacing.xl),
      children: [
        for (var i = 0; i < chapters.length; i++)
          _ChapterRow(
            key: ValueKey('manual-chapter-${chapters[i].slug}'),
            label: chapters[i].title(l10n),
            selected: i == selected,
            onTap: () => onSelected(i),
          ),
      ],
    );
  }
}

class _ChapterRow extends StatefulWidget {
  const _ChapterRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends State<_ChapterRow> {
  final _focusNode = FocusNode(debugLabel: 'ManualChapterRow');
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    // The row's visible text is its accessible name; `selected` carries the
    // current chapter for assistive technology.
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: selected,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: WpRadius.sm,
            child: InkWell(
              focusNode: _focusNode,
              onTap: widget.onTap,
              onHover: (hovered) => setState(() => _hovered = hovered),
              borderRadius: WpRadius.borderSm,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? WpColors.accentSubtle
                      : (_hovered ? WpColors.hover : Colors.transparent),
                  borderRadius: WpRadius.borderSm,
                ),
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: selected ? WpColors.accent : WpColors.textPrimary,
                    fontSize: WpTypography.subheading,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
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

class _ChapterChips extends StatelessWidget {
  const _ChapterChips({
    required this.l10n,
    required this.chapters,
    required this.selected,
    required this.onSelected,
  });

  final L10n l10n;
  final List<ManualChapter> chapters;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        key: const ValueKey('manual-chapter-chips'),
        scrollDirection: Axis.horizontal,
        itemCount: chapters.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: WpSpacing.xs),
        itemBuilder: (context, i) => WpFilterChip(
          key: ValueKey('manual-chapter-${chapters[i].slug}'),
          label: chapters[i].title(l10n),
          isActive: i == selected,
          onTap: () => onSelected(i),
        ),
      ),
    );
  }
}

// ─── Chapter content ─────────────────────────────────────────────────────────

class _ChapterContent extends StatelessWidget {
  const _ChapterContent({required this.chapter});

  final ManualChapter chapter;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SingleChildScrollView(
      key: const ValueKey('manual-chapter-content'),
      padding: const EdgeInsets.only(bottom: WpSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              chapter.title(l10n),
              key: const ValueKey('manual-chapter-title'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          for (final section in chapter.sections) ...[
            const SizedBox(height: WpSpacing.lg),
            WpSection(
              title: section.heading(l10n),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in section.blocks)
                    _ManualBlockView(block: block, l10n: l10n),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualBlockView extends StatelessWidget {
  const _ManualBlockView({required this.block, required this.l10n});

  final ManualBlock block;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ManualParagraph(:final text) => _Paragraph(text: text(l10n)),
      ManualBullets(:final items) => _Bullets(
        items: [for (final item in items) item(l10n)],
      ),
      ManualTip(:final text) => _Tip(text: text(l10n)),
      ManualNotice(:final text) => _Notice(
        label: l10n.manualNoticeLabel,
        text: text(l10n),
      ),
      ManualLabelled(:final label, :final text) => _Labelled(
        label: label(l10n),
        text: text(l10n),
      ),
      ManualCode(:final id, :final text) => _Code(
        id: id,
        text: text(l10n),
        copyLabel: l10n.manualCodeCopy,
        copiedLabel: l10n.manualCodeCopied,
        copyFailedLabel: l10n.manualCodeCopyFailed,
      ),
    };
  }
}

/// Body text style, read from the active palette on every build so a theme
/// switch reaches the handbook (a top-level final would freeze the colour).
TextStyle _bodyStyle() => TextStyle(
  color: WpColors.textPrimary,
  fontSize: WpTypography.subheading,
  height: 1.55,
);

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Text(text, style: _bodyStyle()),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: WpSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Off-scale on purpose: optical nudge that centres the dot on
                // the first line's x-height.
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: WpSpacing.sm),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: WpColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: Text(item, style: _bodyStyle())),
              ],
            ),
          ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.md),
        decoration: BoxDecoration(
          color: WpColors.accentSubtle,
          borderRadius: WpRadius.borderSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                LucideIcons.lightbulb,
                size: WpIconSize.sm,
                color: WpColors.accent,
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            Expanded(child: Text(text, style: _bodyStyle())),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(WpSpacing.md),
        decoration: BoxDecoration(
          color: WpColors.surfaceMutedFill,
          borderRadius: WpRadius.borderSm,
          border: Border.all(color: WpColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.caption,
              ),
            ),
            const SizedBox(height: WpSpacing.xxs),
            Text(
              text,
              style: TextStyle(
                color: WpColors.textPrimary,
                fontSize: WpTypography.subheading,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Text.rich(
        TextSpan(
          style: _bodyStyle(),
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: ' $text'),
          ],
        ),
      ),
    );
  }
}

/// A shell command: monospace, selectable, always left to right (also in an
/// RTL locale), with a copy button that confirms with a toast.
class _Code extends StatelessWidget {
  const _Code({
    required this.id,
    required this.text,
    required this.copyLabel,
    required this.copiedLabel,
    required this.copyFailedLabel,
  });

  final String id;
  final String text;
  final String copyLabel;
  final String copiedLabel;
  final String copyFailedLabel;

  Future<void> _copy(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on PlatformException {
      // No clipboard (e.g. no X selection owner): say so, the text stays
      // selectable for a manual copy.
      if (context.mounted) {
        WpToast.show(
          context,
          message: copyFailedLabel,
          type: WpToastType.error,
        );
      }
      return;
    }
    if (context.mounted) {
      WpToast.show(context, message: copiedLabel, type: WpToastType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: WpCommandBox(
        command: text,
        textKey: ValueKey('manual-code-$id'),
        trailing: Semantics(
          button: true,
          label: copyLabel,
          child: Tooltip(
            message: copyLabel,
            // InkWell, not a bare tap target: it takes keyboard focus and
            // runs on Enter/Space too (UIA-HLP-02).
            child: InkWell(
              key: ValueKey('manual-code-$id-copy'),
              customBorder: const CircleBorder(),
              onTap: () => _copy(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: WpLayout.minTouchTarget,
                  minHeight: WpLayout.minTouchTarget,
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.copy,
                    size: WpIconSize.sm,
                    color: WpColors.textSecondary,
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
