import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/data/database.dart';
import '../data/providers.dart' show DateGroup;

/// View mode for the history page.
enum HistoryViewMode { list, cards, compact }

/// Sort order for history entries.
enum HistorySortOrder { newest, oldest, longest }

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

/// Derives a warm avatar color from the entry's first tag or title.
Color historyAvatarColor(HistoryEntry entry, bool isDark) {
  // Palette of warm, distinguishable hues (not harsh, not glow)
  const palette = [
    Color(0xFF22D3EE), // cyan (default)
    Color(0xFF8B5CF6), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF10B981), // emerald
    Color(0xFFF472B6), // pink
    Color(0xFF3B82F6), // blue
    Color(0xFFEF4444), // red
    Color(0xFF14B8A6), // teal
  ];
  // Hash from title for consistent color per entry
  final hash = entry.title.isNotEmpty
      ? entry.title.codeUnits.fold<int>(0, (a, b) => a + b)
      : entry.id.codeUnits.fold<int>(0, (a, b) => a + b);
  return palette[hash % palette.length];
}

/// A single avatar-icon rule: matches when any [tagKeywords] is found in the
/// entry's tags OR any [titleKeywords] is found in the entry's title.  Tag and
/// title keyword lists are kept SEPARATE so each rule can be asymmetric (some
/// rules deliberately check only tags, others only the title).
typedef _AvatarIconRule = ({
  List<String> tagKeywords,
  List<String> titleKeywords,
  IconData icon,
});

// Rules evaluated in order; first match wins.  Mapping is asymmetric per rule.
const _avatarIconRules = <_AvatarIconRule>[
  (
    tagKeywords: ['meeting'],
    titleKeywords: ['meeting', 'standup'],
    icon: LucideIcons.users,
  ),
  (
    tagKeywords: ['email'],
    titleKeywords: ['email', 'follow'],
    icon: LucideIcons.mail,
  ),
  (
    tagKeywords: ['blog', 'writing'],
    titleKeywords: ['blog', 'draft'],
    icon: LucideIcons.penLine,
  ),
  (
    tagKeywords: ['personal', 'recipe'],
    titleKeywords: [],
    icon: LucideIcons.heart,
  ),
  (
    tagKeywords: ['feedback'],
    titleKeywords: ['feedback', 'review'],
    icon: LucideIcons.messageSquare,
  ),
  (
    tagKeywords: ['project'],
    titleKeywords: ['project', 'brief'],
    icon: LucideIcons.folderOpen,
  ),
  (
    tagKeywords: ['idea', 'team'],
    titleKeywords: [],
    icon: LucideIcons.lightbulb,
  ),
  (
    tagKeywords: [],
    titleKeywords: ['reminder', 'todo'],
    icon: LucideIcons.bellRing,
  ),
];

/// Icon for the entry avatar — based on content/source hints.
IconData historyAvatarIcon(HistoryEntry entry) {
  final title = entry.title.toLowerCase();
  final tags = entry.tags.toLowerCase();
  for (final rule in _avatarIconRules) {
    final matched =
        rule.tagKeywords.any(tags.contains) ||
        rule.titleKeywords.any(title.contains);
    if (matched) return rule.icon;
  }
  return LucideIcons.mic;
}

/// Entry avatar — colored circle with icon (Discord/WhatsApp identity).
class HistoryEntryAvatar extends StatelessWidget {
  const HistoryEntryAvatar({
    super.key,
    required this.color,
    required this.icon,
    required this.isPinned,
    required this.isDark,
    this.size = 36,
  });

  final Color color;
  final IconData icon;
  final bool isPinned;
  final bool isDark;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = (size * 0.44).roundToDouble();
    return SizedBox(
      width: size + 6,
      height: size + 6,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Avatar circle — offset slightly to leave room for badge
          Positioned(
            left: 0,
            bottom: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color.withValues(alpha: isDark ? 0.15 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color: color.withValues(alpha: isDark ? 0.9 : 0.8),
              ),
            ),
          ),
          // Favorite badge — star icon in top-right corner
          if (isPinned)
            Positioned(
              right: 0,
              top: 0,
              child: FaIcon(
                FontAwesomeIcons.solidStar,
                size: 11,
                color: Colors.amber.shade600,
              ),
            ),
        ],
      ),
    );
  }
}

/// Returns true when the focused widget is an [EditableText] (text input).
///
/// `EditableText.build()` creates an internal `Focus` widget that overwrites
/// the FocusNode context, so `context.widget` ends up being `Focus`, not
/// `EditableText`. We check the widget directly AND walk ancestors as a
/// fallback to cover both cases.
bool isTextFieldFocused() {
  final primary = FocusManager.instance.primaryFocus;
  if (primary == null) return false;
  final context = primary.context;
  if (context == null) return false;
  if (context.widget is EditableText) return true;
  return context.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Lightweight union for flattened header/entry items used by list and compact
/// views. Avoids pre-building widgets — the actual widget is created lazily
/// inside [ListView.builder].
class HistoryFlatItem {
  const HistoryFlatItem.header(this.headerLabel) : entry = null;
  const HistoryFlatItem.entry(this.entry) : headerLabel = null;

  final String? headerLabel;
  final HistoryEntry? entry;
}

/// Flattens a list of [DateGroup]s into header/entry items for a [ListView].
List<HistoryFlatItem> buildHistoryFlatItems(List<DateGroup> groups) {
  final result = <HistoryFlatItem>[];
  for (final group in groups) {
    result.add(HistoryFlatItem.header(group.labelKey));
    for (final entry in group.entries) {
      result.add(HistoryFlatItem.entry(entry));
    }
  }
  return result;
}
