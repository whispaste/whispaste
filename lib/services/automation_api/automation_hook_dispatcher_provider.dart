/// App-level wiring for the automation hook dispatcher (WP-38 / 8.3).
///
/// The hook list is read from settings at send time, so an edit in the
/// Integrationen editor applies to the next event without a restart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/logging/app_logger.dart';
import 'automation_hook_dispatcher.dart';

final _log = AppLogger('AutomationHooks');

final automationHookDispatcherProvider = Provider<AutomationHookDispatcher>((
  ref,
) {
  return AutomationHookDispatcher(
    hooks: () =>
        ref.read(settingsProvider).value?.automationApi.hooks ?? const [],
    onFailure: _log.warning,
  );
});
