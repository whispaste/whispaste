import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/telemetry_service.dart';
import 'package:whispaste/services/update_service.dart';

/// Unconfigured (endpointUrl empty → `_isConfigured` false) — every call is
/// a safe no-op with no network client actually invoked. Overriding
/// [telemetryProvider] with this keeps tests that don't care about
/// telemetry from incidentally building the full production provider chain
/// (settings → history database) just because a native mirror now calls
/// `_trackCheckOutcome`.
final _unconfiguredTelemetry = TelemetryService(
  client: http.Client(),
  endpointUrl: '',
  siteId: 0,
  consentGranted: false,
  dntActive: false,
);

void main() {
  group('UpdateNotifier.parseSemver', () {
    test('parses standard X.Y.Z', () {
      expect(UpdateNotifier.parseSemver('1.2.3'), [1, 2, 3]);
    });

    test('strips leading v', () {
      expect(UpdateNotifier.parseSemver('v1.2.3'), [1, 2, 3]);
    });

    test('strips pre-release suffix', () {
      expect(UpdateNotifier.parseSemver('1.2.3-beta.1'), [1, 2, 3]);
    });

    test('strips build metadata', () {
      expect(UpdateNotifier.parseSemver('1.2.3+4'), [1, 2, 3]);
    });

    test('strips pre-release AND build metadata', () {
      expect(UpdateNotifier.parseSemver('v1.2.3-beta.1+42'), [1, 2, 3]);
    });

    test('returns null for too few segments', () {
      expect(UpdateNotifier.parseSemver('1.2'), isNull);
    });

    test('returns null for non-numeric', () {
      expect(UpdateNotifier.parseSemver('abc.def.ghi'), isNull);
    });

    test('returns null for empty string', () {
      expect(UpdateNotifier.parseSemver(''), isNull);
    });
  });

  group('UpdateNotifier.isNewer', () {
    test('higher major is newer', () {
      expect(UpdateNotifier.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('higher minor is newer', () {
      expect(UpdateNotifier.isNewer('1.3.0', '1.2.9'), isTrue);
    });

    test('higher patch is newer', () {
      expect(UpdateNotifier.isNewer('1.2.4', '1.2.3'), isTrue);
    });

    test('equal versions are not newer', () {
      expect(UpdateNotifier.isNewer('1.2.3', '1.2.3'), isFalse);
    });

    test('lower version is not newer', () {
      expect(UpdateNotifier.isNewer('1.2.2', '1.2.3'), isFalse);
    });

    test('handles v prefix on candidate', () {
      expect(UpdateNotifier.isNewer('v1.3.0', '1.2.0'), isTrue);
    });

    test('handles v prefix on both', () {
      expect(UpdateNotifier.isNewer('v2.0.0', 'v1.0.0'), isTrue);
    });

    test('handles build metadata', () {
      expect(UpdateNotifier.isNewer('1.3.0+5', '1.2.0+3'), isTrue);
    });

    test('same version with different build metadata is NOT newer', () {
      expect(UpdateNotifier.isNewer('1.2.0+5', '1.2.0+3'), isFalse);
    });

    test('returns false for invalid candidate', () {
      expect(UpdateNotifier.isNewer('bad', '1.2.3'), isFalse);
    });

    test('returns false for invalid current', () {
      expect(UpdateNotifier.isNewer('1.2.3', 'bad'), isFalse);
    });
  });

  group('UpdateState', () {
    test('default state is idle', () {
      const state = UpdateState();
      expect(state.phase, UpdatePhase.idle);
      expect(state.latestVersion, isNull);
      expect(state.downloadUrl, isNull);
      expect(state.releaseNotesUrl, isNull);
      expect(state.downloadedPath, isNull);
      expect(state.progressPercent, 0);
      expect(state.errorMessage, isNull);
    });

    test('isBusy is true for checking', () {
      const state = UpdateState(phase: UpdatePhase.checking);
      expect(state.isBusy, isTrue);
    });

    test('isBusy is true for downloading', () {
      const state = UpdateState(phase: UpdatePhase.downloading);
      expect(state.isBusy, isTrue);
    });

    test('isBusy is false for idle', () {
      const state = UpdateState(phase: UpdatePhase.idle);
      expect(state.isBusy, isFalse);
    });

    test('isBusy is false for available', () {
      const state = UpdateState(phase: UpdatePhase.available);
      expect(state.isBusy, isFalse);
    });

    test('isBusy is false for error', () {
      const state = UpdateState(phase: UpdatePhase.error);
      expect(state.isBusy, isFalse);
    });

    test('copyWith preserves fields', () {
      const original = UpdateState(
        phase: UpdatePhase.available,
        latestVersion: '2.0.0',
        downloadUrl: 'https://example.com/setup.exe',
        releaseNotesUrl:
            'https://github.com/whispaste/whispaste/releases/tag/v2.0.0',
      );
      final updated = original.copyWith(phase: UpdatePhase.downloading);
      expect(updated.phase, UpdatePhase.downloading);
      expect(updated.latestVersion, '2.0.0');
      expect(updated.downloadUrl, 'https://example.com/setup.exe');
    });
  });

  group('UpdateNotifier native-event mirrors (PRD Bug: Sparkle abort '
      'conflates "no update" with "error")', () {
    test('markErrorNative after markUpToDateNative is ignored — Sparkle '
        'fires a trailing didAbortWithError even for a completely normal '
        '"no update found" cycle', () {
      final container = ProviderContainer(
        overrides: [
          telemetryProvider.overrideWithValue(_unconfiguredTelemetry),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateProvider.notifier);

      notifier.markUpToDateNative(latestVersion: '1.2.44-beta.7');
      notifier.markErrorNative('SUNoUpdateError (benign)');

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.upToDate);
      expect(state.latestVersion, '1.2.44-beta.7');
    });

    test('markErrorNative after markAvailableNative is ignored — a real find '
        'must survive a trailing abort signal', () {
      final container = ProviderContainer(
        overrides: [
          telemetryProvider.overrideWithValue(_unconfiguredTelemetry),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateProvider.notifier);

      notifier.markAvailableNative(version: '1.2.44-beta.8');
      notifier.markErrorNative('trailing abort');

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.available);
      expect(state.latestVersion, '1.2.44-beta.8');
    });

    test('markErrorNative with no prior decisive event still surfaces a '
        'genuine failure (e.g. network unreachable before any appcast '
        'could be parsed)', () {
      final container = ProviderContainer(
        overrides: [
          telemetryProvider.overrideWithValue(_unconfiguredTelemetry),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateProvider.notifier);

      notifier.markCheckingNative();
      notifier.markErrorNative('offline');

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.error);
      expect(state.errorMessage, 'offline');
    });

    test('markReadyToInstallNative transitions to readyToInstall and keeps '
        'the previously-known version', () {
      final container = ProviderContainer(
        overrides: [
          telemetryProvider.overrideWithValue(_unconfiguredTelemetry),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(updateProvider.notifier);

      notifier.markAvailableNative(version: '1.2.44-beta.9');
      notifier.markReadyToInstallNative();

      final state = container.read(updateProvider);
      expect(state.phase, UpdatePhase.readyToInstall);
      expect(state.latestVersion, '1.2.44-beta.9');
    });
  });

  group('UpdateNotifier update-check telemetry (sparse, categorical — no '
      'version strings, no error text)', () {
    ProviderContainer makeContainer(List<String> bodies) {
      final client = MockClient((req) async {
        bodies.add(req.body);
        return http.Response('', 200);
      });
      final telemetry = TelemetryService(
        client: client,
        endpointUrl: 'https://example.matomo.cloud',
        siteId: 1,
        consentGranted: true,
        dntActive: false,
      );
      final container = ProviderContainer(
        overrides: [telemetryProvider.overrideWithValue(telemetry)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('markAvailableNative sends update/check/available', () async {
      final bodies = <String>[];
      final container = makeContainer(bodies);
      container
          .read(updateProvider.notifier)
          .markAvailableNative(version: '1.2.44-beta.9');
      await container.read(telemetryProvider).flush();

      expect(bodies, hasLength(1));
      final params = Uri.splitQueryString(bodies.single);
      expect(params['e_c'], 'update');
      expect(params['e_a'], 'check');
      expect(params['e_n'], 'available');
    });

    test('markUpToDateNative sends update/check/up_to_date', () async {
      final bodies = <String>[];
      final container = makeContainer(bodies);
      container.read(updateProvider.notifier).markUpToDateNative();
      await container.read(telemetryProvider).flush();

      expect(bodies, hasLength(1));
      expect(Uri.splitQueryString(bodies.single)['e_n'], 'up_to_date');
    });

    test(
      'markReadyToInstallNative sends update/check/ready_to_install',
      () async {
        final bodies = <String>[];
        final container = makeContainer(bodies);
        container.read(updateProvider.notifier).markReadyToInstallNative();
        await container.read(telemetryProvider).flush();

        expect(bodies, hasLength(1));
        expect(Uri.splitQueryString(bodies.single)['e_n'], 'ready_to_install');
      },
    );

    test('a genuine markErrorNative (no prior decisive event) sends '
        'update/check/error', () async {
      final bodies = <String>[];
      final container = makeContainer(bodies);
      final notifier = container.read(updateProvider.notifier);
      notifier.markCheckingNative();
      notifier.markErrorNative('offline');
      await container.read(telemetryProvider).flush();

      expect(bodies, hasLength(1));
      expect(Uri.splitQueryString(bodies.single)['e_n'], 'error');
    });

    test('a GUARDED markErrorNative (trailing abort after a decisive result) '
        'sends nothing — it never touched state', () async {
      final bodies = <String>[];
      final container = makeContainer(bodies);
      final notifier = container.read(updateProvider.notifier);
      notifier.markUpToDateNative();
      notifier.markErrorNative('benign trailing abort');
      await container.read(telemetryProvider).flush();

      // Exactly one event: the up_to_date from markUpToDateNative. The
      // guarded error must not add a second.
      expect(bodies, hasLength(1));
      expect(Uri.splitQueryString(bodies.single)['e_n'], 'up_to_date');
    });

    test('markCheckingNative sends nothing — not a terminal outcome', () async {
      final bodies = <String>[];
      final container = makeContainer(bodies);
      container.read(updateProvider.notifier).markCheckingNative();
      await container.read(telemetryProvider).flush();

      expect(bodies, isEmpty);
    });
  });

  group('DeployChannel', () {
    test('deploy channel override works for testing', () {
      deployChannelOverride = DeployChannel.installer;
      expect(detectDeployChannel(), DeployChannel.installer);

      deployChannelOverride = DeployChannel.store;
      expect(detectDeployChannel(), DeployChannel.store);

      deployChannelOverride = DeployChannel.portable;
      expect(detectDeployChannel(), DeployChannel.portable);

      deployChannelOverride = null; // reset
    });
  });
}
