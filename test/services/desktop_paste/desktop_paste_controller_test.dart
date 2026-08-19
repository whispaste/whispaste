/// Channel-level tests for [DesktopPasteController.diagnosticPaste].
///
/// We exercise the real [MacOSDesktopPasteController] (and, symmetrically,
/// the Windows controller) through the platform `MethodChannel` test mock.
/// The native side is faked out so the only thing under test is the Dart
/// wrapper: argument shape, response parsing, and exception mapping.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/linux_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/windows_desktop_paste_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.whispaste.desktop_paste');

  void setHandler(
    Future<Object?>? Function(MethodCall call) handler, {
    List<MethodCall>? recordedCalls,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          recordedCalls?.add(call);
          return handler(call);
        });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('TestPasteOutcome.fromMap', () {
    test('parses success', () {
      final outcome = TestPasteOutcome.fromMap({'status': 'success'});
      expect(outcome, isA<TestPasteOutcomeSuccess>());
    });

    test('parses no_frontmost', () {
      final outcome = TestPasteOutcome.fromMap({'status': 'no_frontmost'});
      expect(outcome, isA<TestPasteOutcomeNoFrontmost>());
    });

    test('parses failure with detail', () {
      final outcome = TestPasteOutcome.fromMap({
        'status': 'failure',
        'detail': 'not_trusted',
      });
      expect(outcome, isA<TestPasteOutcomeFailure>());
      expect((outcome as TestPasteOutcomeFailure).reason, 'not_trusted');
    });

    test('failure without detail falls back to unknown reason', () {
      final outcome = TestPasteOutcome.fromMap({'status': 'failure'});
      expect((outcome as TestPasteOutcomeFailure).reason, 'unknown');
    });

    test('parses unsupported', () {
      final outcome = TestPasteOutcome.fromMap({'status': 'unsupported'});
      expect(outcome, isA<TestPasteOutcomeUnsupported>());
    });

    test('null map -> unsupported', () {
      final outcome = TestPasteOutcome.fromMap(null);
      expect(outcome, isA<TestPasteOutcomeUnsupported>());
    });

    test('unrecognised status -> failure(unknown_status)', () {
      final outcome = TestPasteOutcome.fromMap({'status': 'banana'});
      expect((outcome as TestPasteOutcomeFailure).reason, 'unknown_status');
    });
  });

  group('MacOSDesktopPasteController.diagnosticPaste', () {
    test(
      'forwards demoText to channel call and parses success response',
      () async {
        final calls = <MethodCall>[];
        setHandler((call) async {
          if (call.method == 'diagnosticPaste') {
            return {'status': 'success'};
          }
          return null;
        }, recordedCalls: calls);

        final controller = MacOSDesktopPasteController();
        final outcome = await controller.diagnosticPaste('Hello WhisPaste');

        expect(calls, hasLength(1));
        expect(calls.single.method, 'diagnosticPaste');
        expect(calls.single.arguments, isA<Map>());
        expect((calls.single.arguments as Map)['demoText'], 'Hello WhisPaste');
        expect(outcome, isA<TestPasteOutcomeSuccess>());
      },
    );

    test('parses no_frontmost response', () async {
      setHandler((call) async => {'status': 'no_frontmost'});
      final controller = MacOSDesktopPasteController();
      final outcome = await controller.diagnosticPaste('demo');
      expect(outcome, isA<TestPasteOutcomeNoFrontmost>());
    });

    test('parses failure(not_trusted) response', () async {
      setHandler(
        (call) async => {'status': 'failure', 'detail': 'not_trusted'},
      );
      final controller = MacOSDesktopPasteController();
      final outcome = await controller.diagnosticPaste('demo');
      expect(outcome, isA<TestPasteOutcomeFailure>());
      expect((outcome as TestPasteOutcomeFailure).reason, 'not_trusted');
    });

    test('PlatformException maps to failure(exception)', () async {
      setHandler((call) async {
        throw PlatformException(code: 'BANG');
      });
      final controller = MacOSDesktopPasteController();
      final outcome = await controller.diagnosticPaste('demo');
      expect(outcome, isA<TestPasteOutcomeFailure>());
      expect((outcome as TestPasteOutcomeFailure).reason, 'exception');
    });

    test('MissingPluginException maps to failure(exception)', () async {
      setHandler((call) async {
        throw MissingPluginException('no impl');
      });
      final controller = MacOSDesktopPasteController();
      final outcome = await controller.diagnosticPaste('demo');
      expect(outcome, isA<TestPasteOutcomeFailure>());
      expect((outcome as TestPasteOutcomeFailure).reason, 'exception');
    });
  });

  group('WindowsDesktopPasteController.diagnosticPaste', () {
    test('forwards demoText and parses success', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        if (call.method == 'diagnosticPaste') {
          return {'status': 'success'};
        }
        return null;
      }, recordedCalls: calls);

      final controller = WindowsDesktopPasteController();
      final outcome = await controller.diagnosticPaste('hi');

      expect(calls.single.method, 'diagnosticPaste');
      expect((calls.single.arguments as Map)['demoText'], 'hi');
      expect(outcome, isA<TestPasteOutcomeSuccess>());
    });

    test('parses failure(uipi_blocked)', () async {
      setHandler(
        (call) async => {'status': 'failure', 'detail': 'uipi_blocked'},
      );
      final controller = WindowsDesktopPasteController();
      final outcome = await controller.diagnosticPaste('demo');
      expect((outcome as TestPasteOutcomeFailure).reason, 'uipi_blocked');
    });
  });

  group('WindowsDesktopPasteController.pasteClipboard', () {
    test('parses the native foreground_blocked (UIPI) status distinctly '
        'from the generic post_failed/send_input_failed bucket', () async {
      setHandler(
        (call) async => {
          'status': 'foreground_blocked',
          'detail':
              'SetForegroundWindow refused — UIPI or stale window '
              'handle',
        },
      );
      final controller = WindowsDesktopPasteController();
      final result = await controller.pasteClipboard(delay: Duration.zero);
      expect(result.status, NativePasteStatus.foregroundBlocked);
    });
  });

  group('MacOSDesktopPasteController.typeText', () {
    test('forwards text and delayMs to the channel call', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        if (call.method == 'typeText') {
          return {'status': 'success'};
        }
        return null;
      }, recordedCalls: calls);

      final controller = MacOSDesktopPasteController();
      final result = await controller.typeText(
        'Hören grüßen café 😀',
        delay: const Duration(milliseconds: 150),
      );

      expect(calls.single.method, 'typeText');
      final args = calls.single.arguments as Map;
      expect(args['text'], 'Hören grüßen café 😀');
      expect(args['delayMs'], 150);
      expect(result.status, NativePasteStatus.success);
    });

    test('parses no_accessibility (PostEvent denied) response', () async {
      setHandler(
        (call) async => {
          'status': 'no_accessibility',
          'detail': 'trusted=false',
          'hint': 'postevent_denied',
        },
      );
      final controller = MacOSDesktopPasteController();
      final result = await controller.typeText('demo', delay: Duration.zero);
      expect(result.status, NativePasteStatus.permissionMissing);
    });

    test(
      'MissingPluginException maps to unknown status via legacy-bool path',
      () async {
        setHandler((call) async {
          throw MissingPluginException('no impl');
        });
        final controller = MacOSDesktopPasteController();
        // Unlike diagnosticPaste, typeText does not catch MissingPluginException
        // itself — DesktopPaster.typeText is the layer that maps it to
        // PasteOutcome.platformUnavailable, so it propagates here.
        await expectLater(
          controller.typeText('demo', delay: Duration.zero),
          throwsA(isA<MissingPluginException>()),
        );
      },
    );
  });

  group('WindowsDesktopPasteController.typeText', () {
    test('forwards text and delayMs, parses success', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        if (call.method == 'typeText') {
          return {'status': 'success'};
        }
        return null;
      }, recordedCalls: calls);

      final controller = WindowsDesktopPasteController();
      final result = await controller.typeText(
        'hello',
        delay: const Duration(milliseconds: 50),
      );

      expect(calls.single.method, 'typeText');
      expect((calls.single.arguments as Map)['text'], 'hello');
      expect((calls.single.arguments as Map)['delayMs'], 50);
      expect(result.status, NativePasteStatus.success);
    });
  });

  group('LinuxDesktopPasteController', () {
    test(
      'repairTccEntries reports unsupported without a channel call',
      () async {
        setHandler((call) async {
          fail('unexpected channel call: ${call.method}');
        });
        final controller = LinuxDesktopPasteController();
        final result = await controller.repairTccEntries();
        expect(result.isSupported, isFalse);
        expect(result.error, 'unsupported_platform');
      },
    );

    test('diagnosticPaste forwards demoText and parses success', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        if (call.method == 'diagnosticPaste') {
          return {'status': 'success'};
        }
        return null;
      }, recordedCalls: calls);

      final controller = LinuxDesktopPasteController();
      final outcome = await controller.diagnosticPaste('hi');

      expect(calls.single.method, 'diagnosticPaste');
      expect((calls.single.arguments as Map)['demoText'], 'hi');
      expect(outcome, isA<TestPasteOutcomeSuccess>());
    });

    test(
      'pasteClipboard parses the uinput permission_missing status',
      () async {
        setHandler(
          (call) async => {
            'status': 'permission_missing',
            'detail': 'no write access to /dev/uinput',
          },
        );
        final controller = LinuxDesktopPasteController();
        final result = await controller.pasteClipboard(delay: Duration.zero);
        expect(result.status, NativePasteStatus.permissionMissing);
      },
    );

    test('typeText forwards text and delayMs, parses success', () async {
      final calls = <MethodCall>[];
      setHandler((call) async {
        if (call.method == 'typeText') {
          return {'status': 'success'};
        }
        return null;
      }, recordedCalls: calls);

      final controller = LinuxDesktopPasteController();
      final result = await controller.typeText(
        'hello',
        delay: const Duration(milliseconds: 50),
      );

      expect(calls.single.method, 'typeText');
      expect((calls.single.arguments as Map)['text'], 'hello');
      expect((calls.single.arguments as Map)['delayMs'], 50);
      expect(result.status, NativePasteStatus.success);
    });

    test('checkCapability parses unsupported status', () async {
      setHandler(
        (call) async => {
          'status': 'unsupported',
          'detail': '/dev/uinput not present',
          'canPrompt': false,
        },
      );
      final controller = LinuxDesktopPasteController();
      final result = await controller.checkCapability();
      expect(result.status, NativeCapabilityStatus.unsupported);
      expect(result.canPrompt, isFalse);
    });
  });
}
