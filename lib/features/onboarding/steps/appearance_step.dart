import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
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
      // the vertical line the eye follows down the page. Three 200-px tiles
      // plus two `lg` gaps come to 640 of the 720-px frame, so the inset is
      // paid for out of the 80 px that were spare.
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: kSettingRowInset),
        child: Wrap(
          key: kAppearanceThemeSelectorKey,
          spacing: WpSpacing.lg,
          runSpacing: WpSpacing.lg,
          children: [
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            _ThemeSwatch(
              key: appearanceThemeSwatchKey(ThemeMode.light),
              mode: ThemeMode.light,
              label: l10n.onboardingThemeLight,
              active: themeMode == ThemeMode.light,
              onTap: () => selectThemeMode(ThemeMode.light),
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            _ThemeSwatch(
              key: appearanceThemeSwatchKey(ThemeMode.dark),
              mode: ThemeMode.dark,
              label: l10n.onboardingThemeDark,
              active: themeMode == ThemeMode.dark,
              onTap: () => selectThemeMode(ThemeMode.dark),
            ),
            // loam-ignore: a11y-interactive-semantics – semantics provided in _ThemeSwatch.build
            _ThemeSwatch(
              key: appearanceThemeSwatchKey(ThemeMode.system),
              mode: ThemeMode.system,
              label: l10n.onboardingThemeSystem,
              active: themeMode == ThemeMode.system,
              onTap: () => selectThemeMode(ThemeMode.system),
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

/// Outer dimensions of one preview tile. Three of these plus two `lg` gaps
/// come to 640 of the 720-px page frame — large enough that the miniature
/// reads as a picture rather than as a swatch chip, which is the reason this
/// choice got a page of its own.
const double _kSwatchWidth = 200;
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
class _ThemeSwatch extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    final border = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: active,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: WpRadius.borderMd,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: AnimatedContainer(
                    duration: WpMotion.durationFor(context, WpMotion.fast),
                    curve: WpMotion.defaultCurve,
                    width: _kSwatchWidth,
                    height: _kSwatchHeight,
                    decoration: BoxDecoration(
                      borderRadius: WpRadius.borderMd,
                      border: Border.all(
                        color: active ? accent : border,
                        width: active ? 2 : 1,
                      ),
                    ),
                    // Inset so the ring never paints over the preview's edge.
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(WpRadius.md - 3),
                      child: _ThemeMiniature(mode: mode),
                    ),
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: WpTypography.small,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? textPrimary : textSecondary,
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
    final background = dark
        ? WpColorsDark.background
        : WpColorsLight.background;
    final panel = dark ? WpColorsDark.surface : WpColorsLight.surface;
    final bar = (dark ? WpColorsDark.textMuted : WpColorsLight.textMuted)
        .withValues(alpha: 0.45);
    final accent = dark ? WpColorsDark.accent : WpColorsLight.accent;
    // Surface and background sit deliberately close together in both
    // palettes, so at this size the sidebar would otherwise be invisible and
    // the miniature would read as bars floating on a colour field.
    final divider = dark
        ? WpColorsDark.borderDefault
        : WpColorsLight.borderDefault;

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
