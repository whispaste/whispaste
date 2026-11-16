/// The icon of an app a recording went to, the same everywhere it appears
/// (overview, recordings list, detail, app lists in the settings).
///
/// Order: the system's own app icon → a category tile (terminal, browser, …)
/// → the "unknown app" tile. Tiles are drawn from theme tokens, so they follow
/// light, dark and marine; they show a generic glyph, never a brand.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/colors.dart';
import '../services/app_identity/app_category.dart';
import '../services/app_identity/app_identity_service.dart';

class WpAppIcon extends ConsumerWidget {
  const WpAppIcon({super.key, required this.identifier, this.size = 24});

  /// The identifier as stored (bundle id, exe name, WM_CLASS or app_id).
  final String identifier;

  /// Edge length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(appIdentityProvider(identifier)).value;
    final category = identity?.category ?? appCategoryFor(identifier);
    final tile = WpAppCategoryTile(category: category, size: size);
    final iconPath = identity?.iconPath;
    // Decorative: the app's name is always written next to it.
    if (iconPath == null) return ExcludeSemantics(child: tile);
    return Image.file(
      File(iconPath),
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => ExcludeSemantics(child: tile),
    );
  }
}

/// The tile for a [category]: a rounded square in the surface tone with a
/// line glyph. The unknown tile is quieter, so it never reads as a category.
class WpAppCategoryTile extends StatelessWidget {
  const WpAppCategoryTile({
    super.key,
    required this.category,
    required this.size,
  });

  final AppCategory category;
  final double size;

  static IconData glyphFor(AppCategory category) => switch (category) {
    AppCategory.terminal => LucideIcons.squareTerminal,
    AppCategory.browser => LucideIcons.globe,
    AppCategory.code => LucideIcons.codeXml,
    AppCategory.chat => LucideIcons.messageCircle,
    AppCategory.mail => LucideIcons.mail,
    AppCategory.notes => LucideIcons.fileText,
    AppCategory.office => LucideIcons.sheet,
    AppCategory.calendar => LucideIcons.calendar,
    AppCategory.design => LucideIcons.penTool,
    AppCategory.unknown => LucideIcons.appWindow,
  };

  @override
  Widget build(BuildContext context) {
    final unknown = category == AppCategory.unknown;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: WpColors.surfaceVariant,
        // A quarter of the edge keeps the tile's shape at every size.
        borderRadius: BorderRadius.circular(size / 4),
        border: Border.all(color: WpColors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: Icon(
        glyphFor(category),
        size: size * 0.58,
        color: unknown ? WpColors.textMuted : WpColors.textPrimary,
      ),
    );
  }
}

/// The readable name of [identifier]: the system's, once known, else the
/// cleaned identifier. For rows that show the name next to [WpAppIcon].
String watchAppName(WidgetRef ref, String identifier) =>
    ref.watch(appIdentityProvider(identifier)).value?.name ??
    cleanAppName(identifier);
