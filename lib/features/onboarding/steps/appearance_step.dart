import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/navigation/page_state.dart';
import '../../../core/onboarding/onboarding_surface.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/overlay_preview.dart';
import '../../../widgets/wp_text_link.dart';
import '../../settings/settings_widgets.dart';
import '../../settings/widgets/overlay_theme_swatches.dart';
import 'autostart_toggle.dart';
import 'onboarding_page_fill.dart';

/// Viewport height (the page's offered height, see [OnboardingPageFill]) at
/// which the whole page, overlay preview included, fits without scrolling.
///
/// Measured at text scale 1.0: with the full preview the page needs 628 px
/// (the colour row carries the swatch names, which made the page taller than
/// the 520 px this used to assume). Below this the preview is the
/// last block, so the scroll viewport's edge cuts it in half, which reads as
/// broken; the preview is left out instead. The rows above it stay, and the
/// swatch names stay with them.
const double kAppearanceStepPreviewMinHeight = 628;

/// Viewport height at which the compact one-line preview (pill only, no
/// frame, see [WpOverlayRealPreview.compact]) fits, measured at text scale 1.0
/// (600 px fits, 599 px does not). Below it the page shows a short hint
/// instead, pointing to the same preview in Settings.
const double kAppearanceStepCompactPreviewMinHeight = 600;

/// Height of the compact pill box. The pill scales down into it.
const double kAppearanceStepCompactPreviewHeight = 40;

/// Test ids of the hint tier: the plain hint on a first run, and the link
/// that appears only in a manual review or a revision run.
const kAppearanceStepHintTextId = 'onboarding-appearance-settings-hint';
const kAppearanceStepHintLinkId = 'onboarding-appearance-settings-link';

/// Row id of the overlay rows in Settings › Darstellung (the anchor the
/// recording screen's "open settings" links use for the overlay).
const kAppearanceStepOverlayStartRowId = 'appearance-overlay-start';

/// Leaves the onboarding surface and opens Settings › Darstellung at the
/// overlay rows, the same way the recording screen's settings links do.
///
/// Only reachable from the link, which exists in a manual review or a
/// revision run. On a first run there is no link, so the flow is never left
/// from here and `onboardingCompleted` stays false until the flow ends.
void _openAppearanceSettings(WidgetRef ref) {
  // A revision run stays unstamped when the link leaves it (see
  // [leaveOnboardingSurface]): the revision is offered again on the next start.
  unawaited(leaveOnboardingSurface(ref, markRevisionSeen: false));
  ref
      .read(settingsScrollTargetProvider.notifier)
      .set(kAppearanceStepOverlayStartRowId);
  ref.read(activePageProvider.notifier).setPage('settings');
}

/// Which form of the live preview the appearance page shows.
enum _PreviewTier { full, compact, hint }

/// Key prefix of the overlay position dropdown and its items.
const kAppearanceStepOverlayPositionDropdownId =
    'appearanceStepOverlayPositionDropdown';

/// Widget keys exposed for testing.
@visibleForTesting
const kAppearanceStepOverlayPositionKey = Key('appearanceStepOverlayPosition');
@visibleForTesting
const kAppearanceStepOverlaySizeKey = Key('appearanceStepOverlaySize');
@visibleForTesting
const kAppearanceStepOverlayColorsKey = Key('appearanceStepOverlayColors');

