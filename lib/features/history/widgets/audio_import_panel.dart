import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/audio/import/audio_import_providers.dart';
import '../../../services/audio/import/audio_file_decoder.dart';
import '../../../services/audio/import/audio_import_queue.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_icon_button.dart';
import '../linux_decoder_hint.dart';
import 'history_head.dart';
import 'history_helpers.dart';

final _log = AppLogger('AudioImportPanel');

/// Refusals of the last add, from the file dialog or a drop, shown under the
/// add button until the next add.
class AudioImportRejectionsNotifier extends Notifier<List<ImportRejection>> {
  @override
  List<ImportRejection> build() => const [];

  void set(List<ImportRejection> rejections) => state = rejections;
}

final audioImportRejectionsProvider =
    NotifierProvider<AudioImportRejectionsNotifier, List<ImportRejection>>(
      AudioImportRejectionsNotifier.new,
    );

/// Queues [paths] for import, the one path for the file dialog and a drop.
/// Files with an extension the importer cannot read are refused at once
/// (a drop is not filtered by the dialog's type list); folders and missing
/// files are refused by the queue.
Future<void> importAudioFiles(
  WidgetRef ref,
  List<String> paths, {
  List<String>? extensions,
}) async {
  final allowed = (extensions ?? supportedImportExtensions()).toSet();
  final accepted = <String>[];
  final refused = <ImportRejection>[];
  for (final path in paths) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (FileSystemEntity.isDirectorySync(path) || allowed.contains(ext)) {
      accepted.add(path);
    } else {
      refused.add(
        ImportRejection(
          path: path,
          reason: ImportRejectionReason.unsupportedType,
        ),
      );
    }
  }
  final rejections = ref.read(audioImportRejectionsProvider.notifier)
    ..set(refused);
  if (accepted.isEmpty) return;
  // Completes once these jobs have run; the queue's own refusals (folders,
  // missing files) are known by then.
  final result = await ref
      .read(audioImportQueueProvider.notifier)
      .addFiles(accepted);
  if (result.rejections.isNotEmpty) {
    rejections.set([...refused, ...result.rejections]);
  }
}

/// "Add files" action and the import queue, shown above the history list.
/// Imports run in the background. The queue is one summary line that expands
/// on demand.
class AudioImportPanel extends ConsumerStatefulWidget {
  const AudioImportPanel({super.key});

  @override
  ConsumerState<AudioImportPanel> createState() => _AudioImportPanelState();
}

