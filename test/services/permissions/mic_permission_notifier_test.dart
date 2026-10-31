/// Unit tests for [MicPermissionNotifier].
///
/// Style mirrors `paste_capability_notifier_test.dart`: a hand-rolled fake
/// for the platform dependency ([MicPermissionChecker]), Riverpod overrides
/// for DI. No mockito/build_runner required.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:whispaste/services/permissions/mic_permission_notifier.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeMicPermissionChecker implements MicPermissionChecker {
  _FakeMicPermissionChecker({bool initial = false}) : _next = initial;

  bool _next;
  final List<bool> calls = <bool>[];
  Completer<void>? _gate;

  set nextResult(bool granted) => _next = granted;

  /// If set, [check] awaits this completer before resolving — used to model
  /// overlapping-call coalescing.
  set gate(Completer<void>? c) => _gate = c;

  @override
  Future<bool> check({required bool request}) async {
    calls.add(request);
    final g = _gate;
    if (g != null) await g.future;
    return _next;
  }
}

/// Records every URL [MicPermissionNotifier.openSystemSettings] hands off to
/// the OS, so tests can assert whether the Settings deep-link fired without
/// touching a real platform channel.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return true;
  }
}

ProviderContainer _container({MicPermissionChecker? checker}) {
  return ProviderContainer(
    overrides: [
      if (checker != null)
        micPermissionCheckerProvider.overrideWithValue(checker),
    ],
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeUrlLauncher urlLauncher;

  setUp(() {
    urlLauncher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = urlLauncher;
  });

  group('MicPermissionNotifier — check()', () {
    test('check() with a granted result promotes state to granted', () async {
      final checker = _FakeMicPermissionChecker(initial: true);
      final container = _container(checker: checker);
      addTearDown(container.dispose);

      final notifier = container.read(micPermissionNotifierProvider.notifier);
      final result = await notifier.check();

      expect(result, isTrue);
      expect(checker.calls, [false]);
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.granted,
      );
    });

    test(
      'check() with a missing result leaves status at unknown — never claims '
      'denied from a passive read',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        final result = await notifier.check();

        expect(result, isFalse);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.unknown,
        );
      },
    );

    test(
      'overlapping check() calls are coalesced into one platform call',
      () async {
        final checker = _FakeMicPermissionChecker(initial: true);
        final gate = Completer<void>();
        checker.gate = gate;
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        final first = notifier.check();
        final second = notifier.check();
        gate.complete();
        await Future.wait([first, second]);

        expect(checker.calls.length, 1);
      },
    );
  });

  group('MicPermissionNotifier — request()', () {
    test('first request() this process fires the OS-prompted check and '
        'resolves to granted', () async {
      final checker = _FakeMicPermissionChecker(initial: true);
      final container = _container(checker: checker);
      addTearDown(container.dispose);

      final notifier = container.read(micPermissionNotifierProvider.notifier);
      final result = await notifier.request();

      expect(result, isTrue);
      expect(checker.calls, [true]);
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.granted,
      );
    });

    test('first request() this process, denied, sets status to denied '
        'without opening Settings', () async {
      final checker = _FakeMicPermissionChecker(initial: false);
      final container = _container(checker: checker);
      addTearDown(container.dispose);

      final notifier = container.read(micPermissionNotifierProvider.notifier);
      final result = await notifier.request();

      expect(result, isFalse);
      expect(checker.calls, [true]);
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.denied,
      );
      expect(
        urlLauncher.launchedUrls,
        isEmpty,
        reason:
            'the OS shows its own dialog on the first ask this process — no '
            'deep-link needed yet',
      );
      expect(
        notifier.isPolling,
        isFalse,
        reason: 'nothing to wait for until the user has been sent to Settings',
      );
    });

    test('a second request() this process still asks the platform (a '
        'silent, dialog-free call) instead of assuming denied, and — if '
        'still denied — routes to the Settings deep-link and starts '
        'polling', () async {
      final checker = _FakeMicPermissionChecker(initial: false);
      final container = _container(checker: checker);
      addTearDown(container.dispose);

      final notifier = container.read(micPermissionNotifierProvider.notifier);
      await notifier.request();
      final second = await notifier.request();

      expect(second, isFalse);
      expect(
        checker.calls,
        [true, true],
        reason:
            'a repeat ask never claims denied without evidence — it must '
            'still observe a grant made outside the app since the first ask',
      );
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.denied,
      );
      expect(
        urlLauncher.launchedUrls,
        hasLength(1),
        reason: 'second denial routes straight to the Settings pane',
      );
      expect(notifier.isPolling, isTrue);
    }, skip: !(Platform.isMacOS || Platform.isWindows));

    test(
      'a second request() that turns out granted (flipped outside the '
      'app between calls) resolves to granted without touching Settings',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        await notifier.request();
        checker.nextResult = true;
        final second = await notifier.request();

        expect(second, isTrue);
        expect(checker.calls, [true, true]);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.granted,
        );
        expect(urlLauncher.launchedUrls, isEmpty);
        expect(notifier.isPolling, isFalse);
      },
    );

    test(
      'openSystemSettings is a no-op on Linux — no deep-link target exists',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        await notifier.openSystemSettings();

        expect(urlLauncher.launchedUrls, isEmpty);
      },
      skip: !Platform.isLinux,
    );

    test(
      'openSystemSettings opens the macOS microphone privacy pane',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        await notifier.openSystemSettings();

        expect(urlLauncher.launchedUrls, [
          'x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone',
        ]);
      },
      skip: !Platform.isMacOS,
    );

    test(
      'openSystemSettings opens the Windows microphone privacy page',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        await notifier.openSystemSettings();

        expect(urlLauncher.launchedUrls, ['ms-settings:privacy-microphone']);
      },
      skip: !Platform.isWindows,
    );
  });

  group('MicPermissionNotifier — polling', () {
    test(
      'startPolling calls check periodically until granted, then stops itself',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        notifier.startPolling(
          interval: const Duration(milliseconds: 20),
          timeout: const Duration(seconds: 5),
        );

        await Future<void>.delayed(const Duration(milliseconds: 70));
        expect(checker.calls.length, greaterThanOrEqualTo(2));
        expect(notifier.isPolling, isTrue);

        checker.nextResult = true;
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(notifier.isPolling, isFalse);
        expect(
          container.read(micPermissionNotifierProvider).status,
          MicPermissionStatus.granted,
        );

        final callsAfterStop = checker.calls.length;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(checker.calls.length, callsAfterStop);
      },
    );

    test(
      'startPolling self-stops after timeout even if never granted',
      () async {
        final checker = _FakeMicPermissionChecker(initial: false);
        final container = _container(checker: checker);
        addTearDown(container.dispose);

        final notifier = container.read(micPermissionNotifierProvider.notifier);
        notifier.startPolling(
          interval: const Duration(milliseconds: 20),
          timeout: const Duration(milliseconds: 80),
        );

        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(notifier.isPolling, isFalse);

        final callsAfterTimeout = checker.calls.length;
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(checker.calls.length, callsAfterTimeout);
      },
    );

    test('stopPolling is idempotent and safe to call repeatedly', () async {
      final checker = _FakeMicPermissionChecker(initial: false);
      final container = _container(checker: checker);
      addTearDown(container.dispose);

      final notifier = container.read(micPermissionNotifierProvider.notifier);

      notifier.stopPolling();
      notifier.stopPolling();
      expect(notifier.isPolling, isFalse);

      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      notifier.stopPolling();
      notifier.stopPolling();
      expect(notifier.isPolling, isFalse);

      final callsAfterStop = checker.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(checker.calls.length, callsAfterStop);
    });

    test('no timer survives provider disposal', () async {
      final checker = _FakeMicPermissionChecker(initial: false);
      final container = _container(checker: checker);

      final notifier = container.read(micPermissionNotifierProvider.notifier);
      notifier.startPolling(
        interval: const Duration(milliseconds: 20),
        timeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final callsBeforeDispose = checker.calls.length;

      container.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        checker.calls.length,
        callsBeforeDispose,
        reason: 'a timer that outlived disposal would keep calling check()',
      );
    });
  });
}
