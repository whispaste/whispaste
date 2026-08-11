import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/wp_focus_ring.dart';
import '../../settings/settings_widgets.dart' show kSettingRowInset;

/// Widget keys exposed for testing.
@visibleForTesting
const kAppearanceThemeSelectorKey = Key('appearanceThemeSelector');

/// Test key for the swatch of [mode].
@visibleForTesting
Key appearanceThemeSwatchKey(ThemeMode mode) =>
    Key('appearanceThemeSwatch_${mode.name}');

/// The light/dark/system theme choice — the picture half of the Appearance
/// page (the autostart toggle beneath it is [OnboardingAutostartToggle]; the
/// page itself, heading and gaps included, is composed in the overlay).
///
/// Off the Model & Hotkey page since the redesign's third round, where it had
/// ~27 px of slack to share with everything else — not enough for a choice
/// that is best made by *looking* rather than by reading three words. Here the
/// same choice is three picture tiles: a miniature of what the app will look
/// like, with a ring around the active one (Conductor reference,
/// `.scratch/onboarding-redesign/reference-conductor/SCR-20260804-kayx.png`).
///
/// The selection writes straight to [settingsProvider] and takes effect
/// immediately — the page you are looking at repaints as you choose, which is
/// the whole point of showing it full-size. There is nothing to confirm, so
/// the page stays walkable without any input.
///
/// The recording-duration note that used to sit here moved to the Model
/// page: it explains when a recording stops by itself, which belongs
/// next to the control that starts one, not next to the theme.
class AppearanceStep extends ConsumerWidget {
  const AppearanceStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final l10n = L10n.of(context);
    final themeMode = settings.interface_.themeMode;

