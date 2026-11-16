import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';

/// What an editor's status line says about saving (#634, #1498). One set of
/// states for Recordings, Notes and Snippets.
enum WpSaveStatus {
  /// Nothing typed since the editor opened: the line shows no status.
  idle,

  /// A write is pending or running.
  saving,

  /// The text on screen is what is stored.
  saved,

  /// The last write failed; the text is kept and retried.
  failed,

  /// The text is not stored because it is not valid (snippets); the inline
  /// notice above the editor says why.
  invalid,
}

/// The save status as drawn first in `WpTextEditor`'s status line.
///
/// Semantics identifier `<testId>-save-status`; the key
/// `<testId>-save-status-<state>` carries the state for tests, so they never
/// read the wording.
class WpSaveStatusLabel extends StatelessWidget {
  const WpSaveStatusLabel({
    super.key,
    required this.testId,
    required this.status,
  });

  /// The editor's test id.
  final String testId;
  final ValueListenable<WpSaveStatus> status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ValueListenableBuilder<WpSaveStatus>(
      valueListenable: status,
      builder: (context, value, _) {
        if (value == WpSaveStatus.idle) return const SizedBox.shrink();
        final problem =
            value == WpSaveStatus.failed || value == WpSaveStatus.invalid;
        return Semantics(
          key: ValueKey('$testId-save-status-${value.name}'),
          identifier: '$testId-save-status',
          // Announced only when the text is not stored; a calm "Saved" after
          // every pause in typing would interrupt a screen reader.
          liveRegion: problem,
          child: Text(
            switch (value) {
              WpSaveStatus.idle => '',
              WpSaveStatus.saving => l10n.historyTranscriptSaving,
              WpSaveStatus.saved => l10n.historyTranscriptDraftSaved,
              WpSaveStatus.failed ||
              WpSaveStatus.invalid => l10n.historyTranscriptNotSaved,
            },
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: problem ? WpColors.error : WpColors.textMuted,
            ),
            maxLines: problem ? null : 1,
            overflow: problem ? TextOverflow.visible : TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}
