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
