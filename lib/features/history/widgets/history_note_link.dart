import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/notes_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart'
    show activePageProvider, notesEditorTargetProvider;
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_text_link.dart';

/// "Taken over as a note" under a recording that was copied into a note with
/// "Als Notiz übernehmen" (issue #629). One click opens that note. Draws
/// nothing while no live note points here, so deleting the note (or moving it
/// to the trash) takes the link away without a trace.
class HistoryNoteLink extends ConsumerWidget {
  const HistoryNoteLink({super.key, required this.entryId});

  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteTakenFromEntryProvider(entryId)).value;
    if (note == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        WpSpacing.xl,
        0,
        WpSpacing.xl,
        WpSpacing.xs,
      ),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: WpTextLink(
          testID: 'history-detail-note-link',
          label: L10n.of(context).historyInNote,
          kind: WpLinkKind.page,
          onPressed: () {
            ref.read(notesEditorTargetProvider.notifier).set(note.id);
            ref.read(activePageProvider.notifier).setPage('notes');
          },
        ),
      ),
    );
  }
}
