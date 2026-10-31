// Onboarding v6, V12: the download status in the bottom bar of every screen
// (concept: "links Download-Stand"). Loading shows a bar with percent and the
// remaining time once it is measured; ready shows a check; a failure keeps
// the parts already downloaded and offers a retry.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/wp_button.dart';
import 'onboarding_download_provider.dart';
import 'onboarding_download_status.dart';
import 'onboarding_speech_consent.dart';

/// The download footer. Shows nothing while no download is relevant.
///
/// With [showReady] false it also stays empty once the model is ready, for
/// pages where the status is only news while something is still loading.
class OnboardingDownloadFooter extends ConsumerWidget {
  const OnboardingDownloadFooter({super.key, this.showReady = true});

  final bool showReady;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(onboardingDownloadStatusProvider);
    final l10n = L10n.of(context);
    return switch (status.phase) {
      OnboardingDownloadPhase.idle => const SizedBox.shrink(),
      OnboardingDownloadPhase.ready when !showReady => const SizedBox.shrink(),
      OnboardingDownloadPhase.running ||
      OnboardingDownloadPhase.verifying => _FooterLoading(status: status),
      OnboardingDownloadPhase.ready => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.check, size: WpIconSize.sm, color: WpColors.success),
          const SizedBox(width: WpSpacing.xs),
          Flexible(
            child: Text(
              l10n.onboardingDownloadReady,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: WpTypography.small,
                color: WpColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
      OnboardingDownloadPhase.failed => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.onboardingDownloadFailed,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: WpColors.error,
                ),
              ),
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          WpButton(
            testId: 'onboarding-download-retry',
            label: l10n.actionRetry,
            variant: WpButtonVariant.ghost,
            tone: WpButtonTone.neutral,
            size: WpButtonSize.dense,
            onPressed: () => unawaited(retryWelcomeSpeechDownload(ref)),
          ),
        ],
      ),
    };
  }
}

class _FooterLoading extends StatelessWidget {
  const _FooterLoading({required this.status});

  final OnboardingDownloadStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final percent = (status.fraction * 100).round();
    final remaining = status.remaining;
    final text = remaining == null
        ? l10n.onboardingPracticeModelLoading(percent)
        : l10n.onboardingPracticeModelLoadingEta(
            percent,
            (remaining.inSeconds / 60).ceil().clamp(1, 999),
          );
    final locale = Localizations.localeOf(context).toLanguageTag();
    final sizes = status.bytesTotal > 0
        ? ' · ${onboardingDownloadSize(status.bytesDone, locale)}'
              ' / ${onboardingDownloadSize(status.bytesTotal, locale)}'
        : '';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DownloadBar(fraction: status.fraction),
        const SizedBox(width: WpSpacing.sm),
        Flexible(
          child: Text(
            '$text$sizes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// A download size for the footer: whole MB below one GB, else GB with one
/// decimal in the locale's number format ("512 MB", "1,2 GB").
String onboardingDownloadSize(int bytes, String locale) {
  const mb = 1024 * 1024;
  const gb = 1024 * mb;
  if (bytes < gb) return '${NumberFormat('0', locale).format(bytes / mb)} MB';
  return '${NumberFormat('0.0', locale).format(bytes / gb)} GB';
}

/// The loading bar. The fill follows the progress smoothly, and a soft light
/// drifts slowly across it, so a slow line still visibly moves. With reduced
/// motion the fill jumps and the light stays off.
class _DownloadBar extends StatefulWidget {
  const _DownloadBar({required this.fraction});

  final double fraction;

  @override
  State<_DownloadBar> createState() => _DownloadBarState();
}

class _DownloadBarState extends State<_DownloadBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sheen = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _sheen.stop();
    } else if (!_sheen.isAnimating) {
      _sheen.repeat();
    }
  }

  @override
  void dispose() {
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 96,
      height: 6,
      child: ClipRRect(
        borderRadius: WpRadius.borderSm,
        child: Stack(
          children: [
            ColoredBox(
              color: WpColors.cardFillElevated,
              child: const SizedBox.expand(),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween(end: widget.fraction.clamp(0.0, 1.0)),
              duration: WpMotion.durationFor(context, WpMotion.dramatic),
              curve: WpMotion.spring,
              builder: (context, value, _) => FractionallySizedBox(
                widthFactor: value,
                child: ClipRRect(
                  borderRadius: WpRadius.borderSm,
                  child: reduced
                      ? ColoredBox(
                          color: WpColors.action,
                          child: const SizedBox.expand(),
                        )
                      : AnimatedBuilder(
                          animation: _sheen,
                          builder: (context, _) {
                            // The light travels from just before the fill to
                            // just past it, then rests briefly off the bar.
                            final x = -1.8 + 4.0 * _sheen.value;
                            return DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment(x - 0.8, 0),
                                  end: Alignment(x + 0.8, 0),
                                  colors: [
                                    WpColors.action,
                                    WpColors.surface,
                                    WpColors.action,
                                  ],
                                  stops: const [0.15, 0.5, 0.85],
                                ),
                              ),
                              child: const SizedBox.expand(),
                            );
                          },
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
