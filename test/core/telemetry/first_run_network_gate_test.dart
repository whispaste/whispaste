/// The first-run network hold (#686): before the privacy choice nothing
/// leaves the app on its own; after it, the start event, the alive ping and
/// the first update check follow. Fake transport and fake settings, no real
/// network, no waiting.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/telemetry/first_run_network_gate.dart';
import 'package:whispaste/services/telemetry_service.dart';

class _FakeSettings extends SettingsNotifier {
  _FakeSettings(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(state.value ?? _settings);
    state = AsyncData(_settings);
  }
}

AppSettings _withOnboarding({required bool completed}) =>
    AppSettings.defaults.copyWith(onboardingCompleted: completed);

void main() {
  group('FirstRunNetworkGate', () {
    test(
      'a held gate queues actions and runs them once, in order, on open',
      () {
        final gate = FirstRunNetworkGate(held: true);
        final ran = <String>[];
        gate.whenOpen(() => ran.add('start'));
        gate.whenOpen(() => ran.add('update'));
        expect(gate.isHeld, isTrue);
        expect(ran, isEmpty);

        gate.open();
        gate.open();

        expect(gate.isOpen, isTrue);
        expect(ran, ['start', 'update']);
      },
    );

    test('an open gate runs actions immediately', () {
      final gate = FirstRunNetworkGate(held: false);
      var ran = 0;
      gate.whenOpen(() => ran++);
      expect(ran, 1);
    });
  });

  group('TelemetryService behind the gate', () {
    late List<Map<String, String>> sent;
    late http.Client client;

    setUp(() {
      sent = [];
      client = MockClient((request) async {
        sent.add(request.bodyFields);
        return http.Response('', 204);
      });
      SharedPreferences.setMockInitialValues({});
    });

    TelemetryService service(FirstRunNetworkGate gate) => TelemetryService(
      client: client,
      endpointUrl: 'https://stats.example.invalid',
      siteId: 1,
      consentGranted: true,
      networkAllowed: () => gate.isOpen,
    );

    test('no event, setting change, alive ping or sendEventNow before the '
        'choice', () async {
      final gate = FirstRunNetworkGate(held: true);
      final telemetry = service(gate);
      final prefs = await SharedPreferences.getInstance();

      telemetry.trackEvent(category: 'lifecycle', action: 'start');
      telemetry.trackSettingChange('share_usage_stats');
      telemetry.trackPageView('/x');
      await telemetry.sendDailyAlivePingIfDue(prefs);
      final result = await telemetry.sendEventNow(category: 'c', action: 'a');
      await telemetry.flush();

      expect(sent, isEmpty);
      expect(result, TelemetrySendResult.notAllowed);
      expect(
        prefs.getString('telemetry_alive_ping_last_date'),
        isNull,
        reason: 'a held alive ping must not use up the day',
      );
    });

    test(
      'after the choice the start event and the alive ping go out',
      () async {
        final gate = FirstRunNetworkGate(held: true);
        final telemetry = service(gate);
        final prefs = await SharedPreferences.getInstance();
        gate.whenOpen(() {
          telemetry.trackEvent(category: 'lifecycle', action: 'start');
        });

        gate.open();
        await telemetry.sendDailyAlivePingIfDue(prefs);
        await telemetry.flush();

        expect(sent.map((b) => b['e_a'] ?? b['action_name']), [
          'start',
          'alive',
        ]);
      },
    );

    test('an existing install (gate open from the start) sends at once', () {
      final telemetry = service(FirstRunNetworkGate(held: false));
      telemetry.trackEvent(category: 'lifecycle', action: 'start');
      return telemetry.flush().then((_) => expect(sent, hasLength(1)));
    });

    test('the choice "off" still sends nothing after the gate opens', () async {
      final gate = FirstRunNetworkGate(held: true)..open();
      final telemetry = TelemetryService(
        client: client,
        endpointUrl: 'https://stats.example.invalid',
        siteId: 1,
        consentGranted: false,
        networkAllowed: () => gate.isOpen,
      );
      telemetry.trackEvent(category: 'lifecycle', action: 'start');
      await telemetry.flush();
      expect(sent, isEmpty);
    });
  });

  group('firstRunNetworkGateProvider', () {
    Future<ProviderContainer> containerFor({required bool completed}) async {
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettings(_withOnboarding(completed: completed)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);
      return container;
    }

    test('held while the onboarding is not completed', () async {
      final container = await containerFor(completed: false);
      expect(container.read(firstRunNetworkGateProvider).isHeld, isTrue);
    });

    test('open for an install that finished the onboarding', () async {
      final container = await containerFor(completed: true);
      expect(container.read(firstRunNetworkGateProvider).isOpen, isTrue);
    });

    test(
      'opens when the onboarding completes, even without the page',
      () async {
        final container = await containerFor(completed: false);
        final gate = container.read(firstRunNetworkGateProvider);
        var ran = 0;
        gate.whenOpen(() => ran++);

        await container
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(onboardingCompleted: true));

        expect(gate.isOpen, isTrue);
        expect(ran, 1);
      },
    );
  });
}
