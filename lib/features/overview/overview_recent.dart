import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/first_steps/first_steps_notifier.dart';
import '../../core/data/database.dart';
import '../../core/data/history_providers.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/overview/overview_logic.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/toast.dart';
import '../../widgets/wp_text_link.dart';
import '../../widgets/wp_app_icon.dart';
import '../../widgets/wp_card.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_row_divider.dart';
import '../history/widgets/history_helpers.dart' show formatHistoryTime;
import 'overview_header.dart' show overviewHotkeyCaps;
import 'overview_navigation.dart';
import '../../widgets/wp_keycap.dart';

/// W6: the newest five recordings as one card of rows: a fixed time column,
/// the app slot, the text with the app it went to (when known), and the
/// actions. Copy and "more" stay visible, so reusing a text needs no precise
/// pointer move. The empty state names the hotkey.
class OverviewRecent extends ConsumerWidget {
  const OverviewRecent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final all = ref.watch(historyEntriesProvider).value ?? const [];
    final entries = overviewLatestRecordings(all);
    final empty = overviewRecentEmpty(
      all,
      saveHistory: ref.watch(
        settingsProvider.select((s) => s.value?.history.saveHistory ?? true),
      ),
    );
    return WpCard(
      key: const ValueKey('overview-recent'),
      title: l10n.overviewRecentTitle,
      titleTestId: 'overview-recent',
      trailing: WpTextLink(
        testID: 'overview-recent-all',
        label: l10n.overviewRecentAll,
        icon: LucideIcons.arrowRight,
        iconAfter: true,
        onPressed: () => overviewOpenTarget(ref, 'history'),
      ),
      // Rows carry a 16 px inset of their own, so their hover surface keeps a
      // margin to the card edge and their text lines up with the title.
      bodyPadding: empty != null
          ? null
          : const EdgeInsets.fromLTRB(
              WpSpacing.xs,
              WpSpacing.xs,
              WpSpacing.xs,
              WpSpacing.xs,
            ),
      child: empty != null
          ? _Empty(l10n: l10n, reason: empty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, entry) in entries.indexed) ...[
                  if (i > 0)
                    const WpRowDivider(
                      inset: EdgeInsets.symmetric(horizontal: WpSpacing.md),
                    ),
                  _RecentRow(
                    key: ValueKey('overview-recent-${entry.id}'),
                    entry: entry,
                  ),
                ],
              ],
            ),
    );
  }
}

class _Empty extends ConsumerWidget {
  const _Empty({required this.l10n, required this.reason});

  final L10n l10n;
  final OverviewRecentEmpty reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = WpTextStyles.rowTitle;
    final note = Text(
      l10n.overviewRecentLocalNote,
      style: TextStyle(fontSize: WpTypography.body, color: WpColors.textMuted),
    );
    final Widget body = switch (reason) {
      OverviewRecentEmpty.none => _hotkeyInvite(context, ref),
      OverviewRecentEmpty.putAway => Text(
        l10n.overviewRecentEmptyPutAway,
        style: style,
      ),
      OverviewRecentEmpty.notSaved => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        children: [
          Text(l10n.overviewRecentEmptyNotSaved, style: style),
          WpTextLink(
            testID: 'overview-recent-turn-on-saving',
            label: l10n.overviewRecentEmptyNotSavedAction,
            onPressed: () =>
                overviewOpenTarget(ref, 'settings:privacy-history-save'),
          ),
        ],
      ),
    };
    return Column(
      key: ValueKey('overview-recent-empty-${reason.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        body,
        // Where the recordings live, said where people look for them; not
        // with saving off, where nothing is kept at all.
        if (reason != OverviewRecentEmpty.notSaved) ...[
          const SizedBox(height: WpSpacing.xs),
          note,
        ],
      ],
    );
  }

  Widget _hotkeyInvite(BuildContext context, WidgetRef ref) {
    return KeyedSubtree(
      key: const ValueKey('overview-recent-empty'),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: WpSpacing.sm,
        runSpacing: WpSpacing.xs,
        children: [
          Text(l10n.overviewRecentEmptyBefore, style: WpTextStyles.rowTitle),
          for (final cap in overviewHotkeyCaps(ref, l10n))
            WpKeycap(label: cap.cap),
          Text(l10n.overviewRecentEmptyAfter, style: WpTextStyles.rowTitle),
        ],
      ),
    );
  }
}

class _RecentRow extends ConsumerStatefulWidget {
  const _RecentRow({super.key, required this.entry});

  final HistoryEntry entry;

  @override
  ConsumerState<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends ConsumerState<_RecentRow> {
  bool _hovered = false;
  bool _focused = false;

  void _copy() {
    final l10n = L10n.of(context);
    Clipboard.setData(ClipboardData(text: widget.entry.content));
    ref.read(firstStepsNotifierProvider.notifier).recordingCopied();
    WpToast.show(
      context,
      message: l10n.historyCopiedToClipboard,
      type: WpToastType.info,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final entry = widget.entry;
    final text = entry.content.trim().isEmpty ? entry.title : entry.content;
    final target = entry.targetApp?.trim();
    final meta = WpTextStyles.rowNote;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            color: _hovered || _focused ? WpColors.hover : Colors.transparent,
            borderRadius: WpRadius.borderSm,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: Text(formatHistoryTime(entry.timestamp), style: meta),
              ),
              const SizedBox(width: WpSpacing.md),
              // Without a known target the quiet "unknown" tile keeps the
              // column, so the texts of all rows start at the same edge.
              WpAppIcon(identifier: target ?? '', size: WpIconSize.xl),
              const SizedBox(width: WpSpacing.md),
              // The text opens the recording: a row is clicked where people read
              // it, the "more" button stays for the same action.
              Expanded(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => overviewOpenRecording(ref, entry.id),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: WpTextStyles.rowTitle,
                        ),
                        if (target != null && target.isNotEmpty)
                          Text(watchAppName(ref, target), style: meta),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: WpSpacing.md),
              WpIconButton.ghost(
                testId: 'overview-recent-copy-${entry.id}',
                icon: LucideIcons.copy,
                tooltip: l10n.overviewRecentCopy,
                onPressed: _copy,
              ),
              const SizedBox(width: WpSpacing.xs),
              WpIconButton.ghost(
                testId: 'overview-recent-open-${entry.id}',
                icon: LucideIcons.ellipsis,
                tooltip: l10n.overviewRecentOpen,
                onPressed: () => overviewOpenRecording(ref, entry.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
