import 'dart:math' as math;

// Onboarding v6 from screen 2 on: the split composition. The copy column and
// the one amber action sit on the navy stage on the left; a painted light
// panel with a clean rounded edge rises on the stage on the right (only
// screen 1 fades its painting into the stage). The model download shows as a
// slim pill at the top of the panel while it loads or failed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/colors.dart';
import '../../core/theme/generated/wp_tokens.g.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import 'onboarding_download_footer.dart';
import 'onboarding_download_provider.dart';
import 'onboarding_download_status.dart';
import 'steps/onboarding_headings.dart'
    show OnboardingHeadingFocus, onboardingCompactText;

/// The copy column has the width of screen 1, so every page starts and ends
/// on the same edges.
const double kOnboardingCopyWidth = 440;
const double _kCopyInset = 64;

/// Side by side from this width on; narrower windows drop the panel and the
/// copy comes first.
const double _kSplitWidth = 801;

/// One page of the split composition. [copy] is the column content, [panel]
/// the decorative scene over the painting [panelAsset]; assistive technology
/// skips the scene, it only repeats the copy.
class OnboardingSplitPage extends StatelessWidget {
  const OnboardingSplitPage({
    super.key,
    required this.copy,
    required this.panelAsset,
    required this.panel,
    this.showDownloadPill = true,
  });

  final Widget copy;
  final String panelAsset;
  final Widget panel;

  /// `false` where the page shows the download state itself (the try-out
  /// page's lock card), so progress and retry never appear twice.
  final bool showDownloadPill;

  @override
  Widget build(BuildContext context) {
    Widget column(double minHeight, {required double insetStart}) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                start: insetStart,
                end: WpSpacing.xl,
                top: WpSpacing.xl,
                bottom: WpSpacing.xl,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kOnboardingCopyWidth,
                ),
                child: copy,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _kSplitWidth) {
          return Stack(
            children: [
              column(0, insetStart: WpSpacing.xl),
              if (showDownloadPill)
                const PositionedDirectional(
                  start: 0,
                  end: 0,
                  bottom: WpSpacing.lg,
                  child: Center(child: OnboardingDownloadPill()),
                ),
            ],
          );
        }
        final w = constraints.maxWidth;
        final copyWidth = w * 0.46 > _kCopyInset + kOnboardingCopyWidth
            ? w * 0.46
            : _kCopyInset + kOnboardingCopyWidth + WpSpacing.xl;
        return Stack(
          children: [
            PositionedDirectional(
              start: copyWidth,
              top: WpSpacing.md,
              end: WpSpacing.md,
              bottom: WpSpacing.md,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: WpRadius.borderXl,
                          child: Image.asset(
                            panelAsset,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerRight,
                            excludeFromSemantics: true,
                          ),
                        ),
                        panel,
                      ],
                    ),
                  ),
                  // Outside the excluded scene: the status and its retry
                  // stay readable.
                  if (showDownloadPill)
                    const PositionedDirectional(
                      start: 0,
                      end: 0,
                      top: WpSpacing.lg,
                      child: Center(child: OnboardingDownloadPill()),
                    ),
                ],
              ),
            ),
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              width: copyWidth,
              child: column(constraints.maxHeight, insetStart: _kCopyInset),
            ),
          ],
        );
      },
    );
  }
}

/// The page heading of the split pages, the size of screen 1's.
class OnboardingSplitHeading extends StatelessWidget {
  const OnboardingSplitHeading(this.text, {super.key, required this.testId});

  final String text;
  final String testId;

