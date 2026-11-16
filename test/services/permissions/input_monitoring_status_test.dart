import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_sections.dart'
    show HotkeySettings;
import 'package:whispaste/services/floating_button/floating_button_support.dart'
    show LinuxSessionType;
import 'package:whispaste/services/input_monitoring_offer.dart'
    show inputMonitoringMonitorProvider;
import 'package:whispaste/services/modifier_key_monitor.dart';
import 'package:whispaste/services/permissions/input_monitoring_status.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart'
    show PermissionOverviewStatus;

class _Monitor extends ModifierKeyMonitor {
  _Monitor() : super(isMacOS: true);

  bool? access;
  int reads = 0;

  @override
  Future<bool?> listenAccess() async {
    reads++;
    return access;
  }
}

// Input Monitoring is needed only for a single key as the trigger (#1198).
void main() {
  const combination = HotkeySettings();
  const combinationDoubleTap = HotkeySettings(hotkeyDoubleTap: true);
  const singleKey = HotkeySettings(hotkeyDoubleTapKey: 'rightOption');
  const disabledSingleKey = HotkeySettings(
    hotkeyEnabled: false,
    hotkeyDoubleTapKey: 'rightOption',
  );

  group('inputMonitoringNeeded', () {
    test('follows the trigger alone', () {
      expect(inputMonitoringNeeded(combination), isFalse);
      expect(inputMonitoringNeeded(combinationDoubleTap), isFalse);
      expect(inputMonitoringNeeded(singleKey), isTrue);
      expect(inputMonitoringNeeded(disabledSingleKey), isFalse);
    });
  });

  group('inputMonitoringStatusFor', () {
    PermissionOverviewStatus status(
      TargetPlatform platform,
      HotkeySettings hotkey, {
      bool? access,
      LinuxSessionType session = LinuxSessionType.unknown,
    }) => inputMonitoringStatusFor(
      platform: platform,
      hotkey: hotkey,
      listenAccess: access,
      linuxSession: session,
    );

    test('a key combination never needs it, whatever the grant', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          status(platform, combination, access: false),
          PermissionOverviewStatus.notNeeded,
        );
      }
    });

    test('switching the trigger flips the status', () {
      expect(
        status(TargetPlatform.macOS, combination, access: false),
        PermissionOverviewStatus.notNeeded,
      );
      expect(
        status(TargetPlatform.macOS, singleKey, access: false),
        PermissionOverviewStatus.missing,
      );
      expect(
        status(TargetPlatform.macOS, disabledSingleKey, access: false),
        PermissionOverviewStatus.notNeeded,
      );
    });

    test('macOS reads the grant', () {
      expect(
        status(TargetPlatform.macOS, singleKey, access: true),
        PermissionOverviewStatus.granted,
      );
      expect(
        status(TargetPlatform.macOS, singleKey, access: false),
        PermissionOverviewStatus.missing,
      );
      expect(
        status(TargetPlatform.macOS, singleKey),
        PermissionOverviewStatus.pending,
      );
    });

    test('Windows has no such permission', () {
      expect(
        status(TargetPlatform.windows, singleKey, access: false),
        PermissionOverviewStatus.notNeeded,
      );
    });

    test('Linux needs an X11 session', () {
      expect(
        status(TargetPlatform.linux, singleKey, session: LinuxSessionType.x11),
        PermissionOverviewStatus.granted,
      );
      expect(
        status(
          TargetPlatform.linux,
          singleKey,
          session: LinuxSessionType.wayland,
        ),
        PermissionOverviewStatus.missing,
      );
      expect(
        status(TargetPlatform.linux, singleKey),
        PermissionOverviewStatus.granted,
      );
    });
  });

  // A revoke found at runtime, and the wait for the grant to come back (#1200).
  group('InputMonitoringAccessNotifier', () {
    late _Monitor monitor;
    late ProviderContainer container;

    setUp(() {
      monitor = _Monitor()..access = true;
      container = ProviderContainer(
        overrides: [inputMonitoringMonitorProvider.overrideWithValue(monitor)],
      );
      addTearDown(container.dispose);
    });

    test('markRevoked shows the grant missing at once', () async {
      final access = container.read(inputMonitoringAccessProvider.notifier);
      await access.check();
      expect(container.read(inputMonitoringAccessProvider), isTrue);
      access.markRevoked();
      expect(container.read(inputMonitoringAccessProvider), isFalse);
    });

    test('watchUntilGranted reads until the grant is back, then stops', () {
      fakeAsync((async) {
        monitor.access = false;
        final access = container.read(inputMonitoringAccessProvider.notifier)
          ..markRevoked()
          ..watchUntilGranted();
        async.elapse(const Duration(seconds: 3));
        expect(container.read(inputMonitoringAccessProvider), isFalse);
        monitor.access = true;
        async.elapse(InputMonitoringAccessNotifier.pollInterval);
        expect(container.read(inputMonitoringAccessProvider), isTrue);
        final readsAtGrant = monitor.reads;
        async.elapse(const Duration(seconds: 10));
        expect(monitor.reads, readsAtGrant);
        expect(access, isNotNull);
      });
    });

    test('watchUntilGranted gives up after its timeout', () {
      fakeAsync((async) {
        monitor.access = false;
        container
            .read(inputMonitoringAccessProvider.notifier)
            .watchUntilGranted(timeout: const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));
        final readsAtTimeout = monitor.reads;
        async.elapse(const Duration(seconds: 10));
        expect(monitor.reads, readsAtTimeout);
      });
    });
  });
}
