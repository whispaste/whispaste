import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/brand_wordmark.dart';
import '../../../widgets/language_selector.dart';

/// Test key for the tappable beat list tile at [index] (0-based).
@visibleForTesting
Key onboardingBeatTileKey(int index) => Key('onboardingBeatTile$index');

/// Test key for the large media placeholder while beat [index] is active.
@visibleForTesting
Key onboardingBeatMediaKey(int index) => Key('onboardingBeatMedia$index');

/// Start inset that lines page-1 controls up with the beat *text* rather than
/// with the edge of the beat highlight, which bleeds outward by exactly this
/// much (the tile's horizontal padding). The shell reuses it for the
/// microphone chip it appends after this widget.
const double kOnboardingContentInset = WpSpacing.md;

/// Width of the language dropdown. [LanguageSelector] runs `isExpanded:
/// true`, so it would otherwise stretch across the whole (deliberately wide)
/// page-1 frame — a full-width control for a three-item choice is exactly
/// the boxiness this page is trying to lose.
const double _kLanguageSelectorWidth = 240;

/// Welcome content of onboarding page 1 — wordmark, three demo beats and the
/// language selection.
///
/// Composition follows the Conductor reference (`.scratch/onboarding-redesign/
/// reference-conductor/SCR-20260804-kans.png`): a centred brand lockup on top,
/// then everything else start-aligned in a wide, airy frame — a vertical beat
/// list on one side, ONE large media area on the other, and the few controls
/// stacked underneath at the same start edge. The page carries no boxes it
/// doesn't need: the only filled surfaces are the active beat tile and the
/// media area, both borderless.
///
/// The language choice acts immediately on the whole UI and pre-seeds the
/// recognition language (and thus the engine recommendation on page 3) —
/// existing behaviour, unchanged. The theme choice deliberately does NOT
/// live here anymore: it moved to page 3, because the pre-rendered demo
/// loops cannot follow a live theme switch (see the extracted
/// `WpSegmentedSelector` in `lib/widgets/wp_segmented_selector.dart`, which
/// page 3 reuses for it). Content only — navigation (Back/Next) is owned by
/// the onboarding shell, so this widget renders no CTA of its own.
class WelcomeStep extends ConsumerWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;

    void selectLocale(String locale) {
      HapticFeedback.selectionClick();
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(locale: locale));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Brand lockup — the only centred element on the page, mirroring the
        // reference's centred wordmark over start-aligned content. The claim
        // reads as a quiet second line of the lockup instead of a second
        // headline: the beat titles below already carry that message, so
        // shouting it here is what made the page feel packed.
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WpBrandWordmark(height: 44),
              const SizedBox(height: WpSpacing.sm),
              Text(
                l10n.onboardingWelcome,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: WpTypography.heading,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: WpSpacing.xxl),

        // Three demo beats in the Conductor-style asymmetric composition:
        // a start-aligned vertical list of titles + captions on one side,
        // ONE large media area for the active beat on the other. Captions
        // are rendered by Flutter (l10n, incl. RTL) — never baked into the
        // artwork.
        const _BeatShowcase(),
        const SizedBox(height: WpSpacing.xl),

        // Language selector — items derived from L10n.supportedLocales so
        // adding a new language is an ARB-only change.  Rendered as a
        // compact dropdown without flag icons (see widget docs).
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: kOnboardingContentInset,
          ),
          child: SizedBox(
            width: _kLanguageSelectorWidth,
            child: LanguageSelector(
              currentLocale: settings.locale,
              onChanged: selectLocale,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Beat showcase — asymmetric two-column layout (Conductor reference).
// =============================================================================

/// The three demo beats: a vertical, start-aligned list of title + caption
/// blocks on the start side and ONE large media area on the end side that
/// shows the active beat's placeholder.
///
/// Activation is click/tap-driven (first beat active on appear) rather than
/// timer-driven: deterministic, testable, and inherently reduce-motion-safe
/// — the only motion is the media cross-fade, which collapses to an instant
/// swap via [WpMotion.durationFor]. All three titles + captions stay in the
/// widget/semantics tree at all times — inactive beats are only visually
/// de-emphasised (muted text colors), never hidden, so screen readers and
/// keyboard users always reach the full content. Each tile is a focusable
/// button (InkWell), so keyboard users can also switch the media area.
///
/// Under RTL the plain [Row] mirrors via ambient [Directionality]: the text
/// list moves to the right, the media area to the left — no hard-coded
/// left/right anywhere.
class _BeatShowcase extends StatefulWidget {
  const _BeatShowcase();

  @override
  State<_BeatShowcase> createState() => _BeatShowcaseState();
}

class _BeatShowcaseState extends State<_BeatShowcase> {
  int _activeIndex = 0;

  void _activate(int index) {
    if (index == _activeIndex) return;
    HapticFeedback.selectionClick();
    setState(() => _activeIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    final beats = [
      (
        icon: LucideIcons.audioLines,
        title: l10n.onboardingBeat1Title,
        caption: l10n.onboardingBeat1Caption,
      ),
      (
        icon: LucideIcons.cpu,
        title: l10n.onboardingBeat2Title,
        caption: l10n.onboardingBeat2Caption,
      ),
      (
        icon: LucideIcons.appWindow,
        title: l10n.onboardingBeat3Title,
        caption: l10n.onboardingBeat3Caption,
      ),
    ];

    // Gentle fade-in instead of a hard pop. With "Reduce Motion" active,
    // WpMotion.durationFor collapses the duration to zero — the showcase
    // appears instantly, exactly like the future loop will fall back to a
    // still.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      curve: WpMotion.smooth_,
      builder: (context, opacity, child) =>
          Opacity(opacity: opacity, child: child),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Text list — start-aligned, one tile per beat. The highlight box
          // bleeds outward past the text (like the reference): the tile's own
          // horizontal padding is what [kOnboardingContentInset] adds back to
          // the controls below, so beat text and controls share one start
          // edge while the highlight reads as a surface behind them.
          Expanded(
            flex: 5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < beats.length; i++) ...[
                  if (i > 0) const SizedBox(height: WpSpacing.md),
                  // loam-ignore: a11y-interactive-semantics – semantics provided in _BeatListTile.build
                  _BeatListTile(
                    key: onboardingBeatTileKey(i),
                    title: beats[i].title,
                    caption: beats[i].caption,
                    active: i == _activeIndex,
                    onTap: () => _activate(i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.xxl),
          // ONE large media area for the active beat. AnimatedSwitcher
          // cross-fades between placeholders; with "Reduce Motion" the
          // duration collapses to zero (instant swap, no movement).
          Expanded(
            flex: 3,
            child: AnimatedSwitcher(
              duration: WpMotion.durationFor(context, WpMotion.smooth),
              switchInCurve: WpMotion.smooth_,
              switchOutCurve: WpMotion.smooth_,
              child: _BeatMediaPlaceholder(
                key: onboardingBeatMediaKey(_activeIndex),
                icon: beats[_activeIndex].icon,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the beat text list: title + caption, start-aligned.
///
/// The active tile gets a subtle card background — no border: in the
/// reference the highlighted feature block is a fill alone, and stacking a
/// border on top of it is what turned three quiet text blocks into three
/// competing boxes. Inactive tiles keep muted text colors but remain fully
/// rendered and tappable — they are never removed from the semantics tree.
class _BeatListTile extends StatelessWidget {
  const _BeatListTile({
    super.key,
    required this.title,
    required this.caption,
    required this.active,
    required this.onTap,
  });

  final String title;
  final String caption;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? WpColorsDark.textPrimary
        : WpColorsLight.textPrimary;
    final textSecondary = isDark
        ? WpColorsDark.textSecondary
        : WpColorsLight.textSecondary;
    final textMuted = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);

    return Semantics(
      button: true,
      selected: active,
      label: '$title. $caption',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: WpRadius.borderLg,
        child: AnimatedContainer(
          duration: WpMotion.durationFor(context, WpMotion.fast),
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: kOnboardingContentInset,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: active ? surface : Colors.transparent,
            borderRadius: WpRadius.borderLg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: WpTypography.subheading,
                  fontWeight: FontWeight.w600,
                  color: active ? textPrimary : textSecondary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              Text(
                caption,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: active ? textSecondary : textMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder media surface — replaced 1:1 by the pre-rendered loop asset.
///
/// The asset-production ticket swaps ONLY this widget's content for a
/// pre-rendered animated loop (`Image.asset`, animated WebP/GIF in a
/// light/dark variant) — the surrounding showcase structure, the l10n
/// captions and the reduced-motion seam stay as they are:
/// `MediaQuery.of(context).disableAnimations` (already consulted through
/// [WpMotion.durationFor] for fade-in and cross-fade) is the switch that
/// must then show a still frame instead of the loop.
class _BeatMediaPlaceholder extends StatelessWidget {
  const _BeatMediaPlaceholder({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.5);
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;

    return AspectRatio(
      // 16:9 — the single large media area (the old three-up tiles used a
      // flatter 21:9 to fit three in a row; one big area affords more
      // height while still fitting the fixed 1100×720 onboarding window).
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        // Borderless, like the reference's screenshot panel: the loop asset
        // that replaces this placeholder brings its own edges, and an outline
        // around a still-empty surface only makes the page read as boxes.
        decoration: BoxDecoration(
          color: surface,
          borderRadius: WpRadius.borderLg,
        ),
        child: Center(
          child: Icon(
            icon,
            size: WpIconSize.xxl,
            color: accent.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}