class _AudioImportPanelState extends ConsumerState<AudioImportPanel> {
  @override
  void initState() {
    super.initState();
    // A request made from the tray before this page was shown is taken once
    // the panel is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _takePickRequest();
    });
  }

  void _takePickRequest() {
    if (ref.read(audioImportPickRequestProvider.notifier).takeRequest()) {
      unawaited(_pickFiles());
    }
  }

  Future<void> _pickFiles() async {
    // A second request while the dialog is open must not open a second one.
    final picker = ref.read(audioImportPickerOpenProvider.notifier);
    if (!picker.tryOpen()) return;
    final List<XFile> files;
    try {
      // Audio file types the import accepts. Folders are rejected by the queue.
      final audioTypeGroup = XTypeGroup(
        label: L10n.of(context).historyImportAudioLabel,
        extensions: supportedImportExtensions(),
      );
      files = await openFiles(acceptedTypeGroups: [audioTypeGroup]);
    } on Object catch (e, st) {
      _log.warning('The file dialog failed', e, st);
      // Said, not swallowed: drag and drop still works (UIA-HIS-30).
      if (mounted) {
        WpToast.show(
          context,
          message: L10n.of(context).historyImportDialogFailed,
          type: WpToastType.error,
        );
      }
      return;
    } finally {
      // Only the dialog is guarded. Files picked earlier may still be queued.
      picker.close();
    }
    if (files.isEmpty || !mounted) return;
    await importAudioFiles(ref, [for (final f in files) f.path]);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    ref.listen<DateTime?>(audioImportPickRequestProvider, (_, requestedAt) {
      if (requestedAt != null) _takePickRequest();
    });
    final jobs = ref.watch(audioImportQueueProvider);
    final rejectionText = [
      for (final r in ref.watch(audioImportRejectionsProvider))
        '${p.basename(r.path)}: ${switch (r.reason) {
          ImportRejectionReason.folder => l10n.historyImportRejectedFolder,
          ImportRejectionReason.notFound => l10n.historyImportRejectedNotFound,
          ImportRejectionReason.unsupportedType => l10n.historyImportRejectedType(_importFormats()),
          ImportRejectionReason.notRegularFile => l10n.historyImportRejectedNotRegularFile,
          ImportRejectionReason.reservedName => l10n.historyImportRejectedReservedName,
          ImportRejectionReason.tooLarge => l10n.historyImportRejectedTooLarge,
        }}',
    ];

    // Compact mode (a window below 780 px, or text scale 2.0): this row is
    // dropped. The description moves into the import dialog, and the add
    // action becomes an icon in the status line (UX-077, compact mode).
    final compact = historyHeadIsShort(context);
    final expanded = ref
        .watch(historyHeadOpenProvider)
        .contains(HistoryHeadSection.import);
    final description = Text(
      l10n.historyImportDescription(_importFormats()),
      style: TextStyle(fontSize: WpTypography.small, color: WpColors.textMuted),
    );
    final addButton = Semantics(
      identifier: 'history-import-add',
      child: WpButton(
        key: const ValueKey('history-import-add'),
        label: l10n.historyImportAddFiles,
        variant: WpButtonVariant.secondary,
        icon: LucideIcons.filePlus,
        size: WpButtonSize.dense,
        onPressed: _pickFiles,
      ),
    );
    final header = Row(
      children: [
        Expanded(child: description),
        addButton,
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        0,
        WpSpacing.md,
        WpSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!compact) header,
          // Refusals are one line each. At most kHistoryInlineRows show here;
          // the rest sit in a dialog, so a large drop cannot push the list
          // out of its share of the pane (UX-091).
          for (final message in rejectionText.take(kHistoryInlineRows))
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Text(
                message,
                key: const ValueKey('history-import-rejection'),
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: WpColors.textPrimary,
                ),
              ),
            ),
          if (rejectionText.length > kHistoryInlineRows)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Semantics(
                identifier: 'history-import-rejections-show-all',
                child: WpButton(
                  key: const ValueKey('history-import-rejections-show-all'),
                  label: l10n.historyShowAll,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: () => showHistoryHeadDialog(
                    context: context,
                    title: l10n.historyImportRejectionsTitle,
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final message in rejectionText)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: WpSpacing.xs,
                              ),
                              child: Text(
                                message,
                                style: TextStyle(
                                  fontSize: WpTypography.small,
                                  color: WpColors.textPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    closeLabel: l10n.actionClose,
                  ),
                ),
              ),
            ),
          if (jobs.isNotEmpty && expanded && !historyHeadIsShort(context)) ...[
            for (final job in jobs.take(kHistoryInlineRows))
              _ImportJobRow(job: job),
            if (jobs.length > kHistoryInlineRows)
              Padding(
                padding: const EdgeInsets.only(top: WpSpacing.xs),
                child: WpButton(
                  key: const ValueKey('history-import-show-all'),
                  label: l10n.historyShowAll,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: () => showImportDialog(context, ref),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Opens the queue in a dialog: the short-window form of the expanded queue
/// (with the description the compact header no longer shows), and "Show all"
/// on a tall window.
Future<void> showImportDialog(BuildContext context, WidgetRef ref) {
  final l10n = L10n.of(context);
  return showHistoryHeadDialog(
    context: context,
    title: l10n.historyImportQueueSummary(
      ref.read(audioImportQueueProvider).length,
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.historyImportDescription(_importFormats()),
          style: TextStyle(
            fontSize: WpTypography.small,
            color: WpColors.textMuted,
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        const ImportAllJobs(),
      ],
    ),
    closeLabel: l10n.actionClose,
  );
}

/// Every queue row, for the dialog. Scrolls inside the dialog.
class ImportAllJobs extends ConsumerWidget {
  const ImportAllJobs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(audioImportQueueProvider);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.6,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final job in jobs) _ImportJobRow(job: job)],
        ),
      ),
    );
  }
}

