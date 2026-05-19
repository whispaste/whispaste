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
}
