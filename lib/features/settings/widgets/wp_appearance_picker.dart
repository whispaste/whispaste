/// Appearance picker: three preview cards (Light, Dark, Navy) and the
/// "Follow system" switch (WP-23d, spec 06 §5.6, ticket IA §3 "Modus").
///
/// Each card paints a miniature of sidebar, content card and navy dock from
/// the real [WpThemeColors] set it stands for, so the choice is seen before it
/// is made.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/appearance.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/generated/wp_tokens.g.dart';
import '../../../core/theme/theme.dart' show kWpFontFallback, kWpUiFont;
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../settings_widgets.dart' show settingsToggle;

/// Order of the cards, left to right (mirrored under RTL).
const List<AppearanceMode> _cardModes = [
  AppearanceMode.light,
  AppearanceMode.dark,
  AppearanceMode.navy,
];

/// Card width bounds. Below [_minCardWidth] for three cards the row wraps.
const double _minCardWidth = 180;
const double _maxCardWidth = 240;

/// The mode a card shows as selected: System resolves to the set the platform
/// currently uses.
AppearanceMode _effectiveMode(AppearanceMode mode, Brightness platform) =>
    mode == AppearanceMode.system
    ? (platform == Brightness.dark ? AppearanceMode.dark : AppearanceMode.light)
    : mode;

/// The value written when the "Follow system" switch changes. Turning it off
/// selects the set System resolves to, so the look does not change under the
/// user.
AppearanceMode appearanceForFollowSystem({
  required bool follow,
  required AppearanceMode current,
  required Brightness platformBrightness,
}) {
  if (follow) return AppearanceMode.system;
  if (current != AppearanceMode.system) return current;
  return _effectiveMode(AppearanceMode.system, platformBrightness);
}

/// Three selectable preview cards for [AppearanceMode].
///
/// Keyboard: Tab enters the group, Left and Right (Up and Down too) move focus
/// between cards and wrap, Enter or Space selects the focused card. Selection
/// is explicit, so arrows never write a setting.
class WpAppearancePicker extends StatefulWidget {
  const WpAppearancePicker({
    super.key,
    required this.mode,
    required this.platformBrightness,
    required this.onChanged,
  });

  final AppearanceMode mode;

  /// Brightness the platform reports; only matters for
  /// [AppearanceMode.system].
  final Brightness platformBrightness;

  final ValueChanged<AppearanceMode> onChanged;

  @override
  State<WpAppearancePicker> createState() => _WpAppearancePickerState();
}

