import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stable_revert_hint_service.dart';

const _stableAppcastFixture = '''
<?xml version="1.0" standalone="yes"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WhisPaste</title>
    <item>
      <title>Version 1.2.43</title>
      <sparkle:version>1.2.43</sparkle:version>
      <sparkle:shortVersionString>1.2.43</sparkle:shortVersionString>
      <enclosure url="https://example.invalid/WhisPaste-macos-arm64.dmg" sparkle:edSignature="abc" length="1" type="application/octet-stream" sparkle:os="macos"/>
    </item>
  </channel>
</rss>
''';

void main() {
  tearDown(() {
    // Restore the production seam so later suites never touch a live
    // network via a leaked mock.
    fetchAppcastFn = (url) async => '';
  });

  group('parseAppcastVersion', () {
    test('extracts sparkle:shortVersionString', () {
      expect(parseAppcastVersion(_stableAppcastFixture), '1.2.43');
    });

    test('falls back to the enclosure sparkle:version attribute', () {
      const xmlWithoutShortVersion = '''
        <item>
          <enclosure sparkle:version="1.2.43" url="x"/>
        </item>
      ''';
      expect(parseAppcastVersion(xmlWithoutShortVersion), '1.2.43');
    });

    test('returns null for a feed with no version markers', () {
      expect(parseAppcastVersion('<rss></rss>'), isNull);
    });

    test('returns null for an empty response body', () {
      expect(parseAppcastVersion(''), isNull);
    });
  });

  group('isInstalledAheadOfStable', () {
    test('AC-7: installed beta patch ahead of stable-latest patch → true', () {
      expect(isInstalledAheadOfStable('1.2.44-beta.1', '1.2.43'), isTrue);
    });

    test('AC-3: after promotion, stable-latest matches the beta core → false '
        '(no false hint — auto-update takes over instead)', () {
      expect(isInstalledAheadOfStable('1.2.44-beta.1', '1.2.44'), isFalse);
    });

    test('stable-latest strictly newer than installed beta → false', () {
      expect(isInstalledAheadOfStable('1.2.44-beta.1', '1.2.45'), isFalse);
    });

    test('two plain releases, installed newer → true', () {
      expect(isInstalledAheadOfStable('1.2.44', '1.2.43'), isTrue);
    });

    test('two plain releases, equal → false', () {
      expect(isInstalledAheadOfStable('1.2.44', '1.2.44'), isFalse);
    });

    test('higher beta build number outranks a lower one on equal core', () {
      expect(
        isInstalledAheadOfStable('1.2.44-beta.2', '1.2.44-beta.1'),
        isTrue,
      );
    });

    test('unparseable installed version → false (never a false positive)', () {
      expect(isInstalledAheadOfStable('not-a-version', '1.2.43'), isFalse);
    });

    test('unparseable stable version → false (never a false positive)', () {
      expect(
        isInstalledAheadOfStable('1.2.44-beta.1', 'not-a-version'),
        isFalse,
      );
    });
  });

  group('StableRevertHintNotifier.checkAfterSwitchToStable', () {
    test(
      'AC-7: fetch+parse+compare end-to-end → hint visible with the '
      'parsed stable version, using an injected fetch (no real network)',
      () async {
        fetchAppcastFn = (url) async => _stableAppcastFixture;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(stableRevertHintProvider.notifier)
            .checkAfterSwitchToStable(
              installedVersionOverride: '1.2.44-beta.1',
            );

        final state = container.read(stableRevertHintProvider);
        expect(state.visible, isTrue);
        expect(state.stableVersion, '1.2.43');
      },
    );

    test(
      'AC-3: no false hint once the stable feed has caught up (post-promotion)',
      () async {
        fetchAppcastFn = (url) async => _stableAppcastFixture; // serves 1.2.43
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await container
            .read(stableRevertHintProvider.notifier)
            // Installed is now behind/equal to stable-latest (promoted case).
            .checkAfterSwitchToStable(installedVersionOverride: '1.2.43');

        expect(container.read(stableRevertHintProvider).visible, isFalse);
      },
    );

    test('a failing fetch is swallowed and never shows the hint', () async {
      fetchAppcastFn = (url) async => throw Exception('offline');
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(stableRevertHintProvider.notifier)
          .checkAfterSwitchToStable(installedVersionOverride: '1.2.44-beta.1');

      expect(container.read(stableRevertHintProvider).visible, isFalse);
    });

    test('the fetch targets the STABLE appcast, never the beta one', () async {
      String? requestedUrl;
      fetchAppcastFn = (url) async {
        requestedUrl = url;
        return _stableAppcastFixture;
      };
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(stableRevertHintProvider.notifier)
          .checkAfterSwitchToStable(installedVersionOverride: '1.2.44-beta.1');

      expect(requestedUrl, isNotNull);
      expect(requestedUrl, contains('appcast.xml'));
      expect(requestedUrl, isNot(contains('appcast-beta.xml')));
    });

    test('dismiss() clears a visible hint', () async {
      fetchAppcastFn = (url) async => _stableAppcastFixture;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(stableRevertHintProvider.notifier);

      await notifier.checkAfterSwitchToStable(
        installedVersionOverride: '1.2.44-beta.1',
      );
      expect(container.read(stableRevertHintProvider).visible, isTrue);

      notifier.dismiss();
      expect(container.read(stableRevertHintProvider).visible, isFalse);
    });

    test('shown once per switch: re-reading state without re-invoking the '
        'check does not re-trigger it (no rebuild spam)', () async {
      var fetchCount = 0;
      fetchAppcastFn = (url) async {
        fetchCount++;
        return _stableAppcastFixture;
      };
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(stableRevertHintProvider.notifier);

      await notifier.checkAfterSwitchToStable(
        installedVersionOverride: '1.2.44-beta.1',
      );
      // Simulate multiple rebuilds/navigations reading the same state.
      container.read(stableRevertHintProvider);
      container.read(stableRevertHintProvider);
      container.read(stableRevertHintProvider);

      expect(fetchCount, 1);
      expect(container.read(stableRevertHintProvider).visible, isTrue);
    });
  });
}
