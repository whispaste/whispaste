/// Shared board for the ticket settings goldens: one colour set active, one
/// text scale, one surface. The set is applied through [WpColors.activate]
/// and [wpThemeFor] by the caller, so the board only lays out the child.
library;

import 'package:flutter/material.dart';

import 'package:whispaste/core/theme/theme.dart';
import 'package:whispaste/core/theme/theme_colors.dart';

/// Colour sets the goldens cover, keyed by the file-name suffix.
const Map<String, WpThemeColors> kSettingsGoldenSets = {
  'light': wpLightColors,
  'dark': wpDarkColors,
  'navy': wpNavyColors,
};

Widget settingsGoldenBoard({
  required WpThemeColors set,
  required Widget child,
  required Size size,
  required Key boundaryKey,
  double textScale = 1,
  EdgeInsets inset = const EdgeInsets.all(16),
  double? height,
}) {
  return Theme(
    data: wpThemeFor(set),
    child: RepaintBoundary(
      key: boundaryKey,
      // Content page colour: cards (`cardFill`) read as grey panels on it, as
      // in the settings reference.
      child: ColoredBox(
        color: set.surfaceElevated,
        child: Padding(
          padding: inset,
          // Width is fixed, height follows the content, so an overflow shows
          // up as a test failure instead of being clipped.
          child: SizedBox(
            width: size.width,
            height: height,
            child: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