  @override
  Widget build(BuildContext context) {
    final compact = onboardingCompactText(context);
    // Focus lands on the heading when the page appears, so a screen reader
    // announces the new page (V09); the shell keys pages by step, so this
    // runs once per page.
    return OnboardingHeadingFocus(
      child: Semantics(
        header: true,
        identifier: testId,
        child: Text(
          text,
          style: TextStyle(
            fontSize: compact ? WpTypography.headline : 38,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: compact ? 0 : -0.6,
            color: WpColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// Back as a quiet link above the question, so the one primary action
/// stands alone below the answers.
class OnboardingBackLink extends StatelessWidget {
  const OnboardingBackLink({
    super.key,
    required this.testId,
    required this.label,
    required this.onPressed,
  });

  final String testId;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.md),
      child: Transform.translate(
        offset: const Offset(-kOnboardingGhostLinkInset, 0),
        child: WpButton(
          testId: testId,
          label: label,
          icon: LucideIcons.arrowLeft,
          variant: WpButtonVariant.ghost,
          tone: WpButtonTone.neutral,
          size: WpButtonSize.dense,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// The start padding of a dense ghost [WpButton] (its `ghostPaddingX`).
/// Text links on the copy side shift left by exactly this much, so their icon
/// lines up with the text edge above instead of the button's hit box.
const double kOnboardingGhostLinkInset = WpSpacing.xs;

/// The download status as a navy pill, shown only while the model loads or
/// the download failed.
class OnboardingDownloadPill extends ConsumerWidget {
  const OnboardingDownloadPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(onboardingDownloadStatusProvider).phase;
    final visible = switch (phase) {
      OnboardingDownloadPhase.running ||
      OnboardingDownloadPhase.verifying ||
      OnboardingDownloadPhase.failed => true,
      OnboardingDownloadPhase.idle || OnboardingDownloadPhase.ready => false,
    };
    final pill = AnimatedSwitcher(
      duration: WpMotion.durationFor(context, WpMotion.smooth),
      child: !visible
          ? const SizedBox.shrink()
          : DecoratedBox(
              decoration: BoxDecoration(
                color: wpStagePalette.surfaceSunken,
                borderRadius: WpRadius.borderFull,
                border: Border.all(color: wpStagePalette.borderSubtle),
                boxShadow: WpShadows.overlay,
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.xs,
                ),
                child: OnboardingDownloadFooter(showReady: false),
              ),
            ),
    );
    return visible ? _PillArrival(child: pill) : pill;
  }
}

/// The first time the download pill shows up, it arrives instead of just
/// being there (maintainer 2026-10-30: after the download starts on the first
/// page, nobody noticed it had moved up to the right). It slides in from the
/// copy side, settles from a slightly larger size and rings three times in
/// the action colour, then rests. Later pages show it plainly; with reduced
/// motion it never moves.
class _PillArrival extends StatefulWidget {
  const _PillArrival({required this.child});

  final Widget child;

  @override
  State<_PillArrival> createState() => _PillArrivalState();
}

class _PillArrivalState extends State<_PillArrival>
    with SingleTickerProviderStateMixin {
  // Once per app run: every split page has its own pill, only the first one
  // that appears announces the move.
  static bool _announced = false;

  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_announced) return;
    _announced = true;
    if (!MediaQuery.disableAnimationsOf(context)) _arrive.forward();
  }

  @override
  void dispose() {
    _arrive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context) == TextDirection.rtl ? 1.0 : -1.0;
    return AnimatedBuilder(
      animation: _arrive,
      builder: (context, child) {
        final v = _arrive.value;
        if (v == 0 || v == 1) return child!;
        // 0..0.3: travel in and settle; 0.3..1: three rings.
        final travel = Curves.easeOutCubic.transform((v / 0.3).clamp(0, 1));
        final ring = v < 0.3
            ? 0.0
            : math.sin((v - 0.3) / 0.7 * 3 * math.pi).abs();
        return Transform.translate(
          offset: Offset(dir * 160 * (1 - travel), 0),
          child: Transform.scale(
            scale: 1 + 0.25 * (1 - travel),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child!,
                // The ring is an edge outside the control, pushed out by
                // scale and faded by opacity. No blur, no spread (§7).
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: 1 + 0.08 * ring,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: WpRadius.borderFull,
                          border: Border.all(
                            color: WpColors.accentLocatorRing.withValues(
                              alpha: WpColors.accentLocatorRing.a * ring,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}
