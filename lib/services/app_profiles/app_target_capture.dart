/// "App erfassen" in the profile editor: the app that is in front after the
/// user switched to it is read through the paste host, the same capture the
/// recording uses (`captureTarget`, then `getTargetBundleId`). Nothing new is
/// built natively for it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../desktop_paste/desktop_paste_controller.dart';

/// Result of one capture attempt.
sealed class AppCaptureOutcome {
  const AppCaptureOutcome();
}

/// The app in front was read; [identifier] is its platform key (bundle id,
/// exe name or WM_CLASS), the same key the app rules match.
final class AppCaptured extends AppCaptureOutcome {
  const AppCaptured(this.identifier);

  final String identifier;
}

/// No other app was in front, typically because WhisPaste itself still was.
final class AppCaptureNoForeignApp extends AppCaptureOutcome {
  const AppCaptureNoForeignApp();
}

/// The platform cannot tell the app in front (no paste host, or Wayland).
final class AppCaptureUnavailable extends AppCaptureOutcome {
  const AppCaptureUnavailable();
}

/// Reads the app in front through [controller]. Null controller (no paste
/// host on this build) is unavailable.
Future<AppCaptureOutcome> captureForegroundApp(
  DesktopPasteController? controller,
) async {
  if (controller == null) return const AppCaptureUnavailable();
  final captured = await controller.capturePasteTarget();
  final id = (await controller.getTargetBundleId())?.trim();
  if (id == null || id.isEmpty) {
    return captured
        ? const AppCaptureUnavailable()
        : const AppCaptureNoForeignApp();
  }
  if (!captured) return const AppCaptureNoForeignApp();
  return AppCaptured(id);
}

/// The capture the profile editor runs. Tests override it with a closure.
final appCaptureProvider = Provider<Future<AppCaptureOutcome> Function()>((
  ref,
) {
  final controller = ref.watch(desktopPasteControllerProvider);
  return () => captureForegroundApp(controller);
});
