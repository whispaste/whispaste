/// Severity and action of a message, plus the hold that keeps messages off
/// the main window while onboarding covers it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/accessibility/announce.dart';

/// Message severity; picks tone and icon on the overlay card and the banner.
enum WpMessageType { success, error, info, warning }

/// Bundled label + callback (and testID) for the one action of a message.
class WpMessageAction {
  const WpMessageAction({
    required this.label,
    required this.onPressed,
    this.testId,
  });

  final String label;
  final VoidCallback onPressed;

  /// Stable id for the action button; callers fall back to their own default.
  final String? testId;
}

/// A message kept off the main window during the onboarding hold, for the
/// onboarding frame to show on its own page.
class WpHeldMessage {
  const WpHeldMessage({
    required this.message,
    required this.type,
    this.actionLabel,
    this.onAction,
    this.actionTestId,
  });

  final String message;
  final WpMessageType type;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? actionTestId;
}

/// While onboarding is open the notice slots of the main window are not on
/// screen. Errors and warnings raised meanwhile are held here and shown by
/// the onboarding frame; everything else is dropped.
class WpOnboardingHold {
  WpOnboardingHold._();

  static int _holds = 0;

  /// Errors and warnings raised during a hold, oldest first; cleared when the
  /// last hold ends.
  static final ValueNotifier<List<WpHeldMessage>> held =
      ValueNotifier<List<WpHeldMessage>>(const []);

  static bool get holding => _holds > 0;

  static void hold() => _holds++;

  static void release() {
    if (_holds > 0) _holds--;
    if (_holds == 0) held.value = const [];
  }

  /// Keeps an error or warning for the onboarding frame and reads it out.
  /// [onDismissed] still reports back, so callers can clean up.
  static void add(
    BuildContext context, {
    required String message,
    required WpMessageType type,
    String? actionLabel,
    VoidCallback? onAction,
    String? actionTestId,
    VoidCallback? onDismissed,
  }) {
    final keep = type == WpMessageType.error || type == WpMessageType.warning;
    if (keep && !held.value.any((other) => other.message == message)) {
      held.value = [
        ...held.value,
        WpHeldMessage(
          message: message,
          type: type,
          actionLabel: actionLabel,
          onAction: onAction,
          actionTestId: actionTestId,
        ),
      ];
      announce(View.of(context), message, Directionality.of(context));
    }
    if (onDismissed != null) scheduleMicrotask(onDismissed);
  }

  static void dismiss(WpHeldMessage message) {
    held.value = [
      for (final other in held.value)
        if (!identical(other, message)) other,
    ];
  }
}
