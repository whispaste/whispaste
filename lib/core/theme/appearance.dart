/// Maps the persisted [AppearanceMode] to a colour set (AR-21).
library;

import 'package:flutter/widgets.dart';

import '../config/settings_enums.dart';
import 'theme_colors.dart';

/// The colour set for [mode]; [platform] only matters for
/// [AppearanceMode.system].
WpThemeColors colorsForAppearance(AppearanceMode mode, Brightness platform) =>
    switch (mode) {
      AppearanceMode.light => wpLightColors,
      AppearanceMode.dark => wpDarkColors,
      AppearanceMode.navy => wpNavyColors,
      AppearanceMode.system =>
        platform == Brightness.dark ? wpDarkColors : wpLightColors,
    };

/// The colour set the app paints with: the onboarding stage while the
/// onboarding surface is on top, the user's own set otherwise.
///
/// The stage is always the navy stage ([wpDarkColors], the `WpColorsDark`
/// palette), whatever the user's appearance is. The navy frame with light
/// content (the default "Marine" look) put dark text on a dark stage, which
/// is what made the first-run pages unreadable on the Mac preview (MP-1). A
/// single palette for the whole surface keeps every shared `Wp*` widget that
/// the onboarding shows on the same stage. See `lib/DESIGN.md`, "Onboarding
/// stage".
WpThemeColors effectiveColorsFor({
  required bool onboardingStage,
  required AppearanceMode mode,
  required Brightness platform,
}) => onboardingStage ? wpDarkColors : colorsForAppearance(mode, platform);
