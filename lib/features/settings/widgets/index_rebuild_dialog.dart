/// "Rebuild index" (#668): rebuilds the search and the preview index from the
/// user data and shows the progress. The texts themselves are only read.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_progress_bar.dart';

/// Runs [HistoryDatabase.rebuildIndexes] in a dialog that stays open until
/// the rebuild has finished (or failed); only then can it be closed.
Future<void> showIndexRebuildDialog(
  BuildContext context,
  HistoryDatabase db,
) async {
  final l10n = L10n.of(context);
  final finished = ValueNotifier<bool>(false);
  try {
    await showWpDialog<void>(
      context: context,
      title: l10n.settingsIndexRebuildTitle,
      dismissible: false,
      content: _IndexRebuildProgressView(
        progress: db.rebuildIndexes(),
        onFinished: () => finished.value = true,
      ),
      actions: [
        WpDialogAction<void>(
          label: l10n.actionClose,
          testId: 'settings-index-rebuild-close',
          role: WpDialogActionRole.primary,
          enabledWhen: finished,
        ),
      ],
    );
  } finally {
    finished.dispose();
  }
}

class _IndexRebuildProgressView extends StatefulWidget {
  const _IndexRebuildProgressView({
    required this.progress,
    required this.onFinished,
  });

  final Stream<IndexRebuildProgress> progress;
  final VoidCallback onFinished;

  @override
  State<_IndexRebuildProgressView> createState() =>
      _IndexRebuildProgressViewState();
}

class _IndexRebuildProgressViewState extends State<_IndexRebuildProgressView> {
  StreamSubscription<IndexRebuildProgress>? _subscription;
  IndexRebuildProgress? _latest;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.progress.listen(
      (p) {
        if (mounted) setState(() => _latest = p);
      },
      onError: (Object _) {
        if (mounted) setState(() => _failed = true);
        widget.onFinished();
      },
      onDone: widget.onFinished,
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final p = _latest;
    final status = _failed
        ? l10n.settingsIndexRebuildFailed
        : switch (p?.phase) {
            null => l10n.settingsIndexRebuildStarting,
            IndexRebuildPhase.search => l10n.settingsIndexRebuildSearch(
              p!.done,
              p.total,
            ),
            IndexRebuildPhase.preview => l10n.settingsIndexRebuildPreview(
              p!.done,
              p.total,
            ),
            IndexRebuildPhase.done => l10n.settingsIndexRebuildDone,
          };
    final done = p?.phase == IndexRebuildPhase.done;
    return Column(
      key: const ValueKey('settings-index-rebuild-dialog'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.settingsIndexRebuildExplanation,
          style: TextStyle(
            color: WpColors.textSecondary,
            fontSize: WpTypography.body,
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        if (!_failed)
          ExcludeSemantics(
            child: WpProgressBar(
              key: const ValueKey('settings-index-rebuild-progress'),
              value: done ? 1 : p?.fraction,
            ),
          ),
        const SizedBox(height: WpSpacing.sm),
        // Phase changes and the end are read out; per-batch counts would
        // flood the screen reader, so the live text changes per phase only.
        Semantics(
          liveRegion: true,
          label: _failed
              ? status
              : switch (p?.phase) {
                  IndexRebuildPhase.done => status,
                  IndexRebuildPhase.preview =>
                    l10n.settingsIndexRebuildPreviewPhase,
                  _ => l10n.settingsIndexRebuildSearchPhase,
                },
          child: ExcludeSemantics(
            child: Text(
              status,
              key: const ValueKey('settings-index-rebuild-status'),
              style: TextStyle(
                color: _failed ? WpColors.error : WpColors.textPrimary,
                fontSize: WpTypography.body,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
