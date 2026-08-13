import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/markdown_toolbar.dart';
import '../../../widgets/tag_input.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_text_field.dart';
import '../../../widgets/wp_voice_input_button.dart';
import '../data/note_title.dart';
import 'quick_note_hotkey_line.dart';

// ---------------------------------------------------------------------------
// Note editor panel — strongly reduced sibling of HistoryDetailPanel:
// a slim toolbar row, a hairline divider, and an always-editable multiline
// text field. Controller + focus node are OWNED BY _NotesPageState and only
// passed through here, so cursor/IME state survive panel rebuilds.
// ---------------------------------------------------------------------------

/// Width reserved for the leading quick-note mark button — an [IconButton]'s
/// own default minimum, stated here because the action cluster's width cap
/// subtracts it (see the toolbar row). Keep it equal to the button's actual
/// extent — give that button a `visualDensity` or `padding` without changing
/// this, and the cap drifts and the row overflows again.
const double _quickNoteMarkExtent = kMinInteractiveDimension;

class NoteEditorPanel extends StatelessWidget {
  const NoteEditorPanel({
    super.key,
    required this.note,
    required this.tags,
    required this.controller,
    required this.focusNode,
    this.scrollEditorToEnd,
    required this.onClose,
    required this.onToggleFavorite,
    required this.onQuickNoteSet,
    required this.onQuickNoteClear,
    required this.onMoveToTrash,
    required this.onRestore,
    required this.onDeleteForever,
    required this.onAddTag,
    required this.onRemoveTag,
    required this.onExport,
    required this.onVoiceTranscript,
  });

  final Note note;

  /// Tags linked to this note (from noteTagsProvider, alphabetically sorted).
  final List<Tag> tags;
  final TextEditingController controller;
  final FocusNode focusNode;

  /// Fires when the body field should jump to the end of the note — after a
  /// quick-note append, so the freshly appended text is what is visible
  /// (Ticket 21). Owned by `_NotesPageState` like the two above, and optional
  /// so the panel stays constructible without one (several widget tests build
  /// it directly).
  final Listenable? scrollEditorToEnd;
  final VoidCallback onClose;
  final VoidCallback onToggleFavorite;

  /// Make this note the quick note — offered only while it is not already the
  /// quick note (see the toolbar's comment on the two separate controls).
  final VoidCallback onQuickNoteSet;

  /// Drop the quick-note mark, leaving no note marked.
  final VoidCallback onQuickNoteClear;
  final VoidCallback onMoveToTrash;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  /// Add/remove a tag on this note (tagName / tagId).
  final ValueChanged<String> onAddTag;
  final ValueChanged<String> onRemoveTag;

  /// Export this note via the format picker (txt/md).
  final VoidCallback onExport;

  /// Called with the raw transcript when the voice-input button finishes —
  /// the panel does not insert it itself, that's `_NotesPageState`'s job
  /// (cursor position lives in the shared controller/selection, not here).
  final ValueChanged<String> onVoiceTranscript;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const textPrimary = WpColors.textPrimary;
    const textMuted = WpColors.textMuted;
    const errorColor = WpColors.error;
    final isTrashed = note.deletedAt != null;
    final showQuickNoteMark = !isTrashed && note.isQuickNote;

