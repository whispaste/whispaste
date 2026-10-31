import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/overlay_preview.dart';
import '../../settings/settings_widgets.dart';
import 'autostart_toggle.dart';

/// Widget keys exposed for testing.
@visibleForTesting
const kAppearanceStepOverlayPositionKey = Key('appearanceStepOverlayPosition');
@visibleForTesting
const kAppearanceStepOverlaySizeKey = Key('appearanceStepOverlaySize');
@visibleForTesting
const kAppearanceStepOverlayStyleKey = Key('appearanceStepOverlayStyle');

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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OnboardingAutostartToggle(),
        const SizedBox(height: WpSpacing.lg),
        SettingRow(
          key: kAppearanceStepOverlayPositionKey,
          icon: LucideIcons.mapPin,
          iconSize: WpIconSize.md,
          trailingHugsLabel: true,
          label: l10n.settingsOverlayStartPosition,
          trailing: settingsDropdown(
            context: context,
            value: settings.overlayStartPositionType.value,
            items: OverlayStartPosition.values
                .where((e) => e != OverlayStartPosition.off)
                .map((e) => e.value)
                .toList(),
            labels: [
              l10n.settingsOverlayStartTopCenter,
              l10n.settingsOverlayStartBottomCenter,
              l10n.settingsOverlayStartLastPosition,
            ],
            onChanged: (v) {
              if (v == null) return;
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWith(
                      overlayMode: OverlayMode.floating.value,
                      showOverlay: true,
                      overlayStartPosition: v,
                    ),
                  );
            },
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        SettingRow(
          key: kAppearanceStepOverlaySizeKey,
          icon: LucideIcons.maximize2,
          iconSize: WpIconSize.md,
          trailingHugsLabel: true,
          label: l10n.settingsOverlaySize,
          trailing: settingsDropdown(
            context: context,
            value: settings.overlaySizeType.value,
            items: FloatingOverlaySize.values.map((e) => e.value).toList(),
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
        const SizedBox(height: WpSpacing.sm),
        SettingRow(
          key: kAppearanceStepOverlayStyleKey,
          icon: LucideIcons.sparkles,
          iconSize: WpIconSize.md,
          trailingHugsLabel: true,
          label: l10n.settingsOverlayStyle,
          trailing: settingsDropdown(
            context: context,
            value: settings.overlayStyleType.value,
            items: OverlayStyle.values.map((e) => e.value).toList(),
            labels: [
              l10n.settingsOverlayStyleGlass,
              l10n.settingsOverlayStyleSolid,
            ],
            onChanged: (v) {
              if (v == null) return;
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(overlayStyle: v));
            },
          ),
        ),
        const SizedBox(height: WpSpacing.xs),
        // Fixed, text-scale-immune height cap: unlike the SettingRows above,
        // this preview is a graphic, not text, so it must not grow with the
        // system font size the way its Settings-page counterpart is free to
        // (Settings has no fixed window budget). WpOverlayRealPreview's own
        // FittedBox(fit: scaleDown) does the actual shrinking -- this SizedBox
        // just gives it a shorter box to shrink into than its natural ~104 px
        // (pill + shadow padding + the widget's own padding), which is what
        // keeps this page inside the fixed 1100x720 window's remaining
        // vertical budget at the accessibility text scales
        // `onboarding_overlay_test.dart` exercises (measured: fits up to 1.3).
        SizedBox(
          height: 64,
          child: WpOverlayRealPreview(
            size: settings.overlaySizeType,
            style: settings.overlayStyleType,
          ),
        ),
      ],
    );
  }
}