class _WpAppearancePickerState extends State<WpAppearancePicker> {
  final List<FocusNode> _nodes = [for (final _ in _cardModes) FocusNode()];

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _onKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final key = event.logicalKey;
    int? step;
    if (key == LogicalKeyboardKey.arrowRight) {
      step = rtl ? -1 : 1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      step = rtl ? 1 : -1;
    } else if (key == LogicalKeyboardKey.arrowDown) {
      step = 1;
    } else if (key == LogicalKeyboardKey.arrowUp) {
      step = -1;
    }
    if (step != null) {
      final count = _cardModes.length;
      final next = (index + step + count) % count;
      _nodes[next].requestFocus();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) widget.onChanged(_cardModes[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final names = {
      AppearanceMode.light: l10n.settingsAppearanceLight,
      AppearanceMode.dark: l10n.settingsAppearanceDark,
      AppearanceMode.navy: l10n.settingsAppearanceCardNavy,
    };
    final selected = _effectiveMode(widget.mode, widget.platformBrightness);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Cards keep a fixed proportion and a maximum width; on narrow
        // windows they wrap onto further rows instead of being squeezed.
        const gap = WpSpacing.sm;
        final fit = (constraints.maxWidth - 2 * gap) / 3;
        // Clamp into the card bounds; the Wrap breaks the row when three
        // cards no longer fit. Never wider than the space that is there.
        final cardWidth = math.min(
          constraints.maxWidth,
          fit.clamp(_minCardWidth, _maxCardWidth).toDouble(),
        );
        return Wrap(
          alignment: WrapAlignment.start,
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < _cardModes.length; i++)
              SizedBox(
                width: cardWidth,
                // One semantics node per card: a button with its name and
                // selected state. The visual children are excluded so the name
                // is not read twice.
                child: Semantics(
                  label: names[_cardModes[i]]!,
                  key: ValueKey(
                    'settings-appearance-card-${_cardModes[i].value}',
                  ),
                  button: true,
                  selected: _cardModes[i] == selected,
                  onTap: () => widget.onChanged(_cardModes[i]),
                  excludeSemantics: true,
                  child: _AppearanceCard(
                    mode: _cardModes[i],
                    name: names[_cardModes[i]]!,
                    selected: _cardModes[i] == selected,
                    focusNode: _nodes[i],
                    onKey: (event) => _onKey(i, event),
                    onTap: () => widget.onChanged(_cardModes[i]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.mode,
    required this.name,
    required this.selected,
    required this.focusNode,
    required this.onKey,
    required this.onTap,
  });

  final AppearanceMode mode;
  final String name;
  final bool selected;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final set = colorsForAppearance(mode, Brightness.light);
    return Focus(
      // Key events from the inner InkWell bubble up to here. The wrapper
      // itself must not take focus, or Tab would stop on it.
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => onKey(event),
      child: WpFocusRing(
        focusNode: focusNode,
        radius: WpRadius.md,
        child: InkWell(
          focusNode: focusNode,
          onTap: onTap,
          borderRadius: BorderRadius.circular(WpRadius.md),
          child: Container(
            padding: const EdgeInsets.all(WpSpacing.sm),
            decoration: BoxDecoration(
              // Unselected tiles sit inside the group card: no second fill level.
              color: selected ? WpColors.accentSubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(WpRadius.md),
              border: Border.all(
                color: selected ? WpColors.accent : WpColors.borderSubtle,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ModePreview(colors: set),
                const SizedBox(height: WpSpacing.sm),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: kWpUiFont,
                    fontFamilyFallback: kWpFontFallback,
                    fontSize: WpTypography.subheading,
                    fontWeight: FontWeight.w600,
                    color: selected ? WpColors.accent : WpColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Miniature of the app shell in one colour set: sidebar, content card and
/// the navy dock along the bottom.
class _ModePreview extends StatelessWidget {
  const _ModePreview({required this.colors});

  final WpThemeColors colors;

  // The layout is identical for every set: only the colours differ. The
  // sidebar runs the full height of the window; the dock sits under the
  // content card, so it never meets the sidebar.
  //
  // The miniature is drawn on a fixed design canvas of
  // [_designWidth] x [_designHeight] and scaled as a whole into a box with the
  // same aspect ratio, so it grows and shrinks proportionally and is never
  // stretched.
  static const double _designWidth = 240;
  static const double _designHeight = 150;

  @override
  Widget build(BuildContext context) {
    // The dock is navy in every set, so it always comes from the dark set.
    // ignore: prefer_const_declarations
    final dock = wpDarkColors.background;
    return AspectRatio(
      aspectRatio: _designWidth / _designHeight,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: _designWidth,
          height: _designHeight,
          child: _miniature(colors, dock),
        ),
      ),
    );
  }

  Widget _miniature(WpThemeColors colors, Color dock) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(WpRadius.sm),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.background),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ColoredBox(
                color: colors.frame.background,
                child: Padding(
                  padding: const EdgeInsets.all(WpSpacing.xs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _line(colors.textPrimary, 36),
                      const SizedBox(height: 6),
                      _line(colors.textMuted, 26),
                      const SizedBox(height: 6),
                      _line(colors.textMuted, 30),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 7,
              child: Padding(
                padding: const EdgeInsets.all(WpSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.cardFill,
                          borderRadius: BorderRadius.circular(
                            WpRadiusTokens.chip,
                          ),
                          border: Border.all(color: colors.borderSubtle),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(WpSpacing.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _line(colors.textPrimary, 60),
                              const SizedBox(height: 6),
                              _line(colors.textMuted, 90),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: WpSpacing.xs),
                    Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: dock,
                        borderRadius: BorderRadius.circular(
                          WpRadiusTokens.chip,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(Color color, double width) => Container(
    width: width,
    height: 4,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// "Follow system" switch. On means [AppearanceMode.system]. Turning it off
/// selects the set the platform currently resolves to.
class WpFollowSystemSwitch extends StatelessWidget {
  const WpFollowSystemSwitch({
    super.key,
    required this.mode,
    required this.platformBrightness,
    required this.onChanged,
  });

  final AppearanceMode mode;
  final Brightness platformBrightness;
  final ValueChanged<AppearanceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final follow = mode == AppearanceMode.system;
    return settingsToggle(
      key: const ValueKey('settings-appearance-follow-system'),
      value: follow,
      onChanged: (on) => onChanged(
        appearanceForFollowSystem(
          follow: on,
          current: mode,
          platformBrightness: platformBrightness,
        ),
      ),
    );
  }
}
