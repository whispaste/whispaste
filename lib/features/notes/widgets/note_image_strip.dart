/// Image attachments of the open note, as a strip above the editor (WP-31a).
///
/// Images are attachments, not body text: the strip only lists and removes
/// them. Nothing is shown while the note has none.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/data/database.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../data/notes_actions.dart';

const double _thumbnailExtent = 64;

/// Decode size in device pixels: the 64 dp thumbnail at 3x density.
const int _thumbnailPixels = 192;

class NoteImageStrip extends ConsumerWidget {
  const NoteImageStrip({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets =
        ref.watch(noteAssetsProvider(noteId)).value ?? const <NoteAsset>[];
    if (assets.isEmpty) return const SizedBox.shrink();

    final l10n = L10n.of(context);
    final store = ref.watch(noteAssetStoreProvider);
    return SizedBox(
      height: _thumbnailExtent + WpSpacing.sm,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
        itemCount: assets.length,
        separatorBuilder: (_, _) => const SizedBox(width: WpSpacing.sm),
        itemBuilder: (context, index) {
          final asset = assets[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Semantics(
                identifier: 'notes-editor-image-${asset.id}',
                child: ClipRRect(
                  borderRadius: WpRadius.borderSm,
                  child: Image(
                    key: ValueKey('notes-editor-image-${asset.id}'),
                    semanticLabel: l10n.notesImageFilesLabel,
                    // Decoded to thumbnail size, not to the file's own size: a
                    // 40 MP photo must not be fully decoded to show 64 dp.
                    image: ResizeImage(
                      // A stored path outside the image folder resolves to an
                      // empty file name, which fails to load and shows the
                      // broken-image icon below.
                      FileImage(
                        File(store.resolveAssetPath(asset.relativePath) ?? ''),
                      ),
                      width: _thumbnailPixels,
                      height: _thumbnailPixels,
                      policy: ResizeImagePolicy.fit,
                    ),
                    width: _thumbnailExtent,
                    height: _thumbnailExtent,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => SizedBox(
                      width: _thumbnailExtent,
                      height: _thumbnailExtent,
                      child: Icon(
                        LucideIcons.imageOff,
                        size: WpIconSize.md,
                        color: WpColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -WpSpacing.sm,
                right: -WpSpacing.sm,
                child: Semantics(
                  label: l10n.notesImageRemove,
                  button: true,
                  identifier: 'notes-editor-image-remove-${asset.id}',
                  child: IconButton(
                    key: ValueKey('notes-editor-image-remove-${asset.id}'),
                    tooltip: l10n.notesImageRemove,
                    onPressed: () =>
                        ref.read(notesActionsProvider).removeImage(asset),
                    icon: Icon(
                      LucideIcons.x,
                      size: WpIconSize.sm,
                      color: WpColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
