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

/// The one glyph every entry avatar wears.
///
/// It is a constant rather than a per-entry lookup because the app classifies
/// nothing: an entry is always the same kind of thing, a dictation transcript,
/// so the icon can only ever say that. Keeping it here rather than inlining
/// `LucideIcons.mic` at each avatar keeps that claim in one place — change it
/// once and every list row, card and detail header follows.
const IconData historyAvatarIcon = LucideIcons.mic;

/// Decorative color slot for the entry avatar — a plain read of the slot the
/// entry was handed once, at creation, and has carried ever since.
///
/// The hue means **nothing**. It is rotation, not category: the app does not
/// classify what was dictated — every entry is the same kind of thing, a
/// dictation transcript — and the color exists only so a long list stays
/// scannable. Reading the persisted column rather than deriving anything from
/// the content is what keeps a color stable across restarts and stops it from
/// sliding to the next hue whenever the title is edited.
///
/// Indexes [WpCategorySlot.categories], the same eight-slot space the write
/// path rolls into — never [WpCategorySlot.values], whose ninth entry is the
/// [WpCategorySlot.neutral] fallback grey and no part of the rotation.
///
/// Returns the *slot*, never a [Color]: callers cache this across rebuilds and a
/// resolved color would survive a runtime theme switch as the old theme's hue.
WpCategorySlot historyAvatarSlot(HistoryEntry entry) =>
    WpCategorySlot.categories[entry.colorSlot];

/// Entry avatar — colored circle with the microphone glyph every entry shares.
///
/// "Belichtete Scheibe", now made of the same material as the nav rail's icon
/// chips: [WpAvatarTint.discGradient] is a three-stop vertical ramp whose first
/// tenth is a *precomposited* crown over a lit stop falling to a shaded one,
/// plus a 1px hue-tinted rim. The gloss is baked into the gradient rather than
/// painted as a second layer for the reason the chips already give — Flutter
/// cannot pair a non-uniform `Border` with a shape — and it is what turns a
/// tinted circle into something that looks lit rather than filled.
///
/// **Depth has one source per theme** (*The Depth-Source Rule*): the offset
/// shadow is light-only. Dark takes its depth from the disc's brightness delta
/// against the plane and from the crown; a black shadow on a near-black ground
/// is mud, not lift. Pearl keeps `WpShadows.subtleLight`, because there is
/// almost no room above the plane for a fill to carry objecthood on its own.
///
/// Every lightness and alpha comes from [WpAvatarTint], and every one of them
/// is *mirrored* between the themes — except the crown, which is lit in both
/// (see the token). The disc is a translucent tint over its ground, so it only
/// separates if the preparation flips direction: lighter and thin on navy,
/// toward ink and denser on pearl. The shifts are clamped into a legibility
/// band, so a hue that already sits near the band edge is held there instead of
/// collapsing into the ground or into near-black; hues in between keep their
/// own lightness character. Calibrated to keep the disc visible (≥1.5:1) and
/// the glyph readable (≥3:1 against the disc) for every [WpCategorySlot] in
/// both themes, measured on the ground the row actually stands on — the content
/// plane, not the flat `surface` token — and gated in
/// `test/core/theme/wcag_contrast_test.dart`. The material itself (stops, axis,
/// shape, which theme gets the shadow) is gated in
/// `test/features/history/history_avatar_material_test.dart`.
///
/// > **Retracted 2026-08-11 — "a soft, theme-resolved `WpShadows.subtleFor`
/// > lift".** The disc used to carry `subtleFor(isDark)`, i.e. a shadow in
/// > *both* themes. That predates the sharpening of *The Depth-Source Rule*
/// > into "one source per theme" and was simply left behind when the nav chips
/// > adopted `isDark ? null : subtleLight`. Recorded rather than overwritten
/// > because the flat-disc pass that introduced it argued explicitly for the
/// > shadow, and a claim that quietly disappears cannot be audited.
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
                gradient: tint.discGradient(color),
                shape: BoxShape.circle,
                border: Border.all(color: tint.edge(color), width: 1),
                // One depth source per theme — see this class's docs.
                boxShadow: null,
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
    const fill = WpColorsDark.surfaceMutedFill;
    const text = WpColorsDark.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.xxs,
        vertical: 1,
      ),
      decoration: BoxDecoration(color: fill, borderRadius: WpRadius.borderSm),
      child: Text(
        label,
        style: const TextStyle(
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
