import 'dart:async';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/auto_updater_service.dart';
import 'package:whispaste/services/deploy_channel_service.dart';

void main() {
  // Captured seam invocations for the current test.
  String? feedUrl;
  var checkCalled = false;
  var checkCount = 0;
  bool? checkInBackground;

  /// Wires the seams to in-memory captures and forces the platform branch.
  void installSeams({required bool sparklePlatform}) {
    feedUrl = null;
    checkCalled = false;
    checkCount = 0;
    checkInBackground = null;
    platformSupportsSparkle = () => sparklePlatform;
    setFeedUrlFn = (url) async => feedUrl = url;
    checkForUpdatesFn = ({inBackground}) async {
      checkCalled = true;
      checkCount++;
      checkInBackground = inBackground;
    };
  }

  tearDown(() {
    // Leave the seams on harmless no-ops so the next suite never reaches the
    // native singleton via the lazy production defaults.
    platformSupportsSparkle = () => false;
    setFeedUrlFn = (_) async {};
    checkForUpdatesFn = ({inBackground}) async {};
    addUpdaterListenerFn = (_) {};
    stopAutomaticUpdateChecks();
  });

  group('appcastFeedUrl', () {
    test('stable → GitHub releases/latest/download/appcast.xml', () {
      final url = appcastFeedUrl();
      expect(url, startsWith('https://github.com/whispaste/'));
      expect(url, endsWith('/releases/latest/download/appcast.xml'));
    });

    test('targets the whispaste/whispaste repo (single-source)', () {
      expect(appcastFeedUrl(), contains('whispaste/whispaste'));
    });
  });

  group('shouldUseAutoUpdater', () {
    test('store channel is never eligible, even on a Sparkle platform', () {
      installSeams(sparklePlatform: true);
      expect(shouldUseAutoUpdater(DeployChannel.store), isFalse);
    });

    test(
      'packageManaged channel is never eligible either, even on a Sparkle platform',
      () {
        installSeams(sparklePlatform: true);
        expect(shouldUseAutoUpdater(DeployChannel.packageManaged), isFalse);
      },
    );

    test('installer/portable are eligible on a Sparkle platform', () {
      installSeams(sparklePlatform: true);
      expect(shouldUseAutoUpdater(DeployChannel.installer), isTrue);
      expect(shouldUseAutoUpdater(DeployChannel.portable), isTrue);
    });

    test('no channel is eligible on a non-Sparkle platform (Linux)', () {
      installSeams(sparklePlatform: false);
      expect(shouldUseAutoUpdater(DeployChannel.store), isFalse);
      expect(shouldUseAutoUpdater(DeployChannel.packageManaged), isFalse);
      expect(shouldUseAutoUpdater(DeployChannel.installer), isFalse);
      expect(shouldUseAutoUpdater(DeployChannel.portable), isFalse);
    });
  });

  group('initAutoUpdater', () {
    test('store channel → no-op (feed URL never set, no check)', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.store);
      expect(feedUrl, isNull);
      expect(checkCalled, isFalse);
    });

    test(
      'packageManaged channel → no-op (feed URL never set, no check)',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.packageManaged);
        expect(feedUrl, isNull);
        expect(checkCalled, isFalse);
      },
    );

    test('non-Sparkle platform → no-op for any non-store channel', () async {
      installSeams(sparklePlatform: false);
      await initAutoUpdater(DeployChannel.installer);
      expect(feedUrl, isNull);
      expect(checkCalled, isFalse);
    });

    test(
      'installer + stable → sets the stable appcast feed and checks',
      () async {
        installSeams(sparklePlatform: true);
        await initAutoUpdater(DeployChannel.installer);
        expect(feedUrl, appcastFeedUrl());
        expect(feedUrl, contains('/releases/latest/download/appcast.xml'));
        expect(checkCalled, isTrue);
        expect(checkInBackground, isTrue);
      },
    );

    test('portable + stable → also initializes the self-updater', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.portable);
      expect(feedUrl, appcastFeedUrl());
      expect(checkCalled, isTrue);
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

    test('start without a network: the failed background check is swallowed '
        'and the schedule keeps running (#235)', () {
      fakeAsync((async) {
        installSeams(sparklePlatform: true);
        checkForUpdatesFn = ({inBackground}) async {
          checkCount++;
          throw const SocketException('Failed host lookup: github.com');
        };
        // An error escaping the call would fail the fakeAsync zone.
        var finished = false;
        unawaited(
          initAutoUpdater(DeployChannel.installer).then((_) => finished = true),
        );
        async.flushMicrotasks();
        expect(finished, isTrue);
        expect(checkCount, 1);

        async.elapse(automaticUpdateCheckInterval);
        expect(checkCount, 2);
        stopAutomaticUpdateChecks();
      });
    });

    test('automatic checks off → the native updater is never touched '
        '(no feed URL, no appcast request)', () async {
      installSeams(sparklePlatform: true);
      await initAutoUpdater(DeployChannel.installer, isEnabled: () => false);
      expect(feedUrl, isNull);
      expect(checkCalled, isFalse);
    });

    test('checks again every 24 h and follows the toggle at runtime', () {
      fakeAsync((async) {
        installSeams(sparklePlatform: true);
        var enabled = true;
        initAutoUpdater(DeployChannel.installer, isEnabled: () => enabled);
        async.flushMicrotasks();
        expect(checkCount, 1);

        async.elapse(const Duration(hours: 24));
        expect(checkCount, 2);

        enabled = false;
        async.elapse(const Duration(hours: 24));
        expect(checkCount, 2);

        enabled = true;
        async.elapse(const Duration(hours: 24));
        expect(checkCount, 3);
      });
    });
  });

  group('startAutomaticUpdateChecks (Linux GitHub check)', () {
    test('first check only when enabled, then every 24 h', () {
      fakeAsync((async) {
        var calls = 0;
        var enabled = false;
        startAutomaticUpdateChecks(
          check: () async => calls++,
          enabled: () => enabled,
        );
        async.flushMicrotasks();
        expect(calls, 0);

        enabled = true;
        async.elapse(const Duration(hours: 24));
        expect(calls, 1);
      });
    });
  });

  group('presentSparkleUpdate', () {
    test('re-asserts the stable feed URL and triggers a FOREGROUND '
        '(UI) check — the status-bar chip opens the native dialog, not a '
        'background probe', () async {
      installSeams(sparklePlatform: true);
      await presentSparkleUpdate();
      expect(feedUrl, appcastFeedUrl());
      expect(checkCalled, isTrue);
      expect(checkInBackground, isFalse); // foreground → shows Sparkle UI
    });

    test(
      'a failing native call is swallowed — the tap never crashes',
      () async {
        installSeams(sparklePlatform: true);
        setFeedUrlFn = (_) async => throw Exception('native plugin missing');
        await presentSparkleUpdate(); // must not throw
        expect(checkCalled, isFalse);
      },
    );
  });

  group('checkSparkleUpdateQuietly (#1881)', () {
    test('a manual check runs in the background, so no native '
        '"up to date" window appears', () async {
      installSeams(sparklePlatform: true);
      await checkSparkleUpdateQuietly();
      expect(feedUrl, appcastFeedUrl());
      expect(checkCalled, isTrue);
      expect(checkInBackground, isTrue);
    });
  });

  group('registerSparkleListener', () {
    // Captured callback invocations for the current test.
    var checkingCalled = false;
    String? availableVersion;
    String? availableNotesUrl;
    var upToDateCalled = false;
    var readyToInstallCalled = false;
    String? errorMessage;
    UpdaterListener? captured;

    void reset() {
      checkingCalled = false;
      availableVersion = null;
      availableNotesUrl = null;
      upToDateCalled = false;
      readyToInstallCalled = false;
      errorMessage = null;
      captured = null;
    }

    void register({required bool sparklePlatform}) {
      reset();
      platformSupportsSparkle = () => sparklePlatform;
      addUpdaterListenerFn = (listener) => captured = listener;
      registerSparkleListener(
        onChecking: () => checkingCalled = true,
        onAvailable: (version, releaseNotesUrl) {
          availableVersion = version;
          availableNotesUrl = releaseNotesUrl;
        },
        onUpToDate: () => upToDateCalled = true,
        onReadyToInstall: () => readyToInstallCalled = true,
        onError: (message) => errorMessage = message,
      );
    }

    test('non-Sparkle platform (Linux) → no listener registered', () {
      register(sparklePlatform: false);
      expect(captured, isNull);
    });

    test('Sparkle platform → registers a listener', () {
      register(sparklePlatform: true);
      expect(captured, isNotNull);
    });

    test(
      'onUpdaterUpdateAvailable → onAvailable fires with version + notes URL '
      '(PRD Bug 1: this is what mirrors the native check into the app UI)',
      () {
        register(sparklePlatform: true);
        captured!.onUpdaterUpdateAvailable(
          const AppcastItem(
            displayVersionString: '1.2.44-beta.6',
            releaseNotesURL: 'https://example.invalid/notes',
          ),
        );
        expect(availableVersion, '1.2.44-beta.6');
        expect(availableNotesUrl, 'https://example.invalid/notes');
      },
    );

    test('onUpdaterUpdateAvailable falls back to versionString when '
        'displayVersionString is absent', () {
      register(sparklePlatform: true);
      captured!.onUpdaterUpdateAvailable(
        const AppcastItem(versionString: '1.2.44-beta.6'),
      );
      expect(availableVersion, '1.2.44-beta.6');
    });

    test('onUpdaterUpdateAvailable with a null item → no callback fires', () {
      register(sparklePlatform: true);
      captured!.onUpdaterUpdateAvailable(null);
      expect(availableVersion, isNull);
    });

    test('onUpdaterCheckingForUpdate → onChecking fires', () {
      register(sparklePlatform: true);
      captured!.onUpdaterCheckingForUpdate(null);
      expect(checkingCalled, isTrue);
    });

    test('onUpdaterUpdateNotAvailable → onUpToDate fires', () {
      register(sparklePlatform: true);
      captured!.onUpdaterUpdateNotAvailable(null);
      expect(upToDateCalled, isTrue);
    });

    test('onUpdaterError → onError fires with the message', () {
      register(sparklePlatform: true);
      captured!.onUpdaterError(UpdaterError('boom'));
      expect(errorMessage, 'boom');
    });

    test('onUpdaterError with a null error → a fallback message is used', () {
      register(sparklePlatform: true);
      captured!.onUpdaterError(null);
      expect(errorMessage, isNotEmpty);
    });

    test('onUpdaterUpdateDownloaded → onReadyToInstall fires (the download '
        'finished; there is no progress signal, so this is the only '
        'intermediate state exposed by the native path)', () {
      register(sparklePlatform: true);
      captured!.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.2.44-beta.9'),
      );
      expect(readyToInstallCalled, isTrue);
    });

    test('onUpdaterBeforeQuitForUpdate → onReadyToInstall fires (Sparkle is '
        'about to auto-install on quit)', () {
      register(sparklePlatform: true);
      captured!.onUpdaterBeforeQuitForUpdate(
        const AppcastItem(displayVersionString: '1.2.44-beta.9'),
      );
      expect(readyToInstallCalled, isTrue);
    });
  });

  group('native updaters never check on their own', () {
    // The Dart schedule above is only the single switch if Sparkle and
    // WinSparkle keep their own schedulers off.
    test('macOS: Info.plist disables Sparkle automatic checks and the '
        'runner drops a stored per-user override', () {
      final plist = File('macos/Runner/Info.plist').readAsStringSync();
      expect(
        plist,
        matches(RegExp(r'<key>SUEnableAutomaticChecks</key>\s*<false/>')),
      );
      expect(
        File('macos/Runner/MainFlutterWindow.swift').readAsStringSync(),
        contains('removeObject(forKey: "SUEnableAutomaticChecks")'),
      );
    });

    test('Windows: WinSparkle automatic checks are off before init', () {
      final src = File(
        'packages/auto_updater_windows/windows/auto_updater.h',
      ).readAsStringSync();
      final off = src.indexOf('win_sparkle_set_automatic_check_for_updates(0)');
      expect(off, isNonNegative);
      expect(off, lessThan(src.indexOf('win_sparkle_init();')));
    });
  });
}
