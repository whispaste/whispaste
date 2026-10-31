import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/first_steps/first_steps.dart';
import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_row_divider.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_link.dart';
import '../../widgets/wp_progress_bar.dart';

/// The "Erste Schritte" card on the Übersicht page, right under the status
/// line. Hidden while a dictation runs, after it is closed, and once the
/// success state has passed (see `first_steps_notifier.dart`).
///
/// The only motion is the check mark drawing itself in when a step is done;
/// with reduced motion it appears at once.
class FirstStepsCard extends ConsumerWidget {
  const FirstStepsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(firstStepsViewProvider);
    if (!view.visible) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    final allDone = firstStepsAllDone(view.done);
    final rows = <Widget>[
      for (final (i, item) in FirstStepsItem.values.indexed) ...[
        if (i > 0)
          const WpRowDivider(
            inset: EdgeInsetsDirectional.only(
              start: _CheckMark.size + WpSpacing.md,
            ),
          ),
        _FirstStepsItemRow(item: item, done: view.done.contains(item)),
      ],
    ];
    return WpCard(
      key: const ValueKey('home-first-steps'),
      title: l10n.firstStepsTitle,
      subtitle: l10n.firstStepsProgress(view.done.length, kFirstStepsItemCount),
      trailing: WpIconButton.ghost(
        testId: 'home-first-steps-close',
        icon: LucideIcons.x,
        tooltip: l10n.actionClose,
        onPressed: () =>
            ref.read(firstStepsNotifierProvider.notifier).dismiss(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WpProgressBar(
            key: const ValueKey('home-first-steps-progress'),
            value: view.done.length / kFirstStepsItemCount,
          ),
          const SizedBox(height: WpSpacing.xs),
          if (allDone)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.firstStepsComplete,
                  key: const ValueKey('home-first-steps-complete'),
                  style: WpTextStyles.rowTitle,
                ),
              ),
            )
          else
            ...rows,
        ],
      ),
    );
  }
}

/// One item: a check mark, its title and, while open, the action that leads
/// to the place where the step happens.
class _FirstStepsItemRow extends ConsumerWidget {
  const _FirstStepsItemRow({required this.item, required this.done});

  final FirstStepsItem item;
  final bool done;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final (title, action) = switch (item) {
      FirstStepsItem.firstPaste => (
        l10n.firstStepsItemPasteTitle,
        l10n.firstStepsItemPasteAction,
      ),
      FirstStepsItem.findAndCopy => (
        l10n.firstStepsItemCopyTitle,
        l10n.firstStepsItemCopyAction,
      ),
      FirstStepsItem.personalize => (
        l10n.firstStepsItemPersonalizeTitle,
        l10n.firstStepsItemPersonalizeAction,
      ),
      FirstStepsItem.noteDictation => (
        l10n.firstStepsItemNoteTitle,
        l10n.firstStepsItemNoteAction,
      ),
    };
    final style = WpTextStyles.rowTitle;
    return Semantics(
      container: true,
      checked: done,
      label: title,
      child: ConstrainedBox(
        key: ValueKey('home-first-steps-item-${item.id}'),
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
          child: Row(
            children: [
              _CheckMark(done: done),
              const SizedBox(width: WpSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: style.copyWith(
                    color: done ? WpColors.textMuted : null,
                    decoration: done ? TextDecoration.lineThrough : null,
                    decorationColor: WpColors.textMuted,
                  ),
                ),
              ),
              if (!done) ...[
                const SizedBox(width: WpSpacing.xl),
                WpTextLink(
                  testID: 'home-first-steps-item-${item.id}-action',
                  label: action,
                  icon: LucideIcons.arrowRight,
                  iconAfter: true,
                  onPressed: () => openFirstStepsTarget(ref, item),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The state mark of one item: an empty ring while open, a filled accent disc
/// with an ink check once done. The check draws itself in from the leading
/// edge when it appears.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.done});

  final bool done;

  static const double size = WpIconSize.md;

  @override
  Widget build(BuildContext context) {
    if (!done) {
      return Icon(LucideIcons.circle, size: size, color: WpColors.textMuted);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WpMotion.durationFor(
        context,
        const Duration(milliseconds: 250),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: WpColors.accent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: ClipRect(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: t,
            child: Icon(
              LucideIcons.check,
              size: size * 0.7,
              color: WpColors.onAction,
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the place where an item's step happens: the dictation shortcut in
/// Settings, the Aufnahmen page, the dictionary, or the notes.
void openFirstStepsTarget(WidgetRef ref, FirstStepsItem item) {
  final pages = ref.read(activePageProvider.notifier);
  switch (item) {
    case FirstStepsItem.firstPaste:
      _openSettingsRow(ref, 'general-hotkey-dictation');
    case FirstStepsItem.findAndCopy:
      pages.setPage('history');
    case FirstStepsItem.personalize:
      pages.setPage('replacements');
    case FirstStepsItem.noteDictation:
      pages.setPage('notes');
  }
}

void _openSettingsRow(WidgetRef ref, String rowId) {
  ref.read(settingsScrollTargetProvider.notifier).set(rowId);
  ref.read(activePageProvider.notifier).setPage('settings');
}
