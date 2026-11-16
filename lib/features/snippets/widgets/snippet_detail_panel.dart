import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/content_metadata_providers.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../snippet_item.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_accent_badge.dart';
import '../../../widgets/wp_editor_pane.dart';
import '../../../widgets/wp_head_actions.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_text_editor.dart';
import '../../../widgets/wp_text_field.dart';

/// A snippet in the trash, the right-hand side of the Snippets split view
/// (page family, `internal-notes`).
///
/// The shared editor pane (#1498) in its read state, built like the note's
/// and the recording's in the trash: the head with title, restore,
/// delete-for-good and close (Esc closes it too via the page), usage and
/// fields as the meta row, then the same writing surface, read-only. An
/// active snippet is never shown here: it opens straight in the
/// [SnippetEditor], where the user writes directly (#1498).
class SnippetDetailPanel extends ConsumerStatefulWidget {
  const SnippetDetailPanel({
    super.key,
    required this.snippet,
    required this.onClose,
    this.onRestore,
    this.onDeleteForever,
  });

  final SnippetItem snippet;
  final VoidCallback onClose;
  final VoidCallback? onRestore;
  final VoidCallback? onDeleteForever;

  @override
  ConsumerState<SnippetDetailPanel> createState() => _SnippetDetailPanelState();
}

class _SnippetDetailPanelState extends ConsumerState<SnippetDetailPanel> {
  // The editor block wants a controller and a focus node even read-only;
  // the read view below stands in for the field.
  late final TextEditingController _controller = TextEditingController(
    text: widget.snippet.body,
  );
  final FocusNode _focusNode = FocusNode(debugLabel: 'SnippetDetailBody');

  SnippetItem get snippet => widget.snippet;

  @override
  void didUpdateWidget(covariant SnippetDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_controller.text != widget.snippet.body) {
      _controller.text = widget.snippet.body;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(
      contentMetadataProvider((kind: ContentKind.snippet, id: snippet.id)),
    );
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'snippets-detail',
      container: true,
      explicitChildNodes: true,
      // The shared editor pane (#1498): same slots, insets and edges as the
      // note and the recording.
      child: WpEditorPane(
        head: _header(context, l10n),
        meta: _meta(context, l10n),
        editor: _editor(l10n),
      ),
    );
  }

  Widget _header(BuildContext context, L10n l10n) {
    // The trash head of all three editors (#1498): restore, delete for
    // good, close.
    final actions = <Widget>[
      WpIconButton.ghost(
        compact: true,
        testId: 'snippets-detail-restore',
        icon: LucideIcons.undo2,
        tooltip: l10n.snippetsRestore,
        onPressed: widget.onRestore,
      ),
      WpIconButton.ghost(
        compact: true,
        testId: 'snippets-detail-delete-forever',
        icon: LucideIcons.trash2,
        tooltip: l10n.snippetsDeleteForever,
        color: WpColors.error,
        onPressed: widget.onDeleteForever,
      ),
    ];
    final close = WpIconButton.ghost(
      compact: true,
      testId: 'snippets-detail-close',
      icon: LucideIcons.x,
      tooltip: '${l10n.actionClose} (Esc)',
      onPressed: widget.onClose,
    );
    // The shared editor head (#1498): the title in the heading style and
    // inset of the other editors, so switching between them moves nothing.
    return WpEditorHead(
      title: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Flexible(
              child: Padding(
                padding: WpTextField.headingContentPadding,
                child: Text(
                  snippet.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WpTextField.styleFor(
                    WpTextFieldVariant.heading,
                    color: WpColors.textPrimary,
                  ),
                ),
              ),
            ),
            if (snippet.isInteractive) ...[
              const SizedBox(width: WpSpacing.xs),
              // The split view opens the panel from a sliver: the title
              // yields first, the badge shrinks only past half the row.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth / 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: WpAccentBadge(label: l10n.snippetsInteractiveBadge),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: WpHeadActions(actions: actions, close: close),
    );
  }

  /// Usage and, for an interactive snippet, its fields; null when there is
  /// neither.
  Widget? _meta(BuildContext context, L10n l10n) {
    final muted = TextStyle(
      color: WpColors.textMuted,
      fontSize: WpTypography.small,
    );
    final lastUsed = snippet.lastUsedAt;
    final showFields = snippet.isInteractive && snippet.fields.isNotEmpty;
    if (lastUsed == null && !showFields) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lastUsed != null)
          Text(
            l10n.snippetsUsageLine(
              snippet.useCount,
              DateFormat.yMd(
                Localizations.localeOf(context).toString(),
              ).format(lastUsed),
            ),
            style: muted,
          ),
        if (lastUsed != null && showFields)
          const SizedBox(height: WpSpacing.xxs),
        if (showFields)
          Text(
            '${l10n.snippetsFieldsLabel}: ${snippet.fields.join(' · ')}',
            style: muted,
          ),
      ],
    );
  }

  /// The editor block in its read state: no tool row (nothing in the trash
  /// can be edited), the passage surface with the text, the status line.
  Widget _editor(L10n l10n) => WpTextEditor(
    testId: 'snippets-detail-editor',
    controller: _controller,
    focusNode: _focusNode,
    variant: WpTextFieldVariant.passage,
    editable: false,
    expands: true,
    semanticsLabel: l10n.snippetsBodyLabel,
    showToolbar: false,
    readText: snippet.body,
    readView: Semantics(
      container: true,
      identifier: 'snippets-detail-body',
      child: WpTextFieldSurface(
        variant: WpTextFieldVariant.passage,
        liftsOnHover: false,
        child: SingleChildScrollView(
          child: Text(
            snippet.body,
            style: WpTextField.styleFor(
              WpTextFieldVariant.passage,
              color: WpColors.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}
