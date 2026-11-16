/// The one row focus mode keeps above the editor (#669): the paragraph-focus
/// switch and the way out. Everything else of the note — title, tools, menu —
/// stays in the editor panel below, so no tool is lost while writing.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/page_shell.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_filter_chip.dart';
import '../data/writing_focus.dart';

class WritingFocusBar extends StatelessWidget {
  const WritingFocusBar({
    super.key,
    required this.paragraphFocus,
    required this.onToggleParagraphFocus,
    required this.onExit,
  });

  final bool paragraphFocus;
  final VoidCallback onToggleParagraphFocus;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Semantics(
      identifier: 'notes-focus-bar',
      container: true,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          WpPageFrame.inset,
          WpSpacing.xs,
          WpPageFrame.inset,
          WpSpacing.xs,
        ),
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: WpSpacing.xs,
          runSpacing: WpSpacing.xxs,
          children: [
            WpFilterChip(
              testId: 'notes-focus-paragraph-toggle',
              label: l10n.notesParagraphFocus,
              icon: LucideIcons.textCursor,
              isActive: paragraphFocus,
              onTap: onToggleParagraphFocus,
            ),
            WpButton(
              testId: 'notes-focus-exit',
              label: l10n.notesFocusModeExit,
              semanticsLabel:
                  '${l10n.notesFocusModeExit}, '
                  '${writingFocusShortcutLabel(l10n)}',
              icon: LucideIcons.minimize2,
              variant: WpButtonVariant.ghost,
              size: WpButtonSize.dense,
              onPressed: onExit,
            ),
          ],
        ),
      ),
    );
  }
}
