import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import 'audio_import_panel.dart';

/// Lets audio files dragged from the file manager onto the history page start
/// an import, the same way as "Add files" (XP-5-12). While files hover over
/// the page it shows where they will go.
class AudioImportDropZone extends ConsumerStatefulWidget {
  const AudioImportDropZone({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AudioImportDropZone> createState() =>
      _AudioImportDropZoneState();
}

class _AudioImportDropZoneState extends ConsumerState<AudioImportDropZone> {
  var _hovering = false;

  void _setHovering(bool value) {
    if (_hovering != value) setState(() => _hovering = value);
  }

  void _onDrop(DropDoneDetails details) {
    _setHovering(false);
    final paths = [for (final f in details.files) f.path];
    if (paths.isEmpty) return;
    unawaited(importAudioFiles(ref, paths));
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => _setHovering(true),
      onDragExited: (_) => _setHovering(false),
      onDragDone: _onDrop,
      child: Stack(
        children: [
          widget.child,
          if (_hovering)
            const Positioned.fill(
              child: IgnorePointer(child: _DropHint(key: dropHintKey)),
            ),
        ],
      ),
    );
  }
}

/// Key of the hint shown while files hover over the page.
const dropHintKey = ValueKey('history-import-drop-zone');

class _DropHint extends StatelessWidget {
  const _DropHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'history-import-drop-zone',
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(WpSpacing.sm),
        decoration: BoxDecoration(
          color: WpColors.surface.withValues(alpha: 0.92),
          borderRadius: WpRadius.borderLg,
          border: Border.all(color: WpColors.accent, width: 2),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(WpSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileAudio,
              size: WpIconSize.xl,
              color: WpColors.accent,
            ),
            const SizedBox(height: WpSpacing.sm),
            Text(
              L10n.of(context).historyImportDropHere,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w600,
                color: WpColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
