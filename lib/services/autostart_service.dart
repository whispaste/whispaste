import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../core/config/settings_provider.dart';
import '../core/logging/app_logger.dart';

/// Manages the "launch at startup" registration using the system registry
/// (Windows), login items (macOS), or autostart entries (Linux).
class AutostartService extends Notifier<bool> {
  static bool _setupDone = false;
  static final _log = AppLogger('AutostartService');

  @override
  bool build() {
    _ensureSetup();
    _syncWithSettings();
    return false;
  }

  /// One-time setup of the launch_at_startup plugin.
  void _ensureSetup() {
    if (_setupDone) return;
    _setupDone = true;

    launchAtStartup.setup(
      appName: 'WhisPaste',
      appPath: Platform.resolvedExecutable,
      // MSIX Store packages use a different startup mechanism.
      packageName: 'com.whispaste.app',
      args: ['--autostart'],
    );
  }

  /// Sync the autostart state with the persisted setting.
  Future<void> _syncWithSettings() async {
    final settings = ref.read(settingsProvider).value;
    if (settings == null) return;

    try {
      final isEnabled = await launchAtStartup.isEnabled();
      if (settings.launchAtStartup && !isEnabled) {
        await launchAtStartup.enable();
        _log.info('Autostart enabled');
      } else if (!settings.launchAtStartup && isEnabled) {
        await launchAtStartup.disable();
        _log.info('Autostart disabled');
      }
      state = settings.launchAtStartup;
    } catch (e) {
      _log.warning('Autostart sync failed: $e');
    }
  }
}

final autostartServiceProvider = NotifierProvider<AutostartService, bool>(
  AutostartService.new,
);
