import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

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
      await initAutoUpdater(DeployChannel.store);
      expect(feedUrl, isNull);
      expect(interval, isNull);
      expect(checkCalled, isFalse);
    });

    test('non-Sparkle platform → no-op for any non-store channel', () async {
      installSeams(sparklePlatform: false);
      await initAutoUpdater(DeployChannel.installer);
      expect(feedUrl, isNull);
      expect(checkCalled, isFalse);
    });

    test(
      'installer → sets the GitHub appcast feed, interval, and checks',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.installer);
        expect(feedUrl, kAppcastFeedUrl);
        expect(feedUrl, contains('/releases/latest/download/appcast.xml'));
        expect(interval, greaterThanOrEqualTo(3600));
        expect(checkCalled, isTrue);
        expect(checkInBackground, isTrue);
      },
    );

    test('portable → also initializes the self-updater', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.portable);
      expect(feedUrl, kAppcastFeedUrl);
      expect(checkCalled, isTrue);
    });

    test('feed URL points at the whispaste GitHub repo (single-source)', () {
      expect(kAppcastFeedUrl, startsWith('https://github.com/whispaste/'));
    });

    test(
      'a failing native call is swallowed — startup is never blocked',
      () async {
        installSeams(sparklePlatform: true);
        setFeedUrlFn = (_) async => throw Exception('native plugin missing');
        // Must not throw.
        await initAutoUpdater(DeployChannel.installer);
        expect(checkCalled, isFalse); // aborted after the failing setFeedURL
      },
    );
  });
}
