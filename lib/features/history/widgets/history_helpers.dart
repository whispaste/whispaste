import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import 'package:whispaste/core/data/database.dart';

/// View mode for the history page.
enum HistoryViewMode { list, cards, compact }

/// Resolves a [DateGroup.labelKey] to a localized string.
String resolveDateLabel(String key, L10n l10n) {
  switch (key) {
    case 'today':
      return l10n.historyToday;
    case 'yesterday':
      return l10n.historyYesterday;
    case 'thisWeek':
      return l10n.historyThisWeek;
    case 'older':
      return l10n.historyOlder;
    default:
      return key;
  }
}

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

/// Icon for the entry avatar — based on content/source hints.
IconData historyAvatarIcon(HistoryEntry entry) {
  final title = entry.title.toLowerCase();
  final tags = entry.tags.toLowerCase();

  if (tags.contains('meeting') || title.contains('meeting') || title.contains('standup')) {
    return LucideIcons.users;
  }
  if (tags.contains('email') || title.contains('email') || title.contains('follow')) {
    return LucideIcons.mail;
  }
  if (tags.contains('blog') || tags.contains('writing') || title.contains('blog') || title.contains('draft')) {
    return LucideIcons.penLine;
  }
  if (tags.contains('personal') || tags.contains('recipe')) {
    return LucideIcons.heart;
  }
  if (tags.contains('feedback') || title.contains('feedback') || title.contains('review')) {
    return LucideIcons.messageSquare;
  }
  if (tags.contains('project') || title.contains('project') || title.contains('brief')) {
    return LucideIcons.folderOpen;
  }
  if (tags.contains('idea') || tags.contains('team')) {
    return LucideIcons.lightbulb;
  }
  if (title.contains('reminder') || title.contains('todo')) {
    return LucideIcons.bellRing;
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
      width: size,
      height: size,
      child: Stack(
        children: [
          // Avatar circle
          Container(
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
          // Favorite badge — small dot in corner
          if (isPinned)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? WpColorsDark.surface : WpColorsLight.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
