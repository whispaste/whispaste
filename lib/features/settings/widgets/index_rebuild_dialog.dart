/// "Rebuild index" (#668): rebuilds the search and the preview index from the
/// user data and shows the progress. The texts themselves are only read.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/accessibility/announce.dart';
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
  String? _announced;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _announcePhase());
    _subscription = widget.progress.listen(
      (p) {
        if (!mounted) return;
        setState(() => _latest = p);
        _announcePhase();
      },
      onError: (Object _) {
        if (mounted) {
          setState(() => _failed = true);
          _announcePhase();
        }
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

  /// Phase changes and the end are read out once each; per-batch counts would
  /// flood the screen reader. An explicit announcement instead of a live
  /// region, because VoiceOver on macOS does not read Flutter live-region
  /// changes (native check, #668).
  void _announcePhase() {
    if (!mounted) return;
    final l10n = L10n.of(context);
    final message = _failed
        ? l10n.settingsIndexRebuildFailed
        : switch (_latest?.phase) {
            IndexRebuildPhase.done => l10n.settingsIndexRebuildDone,
            IndexRebuildPhase.preview => l10n.settingsIndexRebuildPreviewPhase,
            _ => l10n.settingsIndexRebuildSearchPhase,
          };
    if (message == _announced) return;
    _announced = message;
    announce(View.of(context), message, Directionality.of(context));
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
        Text(
          status,
          key: const ValueKey('settings-index-rebuild-status'),
          style: TextStyle(
            color: _failed ? WpColors.error : WpColors.textPrimary,
            fontSize: WpTypography.body,
          ),
        ),
      ],
    );
  }
}
