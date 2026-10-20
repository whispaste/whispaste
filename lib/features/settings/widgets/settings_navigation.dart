/// Settings navigation (WP-23b, `07-settings-ia.md` §2): eight areas in three
/// overline groups, a version footer, and the keyboard rules for the list.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/generated/wp_tokens.g.dart' show WpTypeScaleTokens;
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../settings_areas.dart';
import 'settings_scroll_affordance.dart';

/// Width of the navigation column (spec §2).
const double kSettingsNavWidth = 232;

/// Visible height of one row (spec §2). The hit area is 48 px, so the row
/// keeps 2 px of air above and below.
const double kSettingsNavRowHeight = 44;
const double kSettingsNavHitHeight = 48;

/// Icon for each area. Icons appear only here, never inside a settings row.
const Map<SettingsArea, IconData> _kSettingsAreaIcons = {
  SettingsArea.general: LucideIcons.slidersHorizontal,
  SettingsArea.appearance: LucideIcons.palette,
  SettingsArea.shortcuts: LucideIcons.keyboard,
  SettingsArea.recording: LucideIcons.mic,
  SettingsArea.speech: LucideIcons.audioLines,
  SettingsArea.textInsert: LucideIcons.textCursorInput,
  SettingsArea.privacy: LucideIcons.shieldCheck,
  SettingsArea.advanced: LucideIcons.flaskConical,
  SettingsArea.about: LucideIcons.info,
};

IconData settingsAreaIcon(SettingsArea area) => _kSettingsAreaIcons[area]!;

final Map<SettingsArea, String Function(L10n)> _kSettingsAreaLabels = {
  SettingsArea.general: (l) => l.settingsAreaGeneral,
  SettingsArea.appearance: (l) => l.settingsAreaAppearance,
  SettingsArea.shortcuts: (l) => l.settingsAreaShortcuts,
  SettingsArea.recording: (l) => l.settingsAreaRecording,
  SettingsArea.speech: (l) => l.settingsAreaSpeech,
  SettingsArea.textInsert: (l) => l.settingsAreaTextInsert,
  SettingsArea.privacy: (l) => l.settingsAreaPrivacy,
  SettingsArea.advanced: (l) => l.settingsAreaAdvanced,
  SettingsArea.about: (l) => l.pageAboutTitle,
};

String settingsAreaLabel(L10n l10n, SettingsArea area) =>
    _kSettingsAreaLabels[area]!(l10n);

String settingsGroupLabel(L10n l10n, SettingsGroup group) => switch (group) {
  SettingsGroup.app => l10n.settingsGroupApp,
  SettingsGroup.dictation => l10n.settingsGroupDictation,
  SettingsGroup.system => l10n.settingsGroupSystem,
};

/// The navigation column. [footer] sits at the bottom (version and update
/// status, or the store note on store builds).
class SettingsNavigation extends StatelessWidget {
  const SettingsNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.footer,
    this.header,
  });

  final SettingsArea selected;
  final ValueChanged<SettingsArea> onSelect;
  final Widget footer;

  /// Above the groups: the settings search field.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final children = <Widget>[];
    for (final group in SettingsGroup.values) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.md,
            WpSpacing.lg,
            WpSpacing.md,
            WpSpacing.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              settingsGroupLabel(l10n, group).toUpperCase(),
              style: const TextStyle(
                fontFamily: kWpUiFont,
                fontFamilyFallback: kWpFontFallback,
                fontSize: WpTypography.caption,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ).copyWith(color: WpColors.textMuted),
            ),
          ),
        ),
      );
      for (final area in settingsAreasIn(group)) {
        children.add(
          _SettingsNavRow(
            area: area,
            label: settingsAreaLabel(l10n, area),
            selected: area == selected,
            onTap: () => onSelect(area),
          ),
        );
      }
    }

    return SizedBox(
      width: kSettingsNavWidth,
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SettingsScrollAffordance(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [?header, ...children],
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(WpSpacing.md), child: footer),
          ],
        ),
      ),
    );
  }
}

class _SettingsNavRow extends StatefulWidget {
  const _SettingsNavRow({
    required this.area,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final SettingsArea area;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SettingsNavRow> createState() => _SettingsNavRowState();
}

class _SettingsNavRowState extends State<_SettingsNavRow> {
  bool _hovered = false;
  bool _focused = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      widget.onTap();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final foreground = widget.selected
        ? WpColors.accent
        : WpColors.textSecondary;
    final fill = widget.selected
        ? WpColors.accentSubtle
        : _hovered
        ? WpColors.hover
        : null;

    return Semantics(
      key: ValueKey('settings-nav-${widget.area.id}'),
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: Focus(
        onKeyEvent: _onKey,
        onFocusChange: (f) => setState(() => _focused = f),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              height: kSettingsNavHitHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: (kSettingsNavHitHeight - kSettingsNavRowHeight) / 2,
                ),
                child: AnimatedContainer(
                  duration: WpMotion.durationFor(context, WpMotion.hoverIn),
                  padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: WpRadius.borderSm,
                    border: _focused
                        ? Border.all(color: WpColors.accent, width: 2)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        settingsAreaIcon(widget.area),
                        size: WpIconSize.md,
                        color: foreground,
                      ),
                      const SizedBox(width: WpSpacing.md),
                      Expanded(
                        child: Text(
                          widget.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: kWpUiFont,
                            fontFamilyFallback: kWpFontFallback,
                            fontSize: WpTypeScaleTokens.bodyLg,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: foreground,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
