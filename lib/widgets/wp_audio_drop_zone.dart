import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../core/l10n/generated/app_localizations.dart';
import '../core/navigation/page_state.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../services/audio/import/audio_drop_intake.dart';
import '../services/audio/import/audio_file_decoder.dart';
import '../services/audio/import/audio_import_providers.dart';
import 'toast.dart';

/// Whole-window drop target for audio files. Dropped files take the same path
/// as "Transcribe file…": they go to the history page's import queue. The
/// drop is an addition only; the menu and the file picker stay complete.
///
/// The overlay ignores pointers, so the window below keeps working while a
/// drag hovers over it.
class WpAudioDropZone extends ConsumerStatefulWidget {
  const WpAudioDropZone({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WpAudioDropZone> createState() => _WpAudioDropZoneState();
}

class _WpAudioDropZoneState extends ConsumerState<WpAudioDropZone> {
  bool _hovering = false;

  void _setHovering(bool value) {
    if (!mounted || _hovering == value) return;
    setState(() => _hovering = value);
  }

  void _onDone(DropDoneDetails details) {
    _setHovering(false);
    unawaited(_handleDrop(details));
  }

  /// Checks the files off the UI isolate, then queues the accepted ones.
  Future<void> _handleDrop(DropDoneDetails details) async {
    final split = await splitAudioDrop([
      for (final f in details.files) f.path,
    ], extensions: supportedImportExtensions().toSet());
    if (!mounted) return;
    if (split.rejected.isNotEmpty && mounted) {
      _announceRejections(split.rejected);
    }
    if (split.accepted.isEmpty) return;
    ref.read(activePageProvider.notifier).setPage('history');
    unawaited(
      ref.read(audioImportQueueProvider.notifier).addFiles(split.accepted),
    );
  }

  void _announceRejections(List<AudioDropRejected> rejected) {
    final l10n = L10n.of(context);
    final byReason = <AudioDropRejection, List<String>>{};
    for (final r in rejected) {
      byReason.putIfAbsent(r.reason, () => []).add(p.basename(r.path));
    }
    for (final entry in byReason.entries) {
      final names = entry.value.join(', ');
      final message = switch (entry.key) {
        AudioDropRejection.folder => l10n.audioDropRejectedFolder(names),
        AudioDropRejection.notFound => l10n.audioDropRejectedNotFound(names),
        AudioDropRejection.notRegularFile => l10n.audioDropRejectedNotRegular(
          names,
        ),
        AudioDropRejection.reservedName => l10n.audioDropRejectedReservedName(
          names,
        ),
        AudioDropRejection.tooLarge => l10n.audioDropRejectedTooLarge(names),
        AudioDropRejection.unsupportedFormat => l10n.audioDropRejectedFormat(
          names,
          supportedImportExtensions().map((e) => e.toUpperCase()).join(', '),
        ),
      };
      WpToast.show(context, message: message, type: WpToastType.warning);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned.fill(
          child: DropTarget(
            onDragEntered: (_) => _setHovering(true),
            onDragExited: (_) => _setHovering(false),
            onDragDone: _onDone,
            child: IgnorePointer(
              child: _hovering
                  ? _DropOverlay(hint: L10n.of(context).audioDropHint)
                  : const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'audio-drop-overlay',
      liveRegion: true,
      label: hint,
      child: Container(
        key: const ValueKey('audio-drop-overlay'),
        color: WpColors.accentSubtle,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(WpSpacing.xl),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.xl,
            vertical: WpSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: WpColors.surfaceElevated,
            borderRadius: BorderRadius.circular(WpRadius.lg),
            border: Border.all(color: WpColors.accent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.fileAudio,
                size: WpIconSize.xl,
                color: WpColors.accent,
              ),
              const SizedBox(height: WpSpacing.sm),
              Semantics(
                identifier: 'audio-drop-hint',
                child: Text(
                  hint,
                  key: const ValueKey('audio-drop-hint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    fontWeight: FontWeight.w600,
                    color: WpColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
