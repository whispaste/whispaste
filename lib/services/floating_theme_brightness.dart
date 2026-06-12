/// Shared dark-mode resolution for the two floating surfaces (overlay + button).
///
/// Both surfaces must follow the system theme identically: an explicit
/// dark/light setting wins, while [ThemeMode.system] derives from the **live**
/// `platformBrightness`. Before this was shared, the floating button used
/// `themeMode != ThemeMode.light`, which mapped [ThemeMode.system] to dark
/// unconditionally — wrong on a light-mode system (issue 08, bug D5). Routing
/// both surfaces through this one function guarantees they never disagree.
library;

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/widgets.dart';

/// Resolves whether a floating surface should render dark for the given
/// [mode].
///
/// [platformBrightness] is injectable for tests; in production it defaults to
/// the live `PlatformDispatcher.platformBrightness`, the same source the
/// overlay already used.
bool resolveFloatingSurfaceIsDark(
  ThemeMode mode, {
  Brightness? platformBrightness,
}) {
  final brightness =
      platformBrightness ??
      WidgetsBinding.instance.platformDispatcher.platformBrightness;
  return switch (mode) {
    ThemeMode.dark => true,
    ThemeMode.light => false,
    ThemeMode.system => brightness == Brightness.dark,
  };
}
