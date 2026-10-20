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

/// "Add files" action and the import queue list, shown above the history
/// list. Imports run in the background; each row shows its state.
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        WpSpacing.md,
        WpSpacing.xs,
        WpSpacing.md,
        WpSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.historyImportDescription(_importFormats()),
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    color: WpColors.textMuted,
                  ),
                ),
              ),
              Semantics(
                identifier: 'history-import-add',
                child: WpButton(
                  key: const ValueKey('history-import-add'),
                  label: l10n.historyImportAddFiles,
                  variant: WpButtonVariant.secondary,
                  icon: LucideIcons.filePlus,
                  size: WpButtonSize.dense,
                  onPressed: _pickFiles,
                ),
              ),
            ],
          ),
          for (final message in rejectionText)
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
          if (jobs.isNotEmpty) ...[
            const SizedBox(height: WpSpacing.xs),
            Text(
              l10n.historyImportQueueTitle,
              style: TextStyle(
                fontSize: WpTypography.small,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
            for (final job in jobs) _ImportJobRow(job: job),
          ],
        ],
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
          if (job.progress != null)
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
      l10n.historyImportFailureDecoderUnavailable,
    ImportFailure.decodeFailed => l10n.historyImportFailureDecode,
    ImportFailure.inputLimitExceeded => l10n.historyImportFailureInputLimit,
    ImportFailure.ioError => l10n.historyImportFailureIo,
    ImportFailure.copyInterrupted => l10n.historyImportFailureCopyInterrupted,
    ImportFailure.transcriptionFailed => l10n.historyImportFailureTranscription,
    ImportFailure.saveFailed => l10n.historyImportFailureSave,
  };
}

/// The formats this platform imports, as shown to the user ("WAV, MP3").
String _importFormats() =>
    supportedImportExtensions().map((e) => e.toUpperCase()).join(', ');
