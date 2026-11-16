import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_collection_list_pane.dart';
import '../../../widgets/wp_collection_page.dart';

import 'package:whispaste/core/data/database.dart';

import '../data/providers.dart' show DateGroup;

/// View mode for the history page.
enum HistoryViewMode { list, cards, compact }

/// Window height below which the header above the history list counts as
/// short. The page family owns the value (`WpCollectionPage`).
const double kHistoryShortWindowHeight = WpCollectionPage.shortWindowHeight;

/// Rows an expanded header section shows inline before "Show all" (UX-098).
const int kHistoryInlineRows = 2;

/// True on a short window or at text scale 2.0 (UX-091). There the header
/// keeps only its summary line, and an expanded section opens as a dialog, so
/// the header never takes the list's room.
bool historyHeadIsShort(BuildContext context) =>
    wpCollectionHeadIsShort(context);

/// Resolves a [DateGroup.labelKey] to a localized string.
String resolveDateLabel(String key, L10n l10n) => switch (key) {
  'today' => l10n.historyToday,
  'yesterday' => l10n.historyYesterday,
  'thisWeek' => l10n.historyThisWeek,
  'older' => l10n.historyOlder,
  'all' => l10n.historyAll,
  _ => key,
};

/// Formats timestamp as HH:MM.
String formatHistoryTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Formats recording duration as human-readable string.
String formatHistoryDuration(double durationSec) {
  final secs = durationSec.round();
  if (secs < 60) return '${secs}s';
  final mins = secs ~/ 60;
  final rem = secs % 60;
  return rem > 0 ? '${mins}m ${rem}s' : '${mins}m';
}

/// The type glyph of a recording, drawn through `WpListItemTypeGlyph` in the
/// list row, the card and the detail head (#1498).
///
/// It is a constant rather than a per-entry lookup because the app classifies
/// nothing: an entry is always the same kind of thing, a dictation transcript,
/// so the icon can only ever say that. Keeping it here rather than inlining
/// `LucideIcons.mic` keeps that claim in one place.
const IconData historyAvatarIcon = LucideIcons.mic;

/// Small tonal status chip for the entry meta row (e.g. the language/engine
/// badge). Deliberately quieter than the accent-tinted tag chips — a muted
/// neutral surface fill, not brand color — so it reads as "status" while
/// duration/word-count stay plain metadata text.
class HistoryStatusChip extends StatelessWidget {
  const HistoryStatusChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final fill = WpColors.surfaceMutedFill;
    final text = WpColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(color: fill, borderRadius: WpRadius.borderSm),
      child: Text(
        label,
        style: TextStyle(
          fontSize: WpTypography.caption,
          color: text,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// The date groups as rows of a [WpCollectionListPane]: one header row per
/// group ([header] builds it from the group's label key), then its entries.
List<WpCollectionRow<HistoryEntry>> historyCollectionRows(
  List<DateGroup> groups,
  Widget Function(String labelKey) header,
) => [
  for (final group in groups) ...[
    WpCollectionHeaderRow<HistoryEntry>(header(group.labelKey)),
    for (final entry in group.entries)
      WpCollectionItemRow<HistoryEntry>(entry.id, entry),
  ],
];
