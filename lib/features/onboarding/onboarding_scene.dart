// The building blocks of the scenes on the painted panel of the split pages:
// the navy card with real text, the waveform pill and the promise stickers.
// Each page composes its own scene from them, so the pages share one
// language without repeating one picture (maintainer, 2026-10-30).
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/generated/wp_tokens.g.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/level_history/level_history_bars.dart';

/// Width of the scene's card on the panel.
const double kOnboardingSceneWidth = 360;

/// The card above the pill: a small [label] and a dictated [text]. [lit]
/// runs from 0 (a muted example) to 1 (bright, as if it had just landed);
/// on the way up a caret shows at the end of the text once, which reduced
/// motion skips with the transition.
class OnboardingSceneCard extends StatelessWidget {
  const OnboardingSceneCard({
    super.key,
    required this.label,
    required this.text,
    this.lit = 1,
  });

  final String label;
  final String text;
  final double lit;

  @override
  Widget build(BuildContext context) {
    const stage = wpStagePalette;
    final caret = math.sin(math.pi * lit.clamp(0.0, 1.0));
    return DecoratedBox(
      decoration: BoxDecoration(
        // The floating material of dialogs (website `surface.floating`), so
        // the card matches the stage's navy.
        color: WpColors.floatingSurface,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: stage.borderSubtle),
        boxShadow: WpShadows.overlay,
      ),
      child: Padding(
        padding: const EdgeInsets.all(WpSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: WpTypography.caption,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: stage.textMuted,
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
            AnimatedSwitcher(
              duration: WpMotion.durationFor(context, WpMotion.hoverIn),
              layoutBuilder: (current, previous) => Stack(
                alignment: AlignmentDirectional.topStart,
                children: [...previous, ?current],
              ),
              child: Text.rich(
                key: ValueKey(text),
                TextSpan(
                  text: text,
                  children: [
                    if (caret > 0.01)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          width: 2,
                          height: 18,
                          margin: const EdgeInsetsDirectional.only(start: 2),
                          color: WpColors.action.withValues(alpha: caret),
                        ),
                      ),
                  ],
                ),
                style: TextStyle(
                  fontSize: WpTypography.rowTitle,
                  height: 1.45,
                  color: Color.lerp(
                    stage.textMuted.withValues(alpha: 0.6),
                    stage.textPrimary,
                    lit,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The waveform pill below the card. It paints the shared level history
/// ([WpLevelHistoryView], the same element as the recording overlay): live
/// [level] values scroll in as bars, [pulse] drives the resting shape, and
/// without either the pill rests in its fixed shape. [lit] runs from 0 (muted
/// grey: nothing is listening) to 1 (amber).
class OnboardingWavePill extends StatefulWidget {
  const OnboardingWavePill({
    super.key,
    this.pulse,
    this.level,
    this.lit = 1,
    this.scale = 1,
  });

  final Animation<double>? pulse;
  final double? level;
  final double lit;

  /// Size factor; the live pill of the microphone test is larger.
  final double scale;

  static const _heights = <double>[6, 12, 18, 10, 22, 14, 8, 16, 20, 9, 13, 6];
  static const double _fullHeight = 24;

  static double _rest(int i) => _heights[i] / _fullHeight;

  /// Each bar runs a little behind its left neighbour, so the pulse travels.
  static double _phase(double t, int i) =>
      0.5 + 0.5 * math.sin((t + i * 0.12) * math.pi * 2);

  @override
  State<OnboardingWavePill> createState() => _OnboardingWavePillState();
}

class _OnboardingWavePillState extends State<OnboardingWavePill> {
  /// Newest level last; one bar per resting-shape bar.
  List<double> _history = WpLevelHistory.zeros(
    OnboardingWavePill._heights.length,
  );

  @override
  void didUpdateWidget(OnboardingWavePill old) {
    super.didUpdateWidget(old);
    final level = widget.level;
    if (level != null && level != old.level) {
      _history = WpLevelHistory.push(_history, level);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pill = widget;
    final count = OnboardingWavePill._heights.length;
    final color = Color.lerp(
      wpStagePalette.textMuted.withValues(alpha: 0.45),
      WpPalette.amber400,
      pill.lit,
    )!;
    Widget bars(List<double> levels) => WpLevelHistoryView(
      levels: levels,
      color: color,
      width: count * 6 * pill.scale - 3 * pill.scale,
      height: OnboardingWavePill._fullHeight * pill.scale,
      lineStrokeMin: 2 * pill.scale,
    );
    final pulse = pill.pulse;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: wpStagePalette.surfaceSunken,
        borderRadius: WpRadius.borderFull,
        boxShadow: WpShadows.overlay,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: WpSpacing.md * pill.scale,
          vertical: WpSpacing.xs * pill.scale,
        ),
        child: pill.level != null
            ? bars(_history)
            : pulse != null
            ? AnimatedBuilder(
                animation: pulse,
                builder: (context, _) => bars([
                  for (var i = 0; i < count; i++)
                    OnboardingWavePill._rest(i) *
                        (0.55 +
                            0.45 * OnboardingWavePill._phase(pulse.value, i)),
                ]),
              )
            : bars([
                for (var i = 0; i < count; i++)
                  OnboardingWavePill._rest(i) * 0.8,
              ]),
      ),
    );
  }
}

/// Card above pill, centred on the panel at [kOnboardingSceneWidth]: the
/// scene of the personal page.
class OnboardingScene extends StatelessWidget {
  const OnboardingScene({super.key, required this.card, required this.pill});

  final Widget card;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: WpSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kOnboardingSceneWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              card,
              const SizedBox(height: WpSpacing.md),
              Center(child: pill),
            ],
          ),
        ),
      ),
    );
  }
}

/// A promise of WhisPaste (open source, runs locally) as a sticker, the
/// website hero's language: an amber marker pill with an icon, stuck at a
/// slight [angle] onto the corner of a scene element. It drops in once with
/// a little over-rotation and settles; reduced motion shows it settled. A
/// label, not a control: no hover, no cursor, read as plain text.
class OnboardingSticker extends StatelessWidget {
  const OnboardingSticker({
    super.key,
    required this.icon,
    required this.text,
    this.angle = 0.1,
  });

  final IconData icon;
  final String text;

  /// Tilt in radians; the sticker settles at it.
  final double angle;

  @override
  Widget build(BuildContext context) {
    final sticker = DecoratedBox(
      decoration: BoxDecoration(
        color: WpColors.highlight,
        borderRadius: WpRadius.borderFull,
        boxShadow: WpShadows.overlay,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.md,
          vertical: WpSpacing.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Icon(icon, size: WpIconSize.sm, color: WpColors.onCta),
            ),
            const SizedBox(width: WpSpacing.xs),
            Text(
              text,
              style: TextStyle(
                fontSize: WpTypography.body,
                fontWeight: FontWeight.w700,
                color: WpColors.onCta,
              ),
            ),
          ],
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: WpMotion.durationFor(
        context,
        const Duration(milliseconds: 700),
      ),
      curve: Curves.easeOutBack,
      child: sticker,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -28 * (1 - t)),
          child: Transform.rotate(
            angle: angle + 0.2 * (1 - t),
            child: Transform.scale(scale: 1 + 0.15 * (1 - t), child: child),
          ),
        ),
      ),
    );
  }
}