class _ImportJobRow extends ConsumerWidget {
  const _ImportJobRow({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final canCancel = !job.isFinished;
    final canRetry =
        job.status == ImportStatus.failed ||
        job.status == ImportStatus.cancelled;

    return Padding(
      key: ValueKey('history-import-job-${job.id}'),
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  job.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: WpColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              Text(
                _statusLabel(l10n, job.status),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.textMuted,
                ),
              ),
              if (canCancel)
                WpIconButton(
                  key: ValueKey('history-import-cancel-${job.id}'),
                  icon: LucideIcons.x,
                  tooltip: l10n.historyImportCancel,
                  onPressed: () => ref
                      .read(audioImportQueueProvider.notifier)
                      .cancel(job.id),
                ),
              if (canRetry)
                WpIconButton(
                  key: ValueKey('history-import-retry-${job.id}'),
                  icon: LucideIcons.rotateCw,
                  tooltip: l10n.historyImportRetry,
                  onPressed: () =>
                      ref.read(audioImportQueueProvider.notifier).retry(job.id),
                ),
            ],
          ),
          if (job.status == ImportStatus.transcribing)
            _TranscribeProgress(job: job)
          else if (job.progress != null)
            LinearProgressIndicator(value: job.progress),
          if (job.failure != null)
            Text(
              _failureLabel(l10n, job.failure!),
              style: TextStyle(
                fontSize: WpTypography.caption,
                color: WpColors.textPrimary,
              ),
            ),
        ],
      ),
    );
  }

  // loam-ignore: code-duplicates – two parallel enum-to-text switches, kept side by side on purpose
  static String _statusLabel(L10n l10n, ImportStatus status) =>
      switch (status) {
        ImportStatus.queued => l10n.historyImportStatusQueued,
        ImportStatus.copying => l10n.historyImportStatusCopying,
        ImportStatus.decoding => l10n.historyImportStatusDecoding,
        ImportStatus.transcribing => l10n.historyImportStatusTranscribing,
        ImportStatus.done => l10n.historyImportStatusDone,
        ImportStatus.failed => l10n.historyImportStatusFailed,
        ImportStatus.cancelled => l10n.historyImportStatusCancelled,
      };

  static String _failureLabel(
    L10n l10n,
    ImportFailure failure,
  ) => switch (failure) {
    ImportFailure.copyFailed => l10n.historyImportFailureCopy,
    ImportFailure.unsupportedFormat => l10n.historyImportFailureUnsupported,
    ImportFailure.decoderUnavailable =>
      Platform.isLinux
          ? _linuxDecoderLabel(l10n)
          : l10n.historyImportFailureDecoderUnavailable,
    ImportFailure.decodeFailed => l10n.historyImportFailureDecode,
    ImportFailure.inputLimitExceeded => l10n.historyImportFailureInputLimit,
    ImportFailure.ioError => l10n.historyImportFailureIo,
    ImportFailure.copyInterrupted => l10n.historyImportFailureCopyInterrupted,
    ImportFailure.transcriptionFailed => l10n.historyImportFailureTranscription,
    ImportFailure.saveFailed => l10n.historyImportFailureSave,
  };

  /// On Linux the only compressed format without a built-in decoder is
  /// M4A/AAC (GStreamer). The hint depends on the package format: apt only
  /// works for the .deb and the tarball, Flatpak and Snap have their own text
  /// (PAR-040).
  static String _linuxDecoderLabel(L10n l10n) => switch (linuxDecoderHintFrom(
    Platform.environment,
  )) {
    LinuxDecoderHint.apt => l10n.historyImportFailureDecoderUnavailableLinux,
    LinuxDecoderHint.flatpak =>
      l10n.historyImportFailureDecoderUnavailableFlatpak,
    LinuxDecoderHint.snap => l10n.historyImportFailureDecoderUnavailableSnap,
  };
}

/// Progress line of a transcribing job. A determinate bar with the percentage
/// when the engine reports one; otherwise an indeterminate bar and the time
/// since the step started. No percentage or time remaining is ever guessed.
class _TranscribeProgress extends ConsumerStatefulWidget {
  const _TranscribeProgress({required this.job});

  final ImportJob job;

  @override
  ConsumerState<_TranscribeProgress> createState() =>
      _TranscribeProgressState();
}

class _TranscribeProgressState extends ConsumerState<_TranscribeProgress> {
  // Redraws the elapsed time once a second while no engine value is known.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final job = widget.job;
    final fraction = job.progress;
    if (fraction != null) {
      final percent = (fraction * 100).round();
      final text = l10n.historyImportPercent(percent);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            value: text,
            child: LinearProgressIndicator(
              key: ValueKey('history-import-progress-${job.id}'),
              value: fraction,
            ),
          ),
          Text(
            text,
            key: ValueKey('history-import-percent-${job.id}'),
            style: TextStyle(
              fontSize: WpTypography.caption,
              color: WpColors.textMuted,
            ),
          ),
        ],
      );
    }
    final since = job.transcribingSince;
    final elapsed = since == null
        ? Duration.zero
        : ref.read(audioImportClockProvider)().difference(since);
    final text = l10n.historyImportElapsed(_formatElapsed(elapsed));
    // Reduce motion: no moving bar. The elapsed time alone says the step runs.
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!reduceMotion)
          Semantics(
            value: text,
            child: LinearProgressIndicator(
              key: ValueKey('history-import-progress-${job.id}'),
            ),
          ),
        Text(
          text,
          key: ValueKey('history-import-elapsed-${job.id}'),
          style: TextStyle(
            fontSize: WpTypography.caption,
            color: WpColors.textMuted,
          ),
        ),
      ],
    );
  }
}

/// `m:ss`, or `h:mm:ss` from one hour on. Negative durations show as zero.
String _formatElapsed(Duration elapsed) {
  final total = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${two(minutes)}:${two(seconds)}'
      : '$minutes:${two(seconds)}';
}

/// The formats this platform imports, as shown to the user ("WAV, MP3").
String _importFormats() =>
    supportedImportExtensions().map((e) => e.toUpperCase()).join(', ');