    void selectThemeMode(ThemeMode mode) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings(
            (s) => s.copyWithSections(
              interface_: s.interface_.copyWith(themeMode: mode),
            ),
          );
    }

    return Align(
      alignment: AlignmentDirectional.centerStart,
      // The page heading above and the autostart row below both sit on the
      // shared reading edge (`kSettingRowInset`); without this the tiles were
      // the only block on the page starting 12 px further left, which broke
      // the vertical line the eye follows down the page.
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
        // Three equal shares of whatever the frame offers, not three fixed
        // 200-px tiles. The fixed width came to 640 against a 720-px frame and
        // left an 80-px tail, so the tile row ended 68 px short of the
        // autostart row directly beneath it — two stacked blocks with two
        // different right edges, which is the one thing this page could not
        // afford given the tiles ARE the page. Sharing the row out makes the
        // edge flush by construction rather than by arithmetic that has to be
        // redone every time the frame moves (it moved: see `_readingMeasure`).
        child: Row(
          key: kAppearanceThemeSelectorKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            Expanded(
              child: _ThemeSwatch(
                key: appearanceThemeSwatchKey(ThemeMode.light),
                mode: ThemeMode.light,
                label: l10n.onboardingThemeLight,
                active: themeMode == ThemeMode.light,
                onTap: () => selectThemeMode(ThemeMode.light),
              ),
            ),
            const SizedBox(width: WpSpacing.lg),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            Expanded(
              child: _ThemeSwatch(
                key: appearanceThemeSwatchKey(ThemeMode.dark),
                mode: ThemeMode.dark,
                label: l10n.onboardingThemeDark,
                active: themeMode == ThemeMode.dark,
                onTap: () => selectThemeMode(ThemeMode.dark),
              ),
            ),
            const SizedBox(width: WpSpacing.lg),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            Expanded(
              child: _ThemeSwatch(
                key: appearanceThemeSwatchKey(ThemeMode.system),
                mode: ThemeMode.system,
                label: l10n.onboardingThemeSystem,
                active: themeMode == ThemeMode.system,
                onTap: () => selectThemeMode(ThemeMode.system),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme swatch — a miniature of the app in the offered theme, plus its label.
// ---------------------------------------------------------------------------

/// Height of one preview tile. The *width* is whatever third of the row the
/// tile is given (see the [Row] above) — it used to be a fixed 200 px, which
/// is what left the tile row and the autostart row under it on two different
/// right edges. The height stays fixed because it is what makes the miniature
/// read as a picture rather than as a swatch chip, which is the reason this
/// choice got a page of its own.
const double _kSwatchHeight = 132;

/// One selectable theme: the preview tile with a selection ring, the label
/// underneath.
///
/// Semantics are `button` + `selected` + the theme's own name, which is the
/// same contract the segmented control it replaces exposed. The label [Text]
/// is what supplies that name and the [InkWell] is what supplies the button
/// role and the tap action, so both stay in the tree and [MergeSemantics]
/// folds them into one node; only the decorative preview is excluded.
/// Wrapping the lot in `Semantics(excludeSemantics: true)` instead would
/// announce a button that a screen reader cannot actually activate — the
/// tap action lives on the InkWell it would discard.
///
/// Keyboard focus is marked by [WpFocusRing] in external-node mode — the same
/// node goes to the ring and to the [InkWell], so Enter/Space still activates
/// the tile. Without it this was the only selectable tile family in the
/// onboarding relying on InkWell's default highlight, which on a tile that
/// already carries an accent selection border is nearly invisible.
class _ThemeSwatch extends StatefulWidget {
  const _ThemeSwatch({
    super.key,
    required this.mode,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_ThemeSwatch> createState() => _ThemeSwatchState();
}

class _ThemeSwatchState extends State<_ThemeSwatch> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = WpColorsDark.accent;
    const border = WpColorsDark.borderSubtle;
    const textPrimary = WpColorsDark.textPrimary;
    const textSecondary = WpColorsDark.textSecondary;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: widget.active,
        child: WpFocusRing(
          focusNode: _focusNode,
          radius: WpRadius.md,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              focusNode: _focusNode,
              onTap: widget.onTap,
              borderRadius: WpRadius.borderMd,
              // WpFocusRing owns the focus visual — suppress InkWell's own
              // fill, or focus paints twice. Only focusColor: unlike the
              // history rows this tile draws no hover of its own, so
              // hoverColor is its only pointer feedback and has to stay.
              focusColor: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: AnimatedContainer(
                      duration: WpMotion.durationFor(context, WpMotion.fast),
                      curve: WpMotion.defaultCurve,
                      height: _kSwatchHeight,
                      decoration: BoxDecoration(
                        borderRadius: WpRadius.borderMd,
                        border: Border.all(
                          color: widget.active ? accent : border,
                          width: widget.active ? 2 : 1,
                        ),
                      ),
                      // Inset so the ring never paints over the preview's edge.
                      padding: const EdgeInsets.all(2),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(WpRadius.md - 3),
                        child: _ThemeMiniature(mode: widget.mode),
                      ),
                    ),
                  ),
                  // `sm` (12), not `xs` (8). Under a 132-px tile, 8 px reads
                  // as the label clinging to the tile's edge rather than
                  // belonging to it, and it is half the gap that separates
                  // this whole block from the autostart row below (`xl`, 24).
                  // At 12 the ratio to that block gap is a clean 2:1, which is
                  // what makes the tile-plus-label read as one item.
                  const SizedBox(height: WpSpacing.sm),
                  Text(
                    widget.label,
                    style: TextStyle(
                      // `body` (13), matching the label of the autostart row
                      // directly beneath it. These two are the same thing —
                      // the name of a choice — and the tile's was a grade
                      // smaller for no reason other than sitting under a
                      // picture.
                      fontSize: WpTypography.body,
                      fontWeight: widget.active
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: widget.active ? textPrimary : textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The picture inside a swatch: a deliberately abstract miniature — a side
/// panel and a few content bars in the palette the theme would apply.
///
/// Abstract on purpose. A faithful screenshot of the app would have to be
/// re-rendered every time the UI changes, and at 164 px wide it would read as
/// noise anyway; what the tile has to answer is "how light or dark will this
/// be", which shape-free colour blocks answer better than detail.
/// [ThemeMode.system] shows both palettes split diagonally — the standard
/// idiom for "whichever the system is using".
class _ThemeMiniature extends StatelessWidget {
  const _ThemeMiniature({required this.mode});

  final ThemeMode mode;

  @override
  Widget build(BuildContext context) {
    return switch (mode) {
      ThemeMode.light => const _MiniaturePalette(dark: false),
      ThemeMode.dark => const _MiniaturePalette(dark: true),
      ThemeMode.system => const Stack(
        fit: StackFit.expand,
        children: [
          _MiniaturePalette(dark: false),
          ClipPath(
            clipper: _DiagonalClipper(),
            child: _MiniaturePalette(dark: true),
          ),
        ],
      ),
    };
  }
}

class _MiniaturePalette extends StatelessWidget {
  const _MiniaturePalette({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final background = dark ? WpColorsDark.background : WpColorsDark.background;
    final panel = dark ? WpColorsDark.surface : WpColorsDark.surface;
    final bar = (dark ? WpColorsDark.textMuted : WpColorsDark.textMuted)
        .withValues(alpha: 0.45);
    final accent = dark ? WpColorsDark.accent : WpColorsDark.accent;
    // Surface and background sit deliberately close together in both
    // palettes, so at this size the sidebar would otherwise be invisible and
    // the miniature would read as bars floating on a colour field.
    final divider = dark
        ? WpColorsDark.borderDefault
        : WpColorsDark.borderDefault;

    return ColoredBox(
      color: background,
      child: Row(
        children: [
          // Side panel — the app's sidebar, at roughly its real proportion.
          Expanded(flex: 3, child: ColoredBox(color: panel)),
          SizedBox(width: 1, child: ColoredBox(color: divider)),
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.all(WpSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniatureBar(color: accent, widthFactor: 0.5),
                  const SizedBox(height: 6),
                  _MiniatureBar(color: bar, widthFactor: 0.95),
                  const SizedBox(height: 6),
                  _MiniatureBar(color: bar, widthFactor: 0.7),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniatureBar extends StatelessWidget {
  const _MiniatureBar({required this.color, required this.widthFactor});

  final Color color;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

/// Keeps the lower-trailing triangle of the system swatch, so the dark
/// palette painted through it meets the light one on the diagonal.
class _DiagonalClipper extends CustomClipper<Path> {
  const _DiagonalClipper();

  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