    return DecoratedBox(
      decoration: const BoxDecoration(gradient: WpColors.surfaceGradient),
      child: Column(
        children: [
          // ── Toolbar row ──
          // Quick-note mark (only when this note holds it) + derived title +
          // copy + export + voice input + favourite/quick-note/trash (or
          // restore/delete-forever for trashed notes) + close.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl,
              WpSpacing.sm,
              WpSpacing.sm,
              WpSpacing.sm,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  if (showQuickNoteMark)
                    // The quick-note mark, and the only control that drops it.
                    //
                    // Deliberately on the title side rather than in the action
                    // cluster on the right: the cluster is where *setting* the
                    // mark lives, and no position may carry both meanings — a
                    // default value must not flip by being chosen twice. It
                    // also keeps the cluster from growing in the marked state,
                    // which is the state the 280 dp panel floor already
                    // struggles with (FLUTTER_WHISPASTE-64).
                    //
                    // Bolt in the generic interaction accent (cyan, ADR 0013),
                    // never the amber star's glyph or colour: the two mean
                    // different things and must not be mistaken for each
                    // other.
                    SizedBox(
                      // Pinned to a known extent so the cluster's cap below
                      // can subtract it. An unmeasured child to the *left* of
                      // the flexible title would eat into the cluster's budget
                      // without the cap ever hearing about it — the
                      // FLUTTER_WHISPASTE-64 failure mode again, one child
                      // further along the row.
                      width: _quickNoteMarkExtent,
                      child: Semantics(
                        label: l10n.notesQuickNoteClear,
                        button: true,
                        child: IconButton(
                          onPressed: onQuickNoteClear,
                          tooltip: l10n.notesQuickNoteClear,
                          icon: const FaIcon(
                            FontAwesomeIcons.bolt,
                            size: WpIconSize.sm,
                            color: WpColors.accent,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      deriveNoteTitle(note.content) ?? l10n.notesUntitled,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: WpTypography.title,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  // The action cluster is inflexible — a Row hands its
                  // non-flex children unbounded width — and measures ~248 dp,
                  // while the split view renders this panel down to 280 dp
                  // (`_minDetailRenderWidth`), where the 24/12 inset leaves
                  // 244. Four dp short, which is exactly the overflow Sentry
                  // kept reporting from the open/close animation's narrow
                  // frames (FLUTTER_WHISPASTE-64).
                  //
                  // Capping the cluster at the width that is actually there
                  // lets it scale instead of overflow. At every width the
                  // panel rests at, the cap is above the cluster's natural
                  // size and `scaleDown` is a no-op — the toolbar is
                  // unchanged wherever a user can actually stop the drag.
                  //
                  // The cap has to subtract every inflexible child to its
                  // left, not just the gap: the quick-note mark is one such
                  // child in the marked state, and the title next to it is the
                  // only flexible thing in the row.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.hasBoundedWidth
                          ? (constraints.maxWidth -
                                    WpSpacing.xs -
                                    (showQuickNoteMark
                                        ? _quickNoteMarkExtent
                                        : 0.0))
                                .clamp(0.0, double.infinity)
                          : double.infinity,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Each toolbar IconButton is wrapped in Semantics(label:) —
                          // IconButton's tooltip: only yields a semantics HINT, not a
                          // NAME, so screen readers would otherwise announce an unnamed
                          // button (and bySemanticsLabel tests could not find it).
                          Semantics(
                            label: l10n.notesCopy,
                            button: true,
                            child: IconButton(
                              onPressed: () {
                                // Deliberately no telemetry here: note contents are on
                                // the telemetry negative list (CONTEXT.md) — unlike the
                                // history copy action, this stays event-free.
                                Clipboard.setData(
                                  ClipboardData(text: controller.text),
                                );
                                WpToast.show(
                                  context,
                                  message: l10n.notesCopied,
                                  type: WpToastType.success,
                                  duration: const Duration(seconds: 2),
                                );
                              },
                              tooltip: l10n.notesCopy,
                              icon: const Icon(
                                LucideIcons.copy,
                                size: WpIconSize.md,
                                color: textMuted,
                              ),
                            ),
                          ),
                          Semantics(
                            label: l10n.notesExport,
                            button: true,
                            child: IconButton(
                              onPressed: onExport,
                              tooltip: l10n.notesExport,
                              icon: const Icon(
                                LucideIcons.download,
                                size: WpIconSize.md,
                                color: textMuted,
                              ),
                            ),
                          ),
                          WpVoiceInputButton(
                            // Keyed per note — see the note on the body field
                            // below. A dictation started here delivers its
                            // transcript into whichever note is open when it
                            // finishes (up to 45 s later), so the button has
                            // to go down with the note it was started on:
                            // its own mounted-guard then drops the transcript
                            // instead of writing note A's words into note B.
                            key: ValueKey('voice-${note.id}'),
                            onTranscript: onVoiceTranscript,
                          ),
                          if (isTrashed) ...[
                            // Trash view: restore + delete forever instead of the
                            // favourite/move-to-trash pair (copy stays — it's harmless
                            // and occasionally useful for salvaging trashed text).
                            Semantics(
                              label: l10n.notesRestore,
                              button: true,
                              child: IconButton(
                                onPressed: onRestore,
                                tooltip: l10n.notesRestore,
                                icon: const Icon(
                                  LucideIcons.undo2,
                                  size: WpIconSize.md,
                                  color: textMuted,
                                ),
                              ),
                            ),
                            Semantics(
                              label: l10n.notesDeleteForever,
                              button: true,
                              child: IconButton(
                                onPressed: onDeleteForever,
                                tooltip: l10n.notesDeleteForever,
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: WpIconSize.md,
                                  color: errorColor,
                                ),
                              ),
                            ),
                          ] else ...[
                            Semantics(
                              label: note.pinned
                                  ? l10n.notesUnfavorite
                                  : l10n.notesFavorite,
                              button: true,
                              child: IconButton(
                                onPressed: onToggleFavorite,
                                tooltip: note.pinned
                                    ? l10n.notesUnfavorite
                                    : l10n.notesFavorite,
                                // Solid amber star when pinned, Lucide outline star
                                // otherwise — same pinned/unpinned glyph pair as
                                // history's detail-panel pin action.
                                icon: note.pinned
                                    ? const FaIcon(
                                        FontAwesomeIcons.solidStar,
                                        size: WpIconSize.sm,
                                        color: WpSharedColors.pinnedAccent,
                                      )
                                    : const Icon(
                                        LucideIcons.star,
                                        size: WpIconSize.md,
                                        color: textMuted,
                                      ),
                              ),
                            ),
                            if (!note.isQuickNote)
                              // Setting the mark sits with the other per-note
                              // actions; on the note that already holds it
                              // this button is simply absent, so re-marking
                              // is impossible rather than a silent no-op.
                              // Removing the mark lives on the title side.
                              Semantics(
                                label: l10n.notesQuickNoteSet,
                                button: true,
                                child: IconButton(
                                  onPressed: onQuickNoteSet,
                                  tooltip: l10n.notesQuickNoteSet,
                                  icon: const Icon(
                                    LucideIcons.zap,
                                    size: WpIconSize.md,
                                    color: textMuted,
                                  ),
                                ),
                              ),
                            Semantics(
                              label: l10n.notesMoveToTrash,
                              button: true,
                              child: IconButton(
                                onPressed: onMoveToTrash,
                                tooltip: l10n.notesMoveToTrash,
                                icon: const Icon(
                                  LucideIcons.trash2,
                                  size: WpIconSize.md,
                                  color: textMuted,
                                ),
                              ),
                            ),
                          ],
                          Semantics(
                            label: l10n.historyClose,
                            button: true,
                            child: IconButton(
                              onPressed: onClose,
                              tooltip: l10n.historyClose,
                              icon: const Icon(
                                LucideIcons.x,
                                size: WpIconSize.md,
                                color: textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Quick-note hotkey ──
          // Sits with the mark, one line below it, and only on the note that
          // actually holds the mark: whoever picks the target note is right
          // then asking what triggers it (Ticket 24). Deliberately not *in*
          // the toolbar row above — that cluster is capped for the 280 dp
          // panel floor (FLUTTER_WHISPASTE-64) and another inflexible child
          // would spend the budget the actions need.
          //
          // `showQuickNoteMark` is also what keeps it out of the trash view:
          // a trashed note never carries the mark's UI, so the setting it
          // belongs to has nothing to sit next to there.
          if (showQuickNoteMark) const QuickNoteHotkeyLine(),
          // ── Tags ──
          // Deliberately minimal compared to history's tag section: no
          // suggestions, no inline label, no management-dialog button.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl,
              0,
              WpSpacing.xl,
              WpSpacing.xs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpTagInput(
                // Keyed per note: a half-typed, unsubmitted tag name must not
                // ride along to the next note, where Enter would file it.
                // Clicking a list tile already closes add mode through the
                // input's own TapRegion, but Ctrl/Cmd+N (deliberately not
                // guarded by isTextFieldFocused, see _buildListShortcuts) and
                // the quick-note deep link do not go through a pointer.
                key: ValueKey('tags-${note.id}'),
                tags: tags,
                onAdd: onAddTag,
                onRemove: onRemoveTag,
                hintText: l10n.notesAddTag,
                searchHintText: l10n.notesTagPlaceholder,
              ),
            ),
          ),
          // ── Divider ──
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
            color: WpColors.borderSubtle,
          ),
          // ── Formatting toolbar ──
          // Its own row under the divider, permanently — Notes has no read
          // mode to hide it behind (History shows the same bar only while
          // `isEditing`), and a bar that comes and goes on a surface whose
          // whole purpose is writing would move the text under the cursor.
          // Deliberately *not* in the header row above: that cluster already
          // overflowed at the 280 dp panel floor (FLUTTER_WHISPASTE-64) and
          // is capped by a `FittedBox` for it.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              WpSpacing.xl,
              WpSpacing.xs,
              WpSpacing.xl,
              0,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: WpMarkdownToolbar(
                // Keyed per note: it owns the find/replace bar's open flag and
                // both of its fields. Carried over, note B would open with
                // note A's query AND its replacement string loaded and one
                // click from rewriting note B with them — and the still-live
                // bar would re-apply its old query on top of the
                // clearFindHighlight() that _setEditorText does on switch.
                key: ValueKey('toolbar-${note.id}'),
                controller: controller,
                focusNode: focusNode,
              ),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          // ── Editor ──
          // Nothing else shares the region below the divider, so the field
          // *is* the surface: no stroke at rest (it takes the accent one on
          // focus, like every other variant), prose metrics identical to
          // History's transcript. See WpTextField's library docs.
          //
          // Ctrl/Cmd+B, +I and +Shift+L — the very shortcuts the bar's
          // tooltips advertise — are bound around the field and nowhere
          // else. They come out of the toolbar's own owner, so the key and
          // the button it sits under cannot drift apart, and scoping them to
          // this subtree (instead of guarding a panel-wide binding) keeps
          // them off the tag input above without inventing a condition:
          // a key pressed inside the tag field never reaches this Focus.
          Expanded(
            child: CallbackShortcuts(
              bindings: WpMarkdownFormatting(
                controller: controller,
                focusNode: focusNode,
              ).shortcutBindings(),
              child: WpTextField(
                controller: controller,
                focusNode: focusNode,
                scrollToEnd: scrollEditorToEnd,
                variant: WpTextFieldVariant.bare,
                hintText: l10n.notesEditorPlaceholder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
