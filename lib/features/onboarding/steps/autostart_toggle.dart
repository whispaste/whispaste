import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../settings/settings_widgets.dart';

/// Widget key exposed for testing.
@visibleForTesting
const kOnboardingAutostartToggleKey = Key('onboardingAutostartToggle');

/// Autostart toggle card on the Autostart & Auto-Paste onboarding page.
///
/// Moved here from the former final `ReadyStep` unchanged in behaviour: a
/// simpler yes/no than Settings → Interface's never/normal/minimized
/// dropdown; picking "yes" here always means normal (not minimized) startup.
/// `startMinimized` keeps its default (`false`); the full dropdown remains
/// available later in Settings.
class OnboardingAutostartToggle extends ConsumerWidget {
  const OnboardingAutostartToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

    final surfaceVariant =
        (isDark ? WpColorsDark.surfaceVariant : WpColorsLight.surfaceVariant)
            .withValues(alpha: 0.55);
    final borderColor = isDark
        ? WpColorsDark.borderSubtle
        : WpColorsLight.borderSubtle;

    return Container(
      decoration: BoxDecoration(
        color: surfaceVariant,
        borderRadius: WpRadius.borderLg,
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      child: SettingRow(
        key: kOnboardingAutostartToggleKey,
        icon: LucideIcons.power,
        label: l10n.onboardingReadyAutostartToggle,
        subtitle: l10n.onboardingReadyAutostartToggleHint,
        semanticToggledValue: settings.launchAtStartup,
        trailing: settingsToggle(
          value: settings.launchAtStartup,
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .updateSettings((s) => s.copyWith(launchAtStartup: v)),
        ),
      ),
    );
  }
}
