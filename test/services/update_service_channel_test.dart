/// End-to-end coverage for `UpdateNotifier.checkForUpdate()`'s channel
/// routing (PRD Bug 4) — this was previously untested (see the update-
/// mechanism audit) and, before the fix, always hit `/releases/latest`
/// regardless of the persisted [UpdateChannel], which structurally excludes
/// GitHub prereleases.
///
/// Drives the *real* channel-aware branch end-to-end: a beta-channel check
/// must hit the list endpoint (which includes prereleases) instead of the
/// stable-only `/releases/latest`, and the pre-release-aware SemVer compare
/// (PRD Bug 3, `core/semver.dart`) must correctly resolve `available` vs.
/// `upToDate` against the newest entry.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:whispaste/core/app_info.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_channel_service.dart';
import 'package:whispaste/services/update_service.dart';

/// Responds differently to the single-object `/releases/latest` endpoint
/// (stable) vs. the newest-first `/releases` list endpoint (beta) — mirrors
/// what the real GitHub API returns for each.
class _ReleasesAdapter implements HttpClientAdapter {
  static const _assets = [
    {
      'name': 'WhisPaste-Setup.exe',
      'browser_download_url': 'https://example.invalid/setup.exe',
    },
    {
      'name': 'WhisPaste-macos-arm64.dmg',
      'browser_download_url': 'https://example.invalid/mac.dmg',
    },
    {
      'name': 'WhisPaste-linux-x64.tar.gz',
      'browser_download_url': 'https://example.invalid/linux.tar.gz',
    },
  ];

  static String get _jsonAssets {
    final entries = _assets.map(
      (a) =>
          '{"name":"${a['name']}","browser_download_url":"${a['browser_download_url']}"}',
    );
    return '[${entries.join(',')}]';
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final isLatest = options.path.endsWith('/releases/latest');
    final body = isLatest
        ? '{"tag_name":"v1.2.43","assets":$_jsonAssets,"html_url":"https://example.invalid/v1.2.43"}'
        : '[{"tag_name":"v1.2.44-beta.6","assets":$_jsonAssets,"html_url":"https://example.invalid/beta.6"},'
              '{"tag_name":"v1.2.43","assets":$_jsonAssets,"html_url":"https://example.invalid/v1.2.43"}]';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> makeContainer(UpdateChannel channel) async {
    UpdateNotifier.dioOverrideForTesting = Dio()
      ..httpClientAdapter = _ReleasesAdapter();
    deployChannelOverride = DeployChannel.installer;

    final container = ProviderContainer();
    await container.read(updateChannelProvider.notifier).setChannel(channel);
    return container;
  }

  tearDown(() {
    UpdateNotifier.dioOverrideForTesting = null;
    deployChannelOverride = null;
  });

  group('stable channel', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'WhisPaste',
        packageName: 'de.whispaste.app',
        version: '1.2.42',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    test(
      'hits /releases/latest and detects the stable release as newer',
      () async {
        await initAppInfo();
        final container = await makeContainer(UpdateChannel.stable);
        addTearDown(container.dispose);

        await container.read(updateProvider.notifier).checkForUpdate();

        final state = container.read(updateProvider);
        expect(state.phase, UpdatePhase.available);
        expect(state.latestVersion, '1.2.43');
      },
    );
  });

  group('beta channel — PRD Bug 3+4 regression', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'WhisPaste',
        packageName: 'de.whispaste.app',
        version: '1.2.44-beta.5',
        buildNumber: '6',
        buildSignature: '',
      );
    });

    test('hits the /releases list (not /releases/latest) and finds the newer '
        'beta — before the fix this always queried /releases/latest, which '
        'structurally excludes prereleases', () async {
      await initAppInfo();
      final container = await makeContainer(UpdateChannel.beta);
      addTearDown(container.dispose);

      await container.read(updateProvider.notifier).checkForUpdate();

      final state = container.read(updateProvider);
      expect(
        state.phase,
        UpdatePhase.available,
        reason:
            'installed=1.2.44-beta.5, newest=1.2.44-beta.6 — before the '
            'SemVer fix, parseSemver stripped the pre-release suffix and '
            'both compared equal, so this stayed upToDate forever.',
      );
      expect(state.latestVersion, '1.2.44-beta.6');
    });

    test(
      'already on the newest beta → upToDate, not a false positive',
      () async {
        PackageInfo.setMockInitialValues(
          appName: 'WhisPaste',
          packageName: 'de.whispaste.app',
          version: '1.2.44-beta.6',
          buildNumber: '7',
          buildSignature: '',
        );
        await initAppInfo();
        final container = await makeContainer(UpdateChannel.beta);
        addTearDown(container.dispose);

        await container.read(updateProvider.notifier).checkForUpdate();

        expect(container.read(updateProvider).phase, UpdatePhase.upToDate);
      },
    );
  });
}