/// Content of the Appearance onboarding page: launch-at-login, and the
/// recording overlay's position, size and style.
///
/// The autostart toggle ([OnboardingAutostartToggle]) is unchanged from
/// before this step gained a second block. The three overlay rows below it
/// reuse [OverlaySection]'s widget pattern (`lib/features/settings/sections/
/// overlay_button_section.dart`) — same dropdowns, same settings — so a
/// change here and in Settings are the same write, never two definitions that
/// can drift.
///
/// No per-row subtitles (see the class-level accessibility finding below —
/// those were verified to overflow the fixed onboarding window at enlarged
/// text scale). The real overlay preview *is* included, mirroring Settings'
/// [OverlaySection] placement (right under the style row) -- the page
/// content already sits inside a scrolling container
/// (`onboarding_overlay.dart`'s `SingleChildScrollView`), so the preview
/// scrolling into view at large text scale is an accepted fallback, not the
/// hard `RenderFlex` overflow the subtitles caused.
class AppearanceStep extends ConsumerWidget {
  const AppearanceStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    // Null outside a page (standalone tests): the preview is then shown.
    final viewport = OnboardingPageFill.availableHeightOf(context);
    // A manual review or a revision run may link out to Settings; a first run
    // shows the hint as plain text only.
    final manualReview = ref.watch(onboardingManuallyOpenProvider);
    final revisionRun = ref.watch(onboardingRevisionRunProvider);
    final linkMode = manualReview || revisionRun;
    // Only a manual review that is not also a revision run may say the link
    // ends setup; a revision run never makes that claim, even if both flags are set.
    final endsSetup = manualReview && !revisionRun;
    final previewTier = viewport == null
        ? _PreviewTier.full
        : viewport >= kAppearanceStepPreviewMinHeight
        ? _PreviewTier.full
        : viewport >= kAppearanceStepCompactPreviewMinHeight
        ? _PreviewTier.compact
        : _PreviewTier.hint;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The column is as wide as its widest row and every label fills it,
        // so the controls share one column right after the longest text, as
        // on the privacy page (Maintainer 3b, replaces XP-6-03). Center gives
        // IntrinsicWidth the loose width it needs to size to its rows.
        Center(
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnboardingAutostartToggle(),
                const SizedBox(height: WpSpacing.md),
                SettingRow(
                  key: kAppearanceStepOverlayPositionKey,
                  icon: LucideIcons.mapPin,
                  iconSize: WpIconSize.md,
                  label: l10n.settingsOverlayStartPosition,
                  // Same consolidated picker as Settings: "Off" is an entry of its
                  // own, so choosing a position is the visible way the overlay gets
                  // switched on, never a silent side effect.
                  trailing: settingsDropdown(
                    context: context,
                    keyPrefix: kAppearanceStepOverlayPositionDropdownId,
                    value: settings.effectiveOverlayMode == OverlayMode.floating
                        ? settings.overlayStartPositionType.value
                        : OverlayStartPosition.off.value,
                    items: OverlayStartPosition.values
                        .map((e) => e.value)
                        .toList(),
                    labels: [
                      l10n.settingsOff,
                      l10n.settingsOverlayStartTopCenter,
                      l10n.settingsOverlayStartBottomCenter,
                      l10n.settingsOverlayStartLastPosition,
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      final notifier = ref.read(settingsProvider.notifier);
                      if (v == OverlayStartPosition.off.value) {
                        notifier.updateSettings(
                          (s) => s.copyWith(
                            overlayMode: OverlayMode.off.value,
                            showOverlay: false,
                          ),
                        );
                      } else {
                        notifier.updateSettings(
                          (s) => s.copyWith(
                            overlayMode: OverlayMode.floating.value,
                            showOverlay: true,
                            overlayStartPosition: v,
                          ),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                SettingRow(
                  key: kAppearanceStepOverlaySizeKey,
                  icon: LucideIcons.maximize2,
                  iconSize: WpIconSize.md,
                  label: l10n.settingsOverlaySize,
                  trailing: settingsDropdown(
                    context: context,
                    value: settings.overlaySizeType.value,
                    items: FloatingOverlaySize.values
                        .map((e) => e.value)
                        .toList(),
                    labels: [
                      l10n.settingsOverlaySizeNormal,
                      l10n.settingsOverlaySizeCompact,
                      l10n.settingsOverlaySizeMini,
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref
                          .read(settingsProvider.notifier)
                          .updateSettings((s) => s.copyWith(overlaySize: v));
                    },
                  ),
                ),
                const SizedBox(height: WpSpacing.xs),
                // Only the background row here: one set of four swatches fits on one
                // line of the fixed onboarding window. The wave colour is chosen in
                // Settings, next to the other overlay options.
                SettingRow(
                  key: kAppearanceStepOverlayColorsKey,
                  icon: LucideIcons.sparkles,
                  iconSize: WpIconSize.md,
                  label: l10n.settingsOverlayBackground,
                  trailing: WpOverlayBackgroundSwatches(
                    value: settings.overlayBackgroundType,
                    onChanged: (preset) =>
                        pickOverlayBackground(context, ref, settings, preset),
                  ),
                ),
              ],
            ),
          ),
        ),
        switch (previewTier) {
          _PreviewTier.full => Column(
            children: [
              const SizedBox(height: WpSpacing.xs),
              // Fixed, text-scale-immune height cap: unlike the SettingRows
              // above, this preview is a graphic, not text, so it must not
              // grow with the system font size. WpOverlayRealPreview's own
              // FittedBox(fit: scaleDown) does the shrinking; this box only
              // gives it a shorter target than its natural ~104 px, which keeps
              // the page inside the fixed 1100x720 window at the text scales
              // `onboarding_overlay_test.dart` exercises.
              SizedBox(
                height: 56,
                child: WpOverlayRealPreview(
                  size: settings.overlaySizeType,
                  background: settings.overlayBackgroundType,
                  wave: settings.overlayWaveType,
                ),
              ),
            ],
          ),
          _PreviewTier.compact => Column(
            children: [
              const SizedBox(height: WpSpacing.xs),
              SizedBox(
                height: kAppearanceStepCompactPreviewHeight,
                child: WpOverlayRealPreview(
                  size: settings.overlaySizeType,
                  background: settings.overlayBackgroundType,
                  wave: settings.overlayWaveType,
                  compact: true,
                ),
              ),
            ],
          ),
          _PreviewTier.hint => Column(
            children: [
              // xxs, not xs: the link's 48 px target already gives the row room,
              // and the page must still fit the fixed window at text scale 1.0.
              const SizedBox(height: WpSpacing.xxs),
              if (linkMode)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  // WpTextLink carries its own 48 px touch target, so the link
                  // is that tall in layout too; the page budget accounts for it.
                  child: WpTextLink(
                    testID: kAppearanceStepHintLinkId,
                    // The parenthetical "ends setup" is true only for a manual
                    // review. A revision run is shown again later, so its link
                    // says that instead.
                    label: endsSetup
                        ? l10n.onboardingAppearanceSettingsLink
                        : l10n.onboardingAppearanceSettingsLinkRevision,
                    onPressed: () => _openAppearanceSettings(ref),
                  ),
                )
              else
                Semantics(
                  identifier: kAppearanceStepHintTextId,
                  child: Text(
                    l10n.onboardingAppearanceSettingsHint,
                    style: const TextStyle(
                      fontSize: WpTypography.small,
                      fontFamily: kWpUiFont,
                      fontFamilyFallback: kWpFontFallback,
                      height: 1.4,
                    ).copyWith(color: WpColors.textMuted),
                  ),
                ),
            ],
          ),
        },
      ],
    );
  }
}
