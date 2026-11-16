/// Where the Input Monitoring permission stands, for the permissions overview
/// in Settings (#1198).
///
/// Only a single key as the trigger (held, or tapped twice) reads the keyboard
/// outside the app, so only that trigger needs the permission. A key
/// combination, also tapped twice, goes through the system's hotkey registrar
/// and needs none. Per platform:
///
/// * macOS: the system's Input Monitoring grant, read live.
/// * Windows: no permission exists, always "not needed".
/// * Linux: no permission, but the single key needs an X11 session; under
///   Wayland it does not work, so the row reads "missing" and names X11.
///
/// Settings shows the row only where a grant exists (macOS, see
/// `inputMonitoringPermissionApplies`); the Wayland limit is named in the key
/// picker. Separate from `permissionsOverviewProvider`, which the onboarding
/// renders unchanged.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart' show HotkeySettings;
import '../floating_button/floating_button_support.dart'
    show LinuxSessionType, linuxSessionTypeFrom;
import '../input_monitoring_offer.dart' show inputMonitoringMonitorProvider;
import 'permissions_overview_provider.dart' show PermissionOverviewStatus;

/// Whether the chosen trigger reads a single key: only then is the permission
/// needed. The double tap is a gesture of that single key.
bool inputMonitoringNeeded(HotkeySettings hotkey) =>
    hotkey.hotkeyEnabled && hotkey.hotkeyDoubleTapKey.isNotEmpty;

/// The row status for [platform]. [listenAccess] is the macOS grant (`null`
/// while unknown), [linuxSession] the Linux session type.
PermissionOverviewStatus inputMonitoringStatusFor({
  required TargetPlatform platform,
  required HotkeySettings hotkey,
  bool? listenAccess,
  LinuxSessionType linuxSession = LinuxSessionType.unknown,
}) {
  if (!inputMonitoringNeeded(hotkey)) return PermissionOverviewStatus.notNeeded;
  return switch (platform) {
    TargetPlatform.macOS => switch (listenAccess) {
      true => PermissionOverviewStatus.granted,
      false => PermissionOverviewStatus.missing,
      null => PermissionOverviewStatus.pending,
    },
    // An unknown session gets the benefit of the doubt: most of them are X11
    // sessions without the variable set.
    TargetPlatform.linux =>
      linuxSession == LinuxSessionType.wayland
          ? PermissionOverviewStatus.missing
          : PermissionOverviewStatus.granted,
    _ => PermissionOverviewStatus.notNeeded,
  };
}

/// The macOS grant, read live. `null` until the first answer and off macOS.
/// [check] reads it once; [startPolling] keeps it current while a surface
/// shows it, so a grant in System Settings appears without a restart.
///
/// A revoke found at runtime (#1200) arrives through [markRevoked]; after the
/// user starts granting it again, [watchUntilGranted] reads the grant until
/// it is back, whether or not the overview is on screen.
class InputMonitoringAccessNotifier extends Notifier<bool?> {
  Timer? _timer;
  Timer? _watch;

  /// How often [startPolling] reads the grant. Cheap: one preflight call.
  static const pollInterval = Duration(seconds: 1);

  /// How long [watchUntilGranted] waits for the grant before it gives up.
  static const watchTimeout = Duration(minutes: 5);

  @override
  bool? build() {
    ref.onDispose(stopPolling);
    ref.onDispose(_stopWatch);
    return null;
  }

  /// The hotkey's health check found the grant withdrawn: the overview shows
  /// "missing" at once, without waiting for its own poll.
  void markRevoked() {
    if (ref.mounted && state != false) state = false;
  }

  /// Reads the grant every [pollInterval] until it is back or [timeout]
  /// passes. A second call starts the wait anew.
  void watchUntilGranted({Duration timeout = watchTimeout}) {
    _stopWatch();
    final maxTicks = timeout.inMilliseconds ~/ pollInterval.inMilliseconds;
    var ticks = 0;
    late final Timer watch;
    watch = Timer.periodic(pollInterval, (_) async {
      ticks++;
      await check();
      if (!identical(_watch, watch)) return;
      if (state == true || ticks >= maxTicks) _stopWatch();
    });
    _watch = watch;
  }

  void _stopWatch() {
    _watch?.cancel();
    _watch = null;
  }

  Future<void> check() async {
    final access = await ref
        .read(inputMonitoringMonitorProvider)
        .listenAccess();
    if (ref.mounted && access != state) state = access;
  }

  /// Shows the system prompt; on a later request macOS stays silent, and the
  /// caller opens System Settings instead.
  Future<void> request() async {
    await ref.read(inputMonitoringMonitorProvider).requestAccess();
    await check();
  }

  void startPolling() {
    if (_timer != null) return;
    unawaited(check());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(check()));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }
}

final inputMonitoringAccessProvider =
    NotifierProvider<InputMonitoringAccessNotifier, bool?>(
      InputMonitoringAccessNotifier.new,
    );

/// The Linux session type, read once. Overridden in tests.
final linuxSessionTypeProvider = Provider<LinuxSessionType>(
  (ref) => defaultTargetPlatform == TargetPlatform.linux
      ? linuxSessionTypeFrom(Platform.environment)
      : LinuxSessionType.unknown,
);

/// The Input Monitoring row status on this platform with the current trigger.
final inputMonitoringStatusProvider = Provider<PermissionOverviewStatus>((ref) {
  final hotkey =
      ref.watch(settingsProvider.select((s) => s.value?.hotkey)) ??
      AppSettings.defaults.hotkey;
  return inputMonitoringStatusFor(
    platform: defaultTargetPlatform,
    hotkey: hotkey,
    listenAccess: ref.watch(inputMonitoringAccessProvider),
    linuxSession: ref.watch(linuxSessionTypeProvider),
  );
});
