import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/data/database.dart' show Note;
import '../../core/data/notes_providers.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../services/app_identity/app_category.dart';
import '../../widgets/wp_app_icon.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import '../notes/data/note_title.dart';
import '../notes/data/notes_actions.dart';
import '../history/widgets/history_helpers.dart' show formatHistoryTime;
import 'overview_navigation.dart';
import 'overview_rows.dart';

/// The notes edited last (#630), in the same card and rows as the newest
/// recordings ([OverviewRowsCard]): the day or time, the notes tile, the
/// title, and "open". Without notes one sentence invites a new one.
class OverviewNotes extends ConsumerWidget {
  const OverviewNotes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final notes = overviewLatestNotes(
      ref.watch(notesProvider).value ?? const [],
    );
    return OverviewRowsCard(
      key: const ValueKey('overview-notes'),
      title: l10n.navNotes,
      testId: 'overview-notes',
      allLabel: l10n.overviewNotesAll,
      onAll: () => overviewOpenTarget(ref, 'notes'),
      empty: notes.isEmpty ? const _Empty() : null,
      rows: [
        for (final note in notes)
          _NoteRow(key: ValueKey('overview-notes-${note.id}'), note: note),
      ],
    );
  }
}

/// The card's one-sentence empty line, see [OverviewRowsCard.empty] for why
/// it is not a `WpEmptyState`.
class _Empty extends ConsumerWidget {
  const _Empty();

  Future<void> _create(WidgetRef ref) async {
    final note = await ref.read(notesActionsProvider).create();
    overviewOpenNote(ref, note.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    return Wrap(
      key: const ValueKey('overview-notes-empty'),
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: WpSpacing.sm,
      runSpacing: WpSpacing.xs,
      children: [
        Text(l10n.overviewNotesEmpty, style: WpTextStyles.rowTitle),
        WpTextLink(
          testID: 'overview-notes-new',
          label: l10n.notesNewNote,
          onPressed: () => unawaited(_create(ref)),
        ),
      ],
    );
  }
}

class _NoteRow extends ConsumerWidget {
  const _NoteRow({super.key, required this.note});

  final Note note;

  /// Today the time, else "yesterday" or a short date (year only when it
  /// differs), as in the notes list.
  String _when(BuildContext context, L10n l10n) {
    final t = note.updatedAt;
    final now = clock.now();
    final locale = Localizations.localeOf(context).toString();
    return switch (overviewDayOf(t, now)) {
      OverviewDay.today => formatHistoryTime(t),
      OverviewDay.yesterday => l10n.historyYesterday,
      OverviewDay.earlier =>
        (t.year == now.year
                ? DateFormat.MMMd(locale)
                : DateFormat.yMMMd(locale))
            .format(t),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final explicit = note.title?.trim();
    final title = explicit != null && explicit.isNotEmpty
        ? explicit
        : deriveNoteTitle(note.content) ?? l10n.notesUntitled;
    return OverviewRow(
      time: _when(context, l10n),
      // A date is wider than a time; the wider column keeps it on one line.
      timeWidth: 64,
      leading: const ExcludeSemantics(
        child: WpAppCategoryTile(
          category: AppCategory.notes,
          size: WpIconSize.xl,
        ),
      ),
      text: title,
      onOpen: () => overviewOpenNote(ref, note.id),
      actions: [
        WpIconButton.ghost(
          testId: 'overview-notes-open-${note.id}',
          icon: LucideIcons.ellipsis,
          tooltip: l10n.overviewNotesOpen,
          onPressed: () => overviewOpenNote(ref, note.id),
        ),
      ],
    );
  }
}
