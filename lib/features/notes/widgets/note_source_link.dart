import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/data/notes_providers.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart'
    show activePageProvider, historyOpenEntryProvider;
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_text_link.dart';

/// "From recording of ..." under a note that was taken from a recording
/// (issue #629). One click opens that recording. Draws nothing while the
/// recording is gone or in the trash, so deleting it leaves no broken link.
class NoteSourceLink extends ConsumerWidget {
  const NoteSourceLink({super.key, required this.sourceEntryId});

  final String? sourceEntryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = sourceEntryId;
    if (id == null) return const SizedBox.shrink();
    final entry = ref.watch(liveEntryProvider(id)).value;
    if (entry == null) return const SizedBox.shrink();
    final locale = Localizations.localeOf(context).toString();
    final date = DateFormat.yMMMd(locale).add_Hm().format(entry.timestamp);
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
          testID: 'notes-editor-source-link',
          label: L10n.of(context).notesFromRecording(date),
          kind: WpLinkKind.page,
          onPressed: () {
            ref.read(historyOpenEntryProvider.notifier).set(entry.id);
            ref.read(activePageProvider.notifier).setPage('history');
          },
        ),
      ),
    );
  }
}
