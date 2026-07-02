import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';
import 'package:whispaste/services/update_channel_service.dart';

void main() {
  // Captured seam invocations for the current test.
  String? feedUrl;
  int? interval;
  var checkCalled = false;
  bool? checkInBackground;

  /// Wires the seams to in-memory captures and forces the platform branch.
  void installSeams({required bool sparklePlatform}) {
    feedUrl = null;
    interval = null;
    checkCalled = false;
    checkInBackground = null;
    platformSupportsSparkle = () => sparklePlatform;
    setFeedUrlFn = (url) async => feedUrl = url;
    setIntervalFn = (seconds) async => interval = seconds;
    checkForUpdatesFn = ({inBackground}) async {
      checkCalled = true;
      checkInBackground = inBackground;
    };
  }

  tearDown(() {
    // Leave the seams on harmless no-ops so the next suite never reaches the
    // native singleton via the lazy production defaults.
    platformSupportsSparkle = () => false;
    setFeedUrlFn = (_) async {};
    setIntervalFn = (_) async {};
    checkForUpdatesFn = ({inBackground}) async {};
  });

  group('appcastFeedUrl', () {
    test('stable → GitHub releases/latest/download/appcast.xml', () {
      final url = appcastFeedUrl(UpdateChannel.stable);
      expect(url, startsWith('https://github.com/whispaste/'));
      expect(url, endsWith('/releases/latest/download/appcast.xml'));
    });

    test('beta → raw.githubusercontent.com beta-appcast-pointer branch', () {
      expect(
        appcastFeedUrl(UpdateChannel.beta),
        endsWith(
          '/beta-appcast-pointer/appcast-beta.xml',
        ),
      );
      expect(
        appcastFeedUrl(UpdateChannel.beta),
        startsWith('https://raw.githubusercontent.com/whispaste/'),
      );
    });

    test('both URLs target the whispaste/whispaste repo (single-source)', () {
      for (final channel in UpdateChannel.values) {
        expect(appcastFeedUrl(channel), contains('whispaste/whispaste'));
      }
    });

    test('beta feed never collides with the stable latest/download path', () {
      expect(
        appcastFeedUrl(UpdateChannel.beta),
        isNot(contains('latest/download')),
      );
    });
  });

  group('shouldUseAutoUpdater', () {
    test('store channel is never eligible, even on a Sparkle platform', () {
      installSeams(sparklePlatform: true);
      expect(shouldUseAutoUpdater(DeployChannel.store), isFalse);
    });

    test('installer/portable are eligible on a Sparkle platform', () {
      installSeams(sparklePlatform: true);
      expect(shouldUseAutoUpdater(DeployChannel.installer), isTrue);
      expect(shouldUseAutoUpdater(DeployChannel.portable), isTrue);
    });

    test('no channel is eligible on a non-Sparkle platform (Linux)', () {
      installSeams(sparklePlatform: false);
      expect(shouldUseAutoUpdater(DeployChannel.store), isFalse);
      expect(shouldUseAutoUpdater(DeployChannel.installer), isFalse);
      expect(shouldUseAutoUpdater(DeployChannel.portable), isFalse);
    });
  });

  group('initAutoUpdater', () {
    test('store channel → no-op (feed URL never set, no check)', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.store, UpdateChannel.beta);
      expect(feedUrl, isNull);
      expect(interval, isNull);
      expect(checkCalled, isFalse);
    });

    test('non-Sparkle platform → no-op for any non-store channel', () async {
      installSeams(sparklePlatform: false);
      await initAutoUpdater(DeployChannel.installer, UpdateChannel.stable);
      expect(feedUrl, isNull);
      expect(checkCalled, isFalse);
    });

    test(
      'installer + stable → sets the stable appcast feed, interval, and checks',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.installer, UpdateChannel.stable);
        expect(feedUrl, appcastFeedUrl(UpdateChannel.stable));
        expect(feedUrl, contains('/releases/latest/download/appcast.xml'));
        expect(interval, greaterThanOrEqualTo(3600));
        expect(checkCalled, isTrue);
        expect(checkInBackground, isTrue);
      },
    );

    test(
      'AC-1: installer + beta → setFeedURL is called with the BETA feed URL',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.installer, UpdateChannel.beta);
        expect(feedUrl, appcastFeedUrl(UpdateChannel.beta));
        expect(feedUrl, contains('beta-appcast-pointer'));
        expect(feedUrl, contains('appcast-beta.xml'));
        expect(feedUrl, isNot(contains('latest/download')));
        expect(checkCalled, isTrue);
      },
    );

    test('portable + stable → also initializes the self-updater', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.portable, UpdateChannel.stable);
      expect(feedUrl, appcastFeedUrl(UpdateChannel.stable));
      expect(checkCalled, isTrue);
    });

    test(
      'store deploy channel stays a no-op even on the beta update channel',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.store, UpdateChannel.beta);
        expect(feedUrl, isNull);
        expect(checkCalled, isFalse);
      },
    );

    test(
      'a failing native call is swallowed — startup is never blocked',
      () async {
        installSeams(sparklePlatform: true);
        setFeedUrlFn = (_) async => throw Exception('native plugin missing');
        // Must not throw.
        await initAutoUpdater(DeployChannel.installer, UpdateChannel.stable);
        expect(checkCalled, isFalse); // aborted after the failing setFeedURL
      },
    );
  });

  group('presentSparkleUpdate', () {
    test('re-asserts the channel-derived feed URL and triggers a FOREGROUND '
        '(UI) check — the status-bar chip opens the native dialog, not a '
        'background probe', () async {
      installSeams(sparklePlatform: true);
      await presentSparkleUpdate(UpdateChannel.stable);
      expect(feedUrl, appcastFeedUrl(UpdateChannel.stable));
      expect(checkCalled, isTrue);
      expect(checkInBackground, isFalse); // foreground → shows Sparkle UI
    });

    test('beta channel → foreground check uses the beta feed URL', () async {
      installSeams(sparklePlatform: true);
      await presentSparkleUpdate(UpdateChannel.beta);
      expect(feedUrl, appcastFeedUrl(UpdateChannel.beta));
      expect(feedUrl, contains('beta-appcast-pointer'));
    });

    test(
      'a failing native call is swallowed — the tap never crashes',
      () async {
        installSeams(sparklePlatform: true);
        setFeedUrlFn = (_) async => throw Exception('native plugin missing');
        await presentSparkleUpdate(UpdateChannel.stable); // must not throw
        expect(checkCalled, isFalse);
      },
    );
  });
}
