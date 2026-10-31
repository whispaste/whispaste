/// Native notifications only go out while a notification server owns the
/// name on the session bus (XP-7-19). Without one, libnotify would start the
/// server synchronously on the GTK main thread and freeze the app for the
/// 25 s D-Bus timeout.
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/system_attention_service.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings.defaults;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('local_notifier');
  // The dock bounce runs on any macOS host (`Platform.isMacOS`), so it needs
  // its native answer here; the test is about the notification server only.
  const lifecycleChannel = MethodChannel('com.whispaste.app_lifecycle');
  final notifyCalls = <String>[];

  setUp(() {
    notifyCalls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'notify') notifyCalls.add(call.method);
      return true;
    });
    messenger.setMockMethodCallHandler(lifecycleChannel, (call) async {
      return call.method == 'requestUserAttention' ? 1 : null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(lifecycleChannel, null);
  });

  Future<SystemAttentionService> serviceWith({
    required Future<bool> Function() serverRunning,
    required DateTime Function() clock,
  }) async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(_FakeSettingsNotifier.new),
        systemAttentionServiceProvider.overrideWith(
          (ref) => SystemAttentionService(
            ref,
            isNotificationServerRunning: serverRunning,
            clock: clock,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    return container.read(systemAttentionServiceProvider);
  }

  Future<void> paste(SystemAttentionService service, AttentionKind kind) =>
      service.requestAttention(kind: kind, title: 'title', body: 'body');

  test('skips the native notification without a notification server', () async {
    final service = await serviceWith(
      serverRunning: () async => false,
      clock: DateTime.now,
    );

    await paste(service, AttentionKind.pasteFailedUnknown);

    expect(notifyCalls, isEmpty);
  });

  test('shows it while a notification server runs', () async {
    final service = await serviceWith(
      serverRunning: () async => true,
      clock: DateTime.now,
    );

    await paste(service, AttentionKind.pasteFailedUnknown);

    expect(notifyCalls, ['notify']);
  });

  test('reuses one answer for 30 s, then asks again', () async {
    var now = DateTime(2026, 10, 19, 20);
    var checks = 0;
    var running = false;
    final service = await serviceWith(
      serverRunning: () async {
        checks++;
        return running;
      },
      clock: () => now,
    );

    // Distinct kinds, so the per-kind throttle does not hide a call.
    await paste(service, AttentionKind.pasteFailedUnknown);
    running = true;
    now = now.add(const Duration(seconds: 10));
    await paste(service, AttentionKind.pasteBlockedNoTarget);
    expect(checks, 1);
    expect(notifyCalls, isEmpty);

    // A server started later (mako, dunst) is picked up after the TTL.
    now = now.add(const Duration(seconds: 25));
    await paste(service, AttentionKind.silentMicrophone);
    expect(checks, 2);
    expect(notifyCalls, ['notify']);
  });
}
