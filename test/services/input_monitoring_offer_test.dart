/// Logic of the one-time Input Monitoring offer for a key combination (#807).
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/input_monitoring_offer.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.whispaste.modifier_monitor.offer_test');

  /// Container with a host that answers `status` with [listenAccess] and
  /// counts permission prompts in [prompts].
  Future<ProviderContainer> start({
    bool? listenAccess = false,
    bool offered = false,
    List<String>? prompts,
  }) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'status') {
            return listenAccess == null
                ? null
                : <String, Object?>{'listenAccess': listenAccess};
          }
          if (call.method == 'requestListenAccess') {
            prompts?.add(call.method);
            return false;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings(
              onboarding: OnboardingSettings(inputMonitoringOffered: offered),
            ),
          ),
        ),
        inputMonitoringMonitorProvider.overrideWithValue(
          ModifierKeyMonitor(isMacOS: true, channel: channel),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(settingsProvider.future);
    container.read(inputMonitoringOfferProvider);
    return container;
  }

  InputMonitoringOfferNotifier offer(ProviderContainer c) =>
      c.read(inputMonitoringOfferProvider.notifier);

  test(
    'a lost release in hold mode without the permission offers it',
    () async {
      final c = await start();
      await offer(c).releaseLost(holdModeOn: true);
      expect(c.read(inputMonitoringOfferProvider), isTrue);
    },
  );

  test('a declined or ignored offer is not repeated', () async {
    final prompts = <String>[];
    final c = await start(prompts: prompts);
    await offer(c).releaseLost(holdModeOn: true);
    // Shown and closed without the button: no system prompt, recorded.
    await offer(c).consume();
    expect(prompts, isEmpty);
    expect(
      c.read(settingsProvider).value!.onboarding.inputMonitoringOffered,
      isTrue,
    );

    await offer(c).releaseLost(holdModeOn: true);
    expect(c.read(inputMonitoringOfferProvider), isFalse);
  });

  test('an offer made in an earlier session is not repeated', () async {
    final c = await start(offered: true);
    await offer(c).releaseLost(holdModeOn: true);
    expect(c.read(inputMonitoringOfferProvider), isFalse);
  });

  test('only the button shows the system prompt', () async {
    final prompts = <String>[];
    final c = await start(prompts: prompts);
    await offer(c).releaseLost(holdModeOn: true);
    expect(prompts, isEmpty);
    await offer(c).accept();
    expect(prompts, ['requestListenAccess']);
  });

  test(
    'no offer when the permission is granted or the host cannot tell',
    () async {
      for (final access in [true, null]) {
        final c = await start(listenAccess: access);
        await offer(c).releaseLost(holdModeOn: true);
        expect(
          c.read(inputMonitoringOfferProvider),
          isFalse,
          reason: '$access',
        );
      }
    },
  );

  test('no offer outside hold mode, and that uses nothing up', () async {
    final c = await start();
    await offer(c).releaseLost(holdModeOn: false);
    expect(c.read(inputMonitoringOfferProvider), isFalse);
    await offer(c).releaseLost(holdModeOn: true);
    expect(c.read(inputMonitoringOfferProvider), isTrue);
  });

  test('a postponed offer (onboarding on screen) comes again', () async {
    final c = await start();
    await offer(c).releaseLost(holdModeOn: true);
    offer(c).postpone();
    expect(
      c.read(settingsProvider).value!.onboarding.inputMonitoringOffered,
      isFalse,
    );
    await offer(c).releaseLost(holdModeOn: true);
    expect(c.read(inputMonitoringOfferProvider), isTrue);
  });
}
