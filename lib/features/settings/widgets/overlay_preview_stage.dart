/// Labelled, non-interactive preview stage for the recording overlay and the
/// floating button (ticket).
///
/// Both elements sit on one fixed desktop-like backdrop, so the preview reads
/// as a preview and not as controls. [IgnorePointer] keeps them out of hit
/// testing, so they never show hover or pointer feedback. Overlay and button
/// share one row (the pill scales down when space is short) and stack only at
/// large text scales or in very narrow windows; the row follows the text
/// direction (RTL).
library;

import 'package:flutter/material.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/overlay_customization.dart';
import '../../../core/theme/overlay_design_spec.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/floating_button/floating_button_controller_interface.dart';
import '../../../widgets/floating_button/floating_button_view.dart';
import '../../../widgets/overlay_preview.dart';

/// Narrowest stage content width (at text scale 1) that keeps overlay and both
/// button previews side by side: the two buttons with their captions and the
/// gap between them, plus a pill scaled to roughly two thirds of its normal
/// size.
const double _minRowWidth = 520;

class WpOverlayPreviewStage extends StatelessWidget {
  const WpOverlayPreviewStage({
    super.key,
    required this.size,
    required this.background,
    required this.wave,
    required this.showButton,
    this.appearance = OverlayAppearance.defaults,
    this.buttonLook = FloatingButtonLook.defaults,
  });

  /// ticket appearance options shown in the overlay preview.
  final OverlayAppearance appearance;

  /// ticket floating-button look (size, shape, ring, resting opacity).
  final FloatingButtonLook buttonLook;

  final FloatingOverlaySize size;
  final OverlayBackground background;
  final OverlayWave wave;

  /// The floating button is Windows/macOS only; Linux shows the overlay alone.
  final bool showButton;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            l10n.settingsPreviewTitle,
            style: textTheme.titleSmall?.copyWith(color: WpColors.textPrimary),
          ),
        ),
        const SizedBox(height: WpSpacing.xxs),
        Text(
          l10n.settingsPreviewHint,
          style: textTheme.bodySmall?.copyWith(color: WpColors.textSecondary),
        ),
        const SizedBox(height: WpSpacing.sm),
        DecoratedBox(
          key: const ValueKey('overlay-preview-stage'),
          decoration: BoxDecoration(
            color: WpColorsDark.background,
            borderRadius: BorderRadius.circular(WpRadius.md),
            border: Border.all(color: WpColors.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(WpSpacing.md),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final overlay = _PreviewItem(
                  caption: l10n.settingsPreviewOverlayCaption,
                  child: IgnorePointer(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: WpOverlayRealPreview(
                        size: size,
                        background: background,
                        wave: wave,
                        appearance: appearance,
                        shrinkWrap: true,
                      ),
                    ),
                  ),
                );
                if (!showButton) return overlay;
                // Both states of the button: the resting look (ink mic, resting
                // opacity, no ring) and the recording look (wave-coloured stop
                // square and an outer ring, same size as the resting disc),
                // exactly as the native button shows them (BTN-REC).
                final button = _PreviewItem(
                  caption: l10n.settingsFloatingButtonSection,
                  child: Wrap(
                    spacing: WpSpacing.lg,
                    runSpacing: WpSpacing.md,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _PreviewItem(
                        caption: l10n.settingsPreviewButtonIdleCaption,
                        child: IgnorePointer(
                          child: WpFloatingButtonView(
                            key: const ValueKey(
                              'overlay-preview-floating-button-idle',
                            ),
                            state: FloatingButtonVisualState.idle,
                            diameter: buttonLook.diameter,
                            background: background,
                            wave: wave,
                            look: buttonLook,
                          ),
                        ),
                      ),
                      _PreviewItem(
                        caption: l10n.settingsPreviewButtonRecordingCaption,
                        child: IgnorePointer(
                          child: WpFloatingButtonView(
                            key: const ValueKey(
                              'overlay-preview-floating-button-recording',
                            ),
                            state: FloatingButtonVisualState.recording,
                            diameter: buttonLook.diameter,
                            background: background,
                            wave: wave,
                            look: buttonLook,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                // Side by side while the pill keeps a legible size; the pill
                // scales down a little before the row gives up. Large text
                // widens the button caption, so the threshold scales with it.
                final rowFits =
                    constraints.maxWidth >=
                    MediaQuery.textScalerOf(context).scale(_minRowWidth);
                if (!rowFits) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      overlay,
                      const SizedBox(height: WpSpacing.md),
                      button,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(child: overlay),
                    const SizedBox(width: WpSpacing.lg),
                    button,
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewItem extends StatelessWidget {
  const _PreviewItem({required this.caption, required this.child});

  final String caption;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          // The stage backdrop is fixed navy in both themes, so the caption
          // uses the dark palette's secondary text rather than the active one.
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: WpColorsDark.textSecondary),
        ),
        const SizedBox(height: WpSpacing.xxs),
        child,
      ],
    );
  }
}
