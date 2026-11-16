import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';

// ---------------------------------------------------------------------------
// Head of the favourites section of the note list (#830). Same look as the
// date headers, plus a chevron: the whole line folds and unfolds the section.
// ---------------------------------------------------------------------------

class NotesFavoritesHeader extends StatefulWidget {
  const NotesFavoritesHeader({
    super.key,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<NotesFavoritesHeader> createState() => _NotesFavoritesHeaderState();
}

class _NotesFavoritesHeaderState extends State<NotesFavoritesHeader> {
  final FocusNode _focus = FocusNode(debugLabel: 'notes-favorites-toggle');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final color = WpColors.textMuted;
    final title = '${widget.label} (${widget.count})';
    return Padding(
      padding: const EdgeInsets.only(top: WpSpacing.xs),
      // One node: the title, the count and the state ("collapsed" / "expanded")
      // read as a single button; `header` keeps it reachable by heading
      // navigation like the date headers.
      child: Semantics(
        header: true,
        button: true,
        expanded: !widget.collapsed,
        identifier: 'notes-favorites-toggle',
        label: title,
        onTapHint: widget.collapsed
            ? l10n.notesFavoritesExpand
            : l10n.notesFavoritesCollapse,
        excludeSemantics: true,
        child: WpFocusRing(
          focusNode: _focus,
          child: InkWell(
            onTap: widget.onToggle,
            focusNode: _focus,
            borderRadius: WpRadius.borderSm,
            focusColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WpLayout.minTouchTarget,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: WpTypography.caption,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: color,
                      ),
                    ),
                  ),
                  Icon(
                    !widget.collapsed
                        ? LucideIcons.chevronDown
                        : (Directionality.of(context) == TextDirection.rtl
                              ? LucideIcons.chevronLeft
                              : LucideIcons.chevronRight),
                    size: WpIconSize.sm,
                    color: color,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
