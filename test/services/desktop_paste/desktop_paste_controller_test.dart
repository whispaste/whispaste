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

      // getTargetBundleId runs first: it picks the terminal shortcut (V1).
      final call = calls.singleWhere((c) => c.method == 'typeText');
      expect((call.arguments as Map)['text'], 'hello');
      expect((call.arguments as Map)['delayMs'], 50);
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

  group('ClipboardReceiptBridge (receipt-based clipboard restore)', () {
    test('every desktop controller offers the receipt bridge (GR-015)', () {
      expect(MacOSDesktopPasteController(), isA<ClipboardReceiptBridge>());
      expect(WindowsDesktopPasteController(), isA<ClipboardReceiptBridge>());
      expect(LinuxDesktopPasteController(), isA<ClipboardReceiptBridge>());
    });

    test('the Linux receipt wait forwards the native answer', () async {
      final calls = <MethodCall>[];
      setHandler(
        (call) async =>
            call.method == 'waitForClipboardRead' ? {'status': 'read'} : true,
        recordedCalls: calls,
      );
      final controller = LinuxDesktopPasteController();

      expect(await controller.writeClipboardTextWithReceipt('hello'), isTrue);
      expect(
        await controller.waitForClipboardRead(),
        ClipboardReadReceipt.read,
      );
      expect(calls.map((c) => c.method), [
        'writeClipboardTextWithReceipt',
        'waitForClipboardRead',
      ]);
    });

    test('writeClipboardTextWithReceipt forwards the text and returns the '
        'native success flag', () async {
      final calls = <MethodCall>[];
      setHandler((call) async => true, recordedCalls: calls);

      final ok = await MacOSDesktopPasteController()
          .writeClipboardTextWithReceipt('hello');

      expect(ok, isTrue);
      expect(calls.single.method, 'writeClipboardTextWithReceipt');
      expect((calls.single.arguments as Map)['text'], 'hello');
    });

    test(
      'writeClipboardTextExcludingHistory uses the transient write on macOS',
      () async {
        final calls = <MethodCall>[];
        setHandler((call) async => true, recordedCalls: calls);

        final ok = await MacOSDesktopPasteController()
            .writeClipboardTextExcludingHistory('secret');

        expect(ok, isTrue);
        expect(calls.single.method, 'writeClipboardText');
        expect((calls.single.arguments as Map)['text'], 'secret');
      },
    );

    test('writeClipboardTextExcludingHistory asserts in debug when the native '
        'side has no handler (GS-106)', () async {
      // No mock handler -> MissingPluginException -> debug assert.
      await expectLater(
        MacOSDesktopPasteController().writeClipboardTextExcludingHistory('x'),
        throwsA(isA<AssertionError>()),
      );
    });

    test('writeClipboardTextWithReceipt degrades to false when the native '
        'side has no handler', () async {
      // No mock handler -> MissingPluginException.
      final ok = await WindowsDesktopPasteController()
          .writeClipboardTextWithReceipt('hello');
      expect(ok, isFalse);
    });

    test('waitForClipboardRead parses read / lost / unknown', () async {
      final controller = MacOSDesktopPasteController();

      setHandler((call) async => {'status': 'read'});
      expect(
        await controller.waitForClipboardRead(),
        ClipboardReadReceipt.read,
      );

      setHandler((call) async => {'status': 'lost'});
      expect(
        await controller.waitForClipboardRead(),
        ClipboardReadReceipt.ownershipLost,
      );

      setHandler((call) async => {'status': 'superseded'});
      expect(
        await controller.waitForClipboardRead(),
        ClipboardReadReceipt.unknown,
      );
    });

    test(
      'waitForClipboardRead maps a missing native handler to unknown',
      () async {
        expect(
          await WindowsDesktopPasteController().waitForClipboardRead(),
          ClipboardReadReceipt.unknown,
        );
      },
    );

    test('restoreClipboardTextIfOwner forwards the text and parses the '
        'outcome', () async {
      final calls = <MethodCall>[];
      final controller = WindowsDesktopPasteController();

      setHandler((call) async => {'status': 'restored'}, recordedCalls: calls);
      expect(
        await controller.restoreClipboardTextIfOwner('previous'),
        ClipboardRestoreOutcome.restored,
      );
      expect(calls.single.method, 'restoreClipboardTextIfOwner');
      expect((calls.single.arguments as Map)['text'], 'previous');

      setHandler((call) async => {'status': 'not_owner'});
      expect(
        await controller.restoreClipboardTextIfOwner('previous'),
        ClipboardRestoreOutcome.notOwner,
      );

      setHandler((call) async => {'status': 'banana'});
      expect(
        await controller.restoreClipboardTextIfOwner('previous'),
        ClipboardRestoreOutcome.failed,
      );
    });
  });

  group('ClipboardSnapshotBridge (full clipboard backup, P1.1)', () {
    test('snapshotClipboard parses status, text form and counts', () async {
      final calls = <MethodCall>[];
      setHandler(
        (call) async => {
          'status': 'saved',
          'text': 'plain form',
          'formats': 3,
          'bytes': 4096,
        },
        recordedCalls: calls,
      );

      final snapshot = await MacOSDesktopPasteController().snapshotClipboard();

      expect(calls.single.method, 'snapshotClipboard');
      expect(snapshot.status, ClipboardSnapshotStatus.saved);
      expect(snapshot.text, 'plain form');
      expect(snapshot.formats, 3);
      expect(snapshot.bytes, 4096);
    });

    test('unknown answers and a missing handler degrade to failed', () async {
      setHandler((call) async => {'status': 'banana'});
      expect(
        (await LinuxDesktopPasteController().snapshotClipboard()).status,
        ClipboardSnapshotStatus.failed,
      );
      expect(
        (await WindowsDesktopPasteController().snapshotClipboard()).status,
        ClipboardSnapshotStatus.failed,
      );
    });

    test('empty and denied are passed through', () async {
      setHandler((call) async => {'status': 'empty'});
      expect(
        (await WindowsDesktopPasteController().snapshotClipboard()).status,
        ClipboardSnapshotStatus.empty,
      );
      setHandler((call) async => {'status': 'denied'});
      expect(
        (await MacOSDesktopPasteController().snapshotClipboard()).status,
        ClipboardSnapshotStatus.denied,
      );
    });

    test('restoreClipboardSnapshotIfOwner parses the owner outcome', () async {
      final calls = <MethodCall>[];
      final controller = LinuxDesktopPasteController();
      setHandler((call) async => {'status': 'not_owner'}, recordedCalls: calls);

      expect(
        await controller.restoreClipboardSnapshotIfOwner(),
        ClipboardRestoreOutcome.notOwner,
      );
      expect(calls.single.method, 'restoreClipboardSnapshotIfOwner');
    });
  });

  // The undo gate reads these calls on the paste path. A malformed native
  // answer must degrade to "no idle source" or "no keystroke", never throw.
  group('undo gate channel calls (DEV-165, DEV-185)', () {
    test('reads the three idle ages from the snapshot map', () async {
      setHandler(
        (call) async => {'keyIdle': 1.5, 'mouseIdle': 2, 'syntheticIdle': 1e9},
      );
      final snapshot = await MacOSDesktopPasteController().inputIdleSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.keyIdle, 1.5);
      expect(snapshot.mouseIdle, 2.0);
      expect(snapshot.syntheticIdle, 1e9);
    });

    test('a snapshot that is not a map is null, not an error', () async {
      setHandler((call) async => ['not', 'a', 'map']);
      expect(await MacOSDesktopPasteController().inputIdleSnapshot(), isNull);
    });

    test('a snapshot with a missing age is null', () async {
      setHandler((call) async => {'keyIdle': 1.0, 'mouseIdle': 1.0});
      expect(await MacOSDesktopPasteController().inputIdleSnapshot(), isNull);
    });

    test('a platform error on the snapshot is null', () async {
      setHandler((call) async => throw PlatformException(code: 'boom'));
      expect(await MacOSDesktopPasteController().inputIdleSnapshot(), isNull);
    });

    test('a non-bool undo answer is false, so the copy path runs', () async {
      setHandler((call) async => 'yes');
      expect(await MacOSDesktopPasteController().sendUndoShortcut(), isFalse);
    });

    test('a platform error on the undo keystroke is false', () async {
      setHandler((call) async => throw PlatformException(code: 'boom'));
      expect(await MacOSDesktopPasteController().sendUndoShortcut(), isFalse);
    });
  });

  // A malformed native answer must stay inside the channel wrapper. The paste
  // caller catches Exception only, and a TypeError is an Error, so a wrong
  // answer type there used to escape the whole paste path.
  group('malformed paste answers (channel wrapper)', () {
    test(
      'a non-bool, non-map paste answer is postFailed, not an error',
      () async {
        setHandler((call) async => 42);
        final result = await MacOSDesktopPasteController().pasteClipboard(
          delay: Duration.zero,
        );
        expect(result.status, NativePasteStatus.postFailed);
      },
    );

    test('a non-bool typeText answer is postFailed, not an error', () async {
      setHandler((call) async => 'yes');
      final result = await MacOSDesktopPasteController().typeText(
        'x',
        delay: Duration.zero,
      );
      expect(result.status, NativePasteStatus.postFailed);
    });

    test(
      'a non-bool clipboard answer is false, so the plain write runs',
      () async {
        setHandler((call) async => ['no']);
        expect(
          await MacOSDesktopPasteController()
              .writeClipboardTextExcludingHistory('x'),
          isFalse,
        );
      },
    );
  });
}
