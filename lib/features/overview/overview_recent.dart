import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import '../../services/audio/playback/recording_playback.dart';
import '../../widgets/wp_app_icon.dart';
import '../../widgets/wp_icon_button.dart';
import '../history/widgets/history_helpers.dart' show formatHistoryTime;
import 'overview_header.dart' show overviewHotkeyCaps;
import 'overview_navigation.dart';
import 'overview_rows.dart';
import '../../widgets/wp_keycap.dart';
import '../../widgets/wp_copy_feedback.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/wp_text_link.dart';

/// Entry id → path of the retained audio, for the rows of [OverviewRecent]
/// that can be played (#170): one watched query for all five rows, rebuilt
/// only when the row set changes. Files gone from disk (retention sweep,
/// orphaned rows) are left out, so a row never offers a dead "Listen".
final overviewRecentAudioProvider = StreamProvider<Map<String, String>>((ref) {
  final ids = ref.watch(
    latestRecordingsProvider.select(
      (all) => [
        for (final e in overviewLatestRecordings(all.value ?? const [])) e.id,
      ].join('\n'),
    ),
  );
  if (ids.isEmpty) return Stream.value(const {});
  return ref
      .watch(historyDatabaseProvider)
      .watchLatestAudioPaths(ids.split('\n'))
      .asyncMap((paths) async {
        final existing = <String, String>{};
        for (final MapEntry(:key, :value) in paths.entries) {
          if (await File(value).exists()) existing[key] = value;
        }
        return existing;
      });
});

/// W6: the newest five recordings as one card of rows: a time column that
/// grows with the text size, the app slot, the text with the app it went to
/// (when known), and the actions. Copy and "more" stay visible, so reusing a
/// text needs no precise pointer move. The empty state names the hotkey.
class OverviewRecent extends ConsumerWidget {
  const OverviewRecent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final latest = ref.watch(latestRecordingsProvider).value ?? const [];
    final entries = overviewLatestRecordings(latest);
    final empty = overviewRecentEmpty(
      latest,
      saveHistory: ref.watch(
        settingsProvider.select((s) => s.value?.history.saveHistory ?? true),
      ),
    );
    return OverviewRowsCard(
      key: const ValueKey('overview-recent'),
      title: l10n.overviewRecentTitle,
      testId: 'overview-recent',
      allLabel: l10n.overviewRecentAll,
      onAll: () => overviewOpenTarget(ref, 'history'),
      empty: empty != null ? _Empty(l10n: l10n, reason: empty) : null,
      rows: [
        for (final entry in entries)
          _RecentRow(
            key: ValueKey('overview-recent-${entry.id}'),
            entry: entry,
          ),
      ],
    );
  }
}

/// The card's one-sentence empty line, see [OverviewRowsCard.empty] for why
/// it is not a `WpEmptyState`.
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
  Future<void> _copy() async {
    // The list row carries only a preview: copy the full text (#1324).
    final full = (await ref.read(historyDatabaseProvider).entryContents([
      widget.entry.id,
    ]))[widget.entry.id];
    if (!mounted) return;
    unawaited(
      copyWithFeedback(
        context,
        text: full ?? widget.entry.content,
        target: 'overview-recent-${widget.entry.id}',
      ),
    );
    ref.read(firstStepsNotifierProvider.notifier).recordingCopied();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final entry = widget.entry;
    final text = entry.content.trim().isEmpty ? entry.title : entry.content;
    final target = entry.targetApp?.trim();
    final audioPath = ref.watch(
      overviewRecentAudioProvider.select((a) => a.value?[entry.id]),
    );
    final playing = ref.watch(
      recordingPlaybackProvider.select((key) => key == entry.id),
    );
    return OverviewRow(
      time: formatHistoryTime(entry.timestamp),
      // Without a known target the quiet "unknown" tile keeps the column, so
      // the texts of all rows start at the same edge.
      leading: WpAppIcon(identifier: target ?? '', size: WpIconSize.xl),
      text: text,
      subtitle: target != null && target.isNotEmpty
          ? watchAppName(ref, target)
          : null,
      onOpen: () => overviewOpenRecording(ref, entry.id),
      actions: [
        WpCopyAnchor(
          target: 'overview-recent-${entry.id}',
          child: WpIconButton.ghost(
            testId: 'overview-recent-copy-${entry.id}',
            icon: LucideIcons.copy,
            tooltip: l10n.overviewRecentCopy,
            onPressed: _copy,
          ),
        ),
        if (audioPath != null)
          WpIconButton.ghost(
            testId: 'overview-recent-play-${entry.id}',
            icon: playing ? LucideIcons.square : LucideIcons.play,
            tooltip: playing
                ? l10n.overviewRecentStop
                : l10n.overviewRecentPlay,
            onPressed: () => unawaited(
              ref
                  .read(recordingPlaybackProvider.notifier)
                  .toggle(entry.id, audioPath),
            ),
          ),
        WpIconButton.ghost(
          testId: 'overview-recent-open-${entry.id}',
          icon: LucideIcons.ellipsis,
          tooltip: l10n.overviewRecentOpen,
          onPressed: () => overviewOpenRecording(ref, entry.id),
        ),
      ],
    );
  }
}
