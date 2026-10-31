/// Shared "bring the main window to the front" sequence.
///
/// Extracted from `TrayService._showWindow` so the quick-note path (Ticket 21)
/// uses the *same* sequence instead of rebuilding it: on macOS the Dock
/// presence has to be restored first (`MacOSLifecycleChannel.setRegular`),
/// because an app running in tray/accessory mode is not brought forward by
/// `windowManager.show()` alone — a second, `setRegular`-less copy of this
/// would be a silent no-op exactly in the tray case it exists for.
///
/// Deliberately a Riverpod seam rather than an instance field: both callers
/// (`TrayService`, a `Notifier`, and `WpRecordingBehavior`, a
/// `ConsumerStatefulWidget`) hold a `ref`, and tests replace the whole
/// activation with `windowActivatorProvider.overrideWithValue(...)` instead
/// of mocking `windowManager`'s platform channel.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/logging/app_logger.dart';
import '../core/platform/macos_lifecycle_channel.dart';

final _log = AppLogger('WindowActivation');

/// Restores Dock presence (macOS), shows and focuses the main window.
///
/// Never repositions or resizes: an already-visible window is only focused.
/// Channel errors are logged, not thrown — a failed activation must not take
/// down the caller's flow (tray click, finished quick-note append).
Future<void> activateWindow() async {
  try {
    // On macOS, restore Dock presence before showing the window.
    await MacOSLifecycleChannel.setRegular();
    await windowManager.show();
    await windowManager.focus();
  } on Exception catch (e) {
    _log.warning('Failed to activate window: $e');
  }
}

/// Injection point for [activateWindow]; overridden in tests with a spy.
final windowActivatorProvider = Provider<Future<void> Function()>(
  (ref) => activateWindow,
);
