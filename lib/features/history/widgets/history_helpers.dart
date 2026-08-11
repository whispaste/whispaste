import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
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

/// A single avatar-icon rule: matches when any [tagKeywords] is found in the
/// entry's tags OR any [titleKeywords] is found in the entry's title.  Tag and
/// title keyword lists are kept SEPARATE so each rule can be asymmetric (some
/// rules deliberately check only tags, others only the title).
///
/// [key] identifies the rule to [categorySlotForAvatarRule] and is the reason
/// the avatar hue means something: it names the *category*, not the entry, so
/// every meeting is one color because every meeting is one kind of thing.
typedef _AvatarIconRule = ({
  String key,
  List<String> tagKeywords,
  List<String> titleKeywords,
  IconData icon,
});

// Rules evaluated in order; first match wins.  Mapping is asymmetric per rule.
const _avatarIconRules = <_AvatarIconRule>[
  (
    key: 'meeting',
    tagKeywords: ['meeting'],
    titleKeywords: ['meeting', 'standup'],
    icon: LucideIcons.users,
  ),
  (
    key: 'email',
    tagKeywords: ['email'],
    titleKeywords: ['email', 'follow'],
    icon: LucideIcons.mail,
  ),
  (
    key: 'blog',
    tagKeywords: ['blog', 'writing'],
    titleKeywords: ['blog', 'draft'],
    icon: LucideIcons.penLine,
  ),
  (
    key: 'personal',
    tagKeywords: ['personal', 'recipe'],
    titleKeywords: [],
    icon: LucideIcons.heart,
  ),
  (
    key: 'feedback',
    tagKeywords: ['feedback'],
    titleKeywords: ['feedback', 'review'],
    icon: LucideIcons.messageSquare,
  ),
  (
    key: 'project',
    tagKeywords: ['project'],
    titleKeywords: ['project', 'brief'],
    icon: LucideIcons.folderOpen,
  ),
  (
    key: 'idea',
    tagKeywords: ['idea', 'team'],
    titleKeywords: [],
    icon: LucideIcons.lightbulb,
  ),
  (
    key: 'reminder',
    tagKeywords: [],
    titleKeywords: ['reminder', 'todo'],
    icon: LucideIcons.bellRing,
  ),
];

/// The rule an entry falls under, or `null` when none matches.
_AvatarIconRule? _matchAvatarRule(HistoryEntry entry) {
  final title = entry.title.toLowerCase();
  final tags = entry.tags.toLowerCase();
  for (final rule in _avatarIconRules) {
    final matched =
        rule.tagKeywords.any(tags.contains) ||
        rule.titleKeywords.any(title.contains);
    if (matched) return rule;
  }
  return null;
}

/// Icon for the entry avatar — based on content/source hints.
IconData historyAvatarIcon(HistoryEntry entry) =>
    _matchAvatarRule(entry)?.icon ?? LucideIcons.mic;

/// Category slot for the entry avatar — the same rule that picks the icon, so
/// hue and glyph always say the same thing and neither is the sole carrier.
///
/// An entry matching no rule is untitled/uncategorised, which in a dictation app
/// is the *normal* case rather than an edge one: it takes the dedicated
/// [WpCategorySlot.neutral] and is deliberately kept out of the category hues,
/// instead of hashing itself into one of them like the incumbent title hash did.
///
/// Returns the *slot*, never a [Color]: callers cache this across rebuilds and a
/// resolved color would survive a runtime theme switch as the old theme's hue.
WpCategorySlot historyAvatarSlot(HistoryEntry entry) {
  final rule = _matchAvatarRule(entry);
  return rule == null
      ? WpCategorySlot.neutral
      : categorySlotForAvatarRule(rule.key);
}

/// Entry avatar — colored circle with icon (Discord/WhatsApp identity).
///
/// "Belichtete Scheibe": a lightness-shifted fill gradient (same hue, the lit
/// stop offset by [WpAvatarTint.topStopLightnessDelta]) plus a 1px hue-tinted
/// edge border and a soft, theme-resolved `WpShadows.subtleFor` lift —
/// glow-free materiality on top of the flat fill this used to be.
///
/// Every lightness and alpha comes from [WpAvatarTint], and every one of them
/// is *mirrored* between the themes: the disc is a translucent tint over its
/// ground, so it only separates if the preparation flips direction — lighter
/// and thin on navy, toward ink and denser on pearl. The shifts are clamped
/// into a legibility band, so a hue that already sits near the band edge is
/// held there instead of collapsing into the ground or into near-black; hues in
/// between keep their own lightness character. Result is calibrated to keep the
/// disc visible (≥1.5:1 against surface) and the glyph readable (≥3:1 against
/// the disc) for every [WpCategorySlot] in both themes — gated in
/// `test/core/theme/wcag_contrast_test.dart`.
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
    final tint = WpAvatarTint.of(isDark);
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [tint.fillTop(color), tint.fillBottom(color)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: tint.edge(color), width: 1),
                boxShadow: WpShadows.subtleFor(isDark),
              ),
              child: Icon(icon, size: iconSize, color: tint.glyph(color)),
            ),
          ),
          // Favorite badge — star icon in top-right corner
          if (isPinned)
            const Positioned(
              right: 0,
              top: 0,
              child: FaIcon(
                FontAwesomeIcons.solidStar,
                size: 11,
                color: WpSharedColors.pinnedAccent,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small tonal status chip for the entry meta row (e.g. the language/engine
/// badge). Deliberately quieter than the accent-tinted tag chips — a muted
/// neutral surface fill, not brand color — so it reads as "status" while
/// duration/word-count stay plain metadata text.
class HistoryStatusChip extends StatelessWidget {
  const HistoryStatusChip({
    super.key,
    required this.label,
    required this.isDark,
  });

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fill = isDark
        ? WpColorsDark.surfaceMutedFill
        : WpColorsLight.surfaceMutedFill;
    final text = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(color: fill, borderRadius: WpRadius.borderSm),
      child: Text(
        label,
        style: TextStyle(
          fontSize: WpTypography.micro,
          color: text,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
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
