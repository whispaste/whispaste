/// Pure decisions for desktop window geometry at start-up and on onboarding
/// completion.
///
/// Extracted from `main.dart` (`_initDesktopWindow`) and `app.dart`
/// (`_debounceSaveWindowState`) so the onboarding-vs-regular geometry choice
/// is unit-testable without touching `window_manager` or any other native
/// API — callers apply the resolved values through the real platform
/// binding, this file only decides what they should be.
library;

import 'package:flutter/widgets.dart';

import '../config/settings_provider.dart';

/// Fixed size WhisPaste opens the onboarding window at, chosen to fit
/// reliably on a 1280 × 800 notebook including OS chrome, with three demo
/// beats laid out side by side rather than stacked (PRD "Entscheidungen aus
/// der Triage").
const Size kOnboardingWindowSize = Size(1100, 720);

/// What size/position/maximized-state the window should open at for the
/// given [settings].
class DesktopWindowGeometry {
  const DesktopWindowGeometry({
    required this.size,
    required this.position,
    required this.maximized,
  });

  final Size size;

  /// `null` means "let `window_manager` center it" — always the case for the
  /// fixed onboarding size, and also whenever no regular position was ever
  /// persisted.
  final Offset? position;

  final bool maximized;
}

/// Resolves the window geometry to apply for [settings].
///
/// While onboarding is unfinished this is always the fixed
/// [kOnboardingWindowSize], centered and never maximized — regardless of
/// whatever regular geometry happens to be persisted. That persisted
/// geometry is the user's own regular-window setup and must survive
/// onboarding untouched (see [shouldPersistWindowGeometry]); the onboarding
/// window intentionally never reads or reflects it. This also covers the
/// "restart mid-onboarding" path (the macOS App Store Auto-Paste grant
/// flow): a fresh process re-evaluates this function from disk and still
/// gets the fixed onboarding size, never a stale in-between value.
DesktopWindowGeometry resolveDesktopWindowGeometry(AppSettings settings) {
  if (!settings.onboarding.onboardingCompleted) {
    return const DesktopWindowGeometry(
      size: kOnboardingWindowSize,
      position: null,
      maximized: false,
    );
  }
  final position = settings.windowPosition;
  final hasPosition = position.windowX >= 0 && position.windowY >= 0;
  return DesktopWindowGeometry(
    size: Size(position.windowWidth, position.windowHeight),
    position: hasPosition ? Offset(position.windowX, position.windowY) : null,
    maximized: position.windowMaximized,
  );
}

/// Whether a resize/move event happening right now should be written to
/// [AppSettings]'s persisted window geometry.
///
/// `false` while onboarding is unfinished: the onboarding window can still
/// be resized by the user (or reflow with a system text-size change), and
/// none of that may overwrite the regular geometry the user set up before
/// onboarding started — not even through the generic "every resize gets
/// saved" listener that drives the regular window's persistence.
bool shouldPersistWindowGeometry(AppSettings settings) =>
    settings.onboarding.onboardingCompleted;
