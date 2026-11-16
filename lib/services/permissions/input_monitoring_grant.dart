/// The one "Grant access" action for Input Monitoring on macOS (#1200).
///
/// The permissions overview and the "single key lost its permission" notice
/// run the same steps, so both buttons behave alike: first the system prompt;
/// when that leaves the grant missing (macOS asks only once), System Settings
/// opens at Input Monitoring with the "drag the app into the list" panel the
/// onboarding docks beside it. Afterwards the grant is read until it is back,
/// and the hotkey takes the single key over again.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n/generated/app_localizations.dart';
import '../../core/logging/app_logger.dart';
import '../paste/paste_capability_notifier.dart';
import '../permission_helper_service.dart';
import 'input_monitoring_status.dart';
import 'settings_window_placement.dart';

const _inputMonitoringPane =
    'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent';

final _log = AppLogger('InputMonitoringGrant');

/// What [grantInputMonitoring] ended with.
enum InputMonitoringGrantStep {
  /// The grant is there (prompt accepted, or it was on already).
  granted,

  /// The drag-into-the-list panel docks beside System Settings; the caller
  /// hides it when its surface goes away.
  helperShown,

  /// System Settings opened at Input Monitoring without the panel.
  settingsOpened,

  /// Not macOS: there is no grant to give.
  unsupported,
}

/// Runs the grant steps. [read] is a `ref.read` of the caller.
Future<InputMonitoringGrantStep> grantInputMonitoring({
  required T Function<T>(ProviderListenable<T> provider) read,
  required L10n l10n,
}) async {
  if (defaultTargetPlatform != TargetPlatform.macOS) {
    return InputMonitoringGrantStep.unsupported;
  }
  final access = read(inputMonitoringAccessProvider.notifier);
  await access.request();
  if (read(inputMonitoringAccessProvider) == true) {
    return InputMonitoringGrantStep.granted;
  }
  // Read on until the grant is back, also once the asking surface is gone.
  access.watchUntilGranted();
  final cached = read(
    pasteCapabilityNotifierProvider.notifier,
  ).cachedProbeBuild;
  final shown = await read(permissionHelperProvider).show(
    PermissionHelperKind.inputMonitoring,
    // The store build is listed already; it only needs switching on.
    text: cached
        ? l10n.onboardingAccessibilitySwitchHint('WhisPaste')
        : l10n.onboardingAccessibilityDragHint('WhisPaste'),
    note: '',
    closeLabel: l10n.actionClose,
  );
  switch (shown) {
    case PermissionHelperShowResult.shown:
      return InputMonitoringGrantStep.helperShown;
    case PermissionHelperShowResult.granted:
      unawaited(access.check());
      return InputMonitoringGrantStep.granted;
    case PermissionHelperShowResult.unsupported ||
        PermissionHelperShowResult.failed:
      try {
        await launchUrl(Uri.parse(_inputMonitoringPane));
      } on Exception catch (e) {
        _log.warning('Could not open Input Monitoring settings', e);
      }
      unawaited(placeBesideSystemSettings());
      return InputMonitoringGrantStep.settingsOpened;
  }
}
