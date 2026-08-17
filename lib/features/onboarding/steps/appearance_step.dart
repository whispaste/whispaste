import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart';
import 'autostart_toggle.dart';

/// Widget keys exposed for testing.
@visibleForTesting
const kAppearanceStepOverlayPositionKey = Key(
  'appearanceStepOverlayPosition',
);
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
/// Deliberately no overlay preview and no per-row subtitles — see the
/// class-level accessibility finding below; both were verified to overflow
/// the fixed onboarding window at enlarged text scale.
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
      ],
    );
  }
}
