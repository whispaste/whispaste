/// Channel-level tests for the polled native reads of the paste controller:
/// a reply that never arrives must end in a timeout, must not stack new
/// unanswered calls, and must recover once the native side answers. The
/// native side is a handler that never completes; time is simulated.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/desktop_paste/desktop_paste_controller_interface.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.whispaste.desktop_paste');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'checkCapability: a silent native side times out and does not stack',
    () {
      fakeAsync((async) {
        var sends = 0;
        final silent = Completer<Object?>();
        messenger.setMockMethodCallHandler(channel, (call) {
          sends++;
          return silent.future;
        });
        final controller = MacOSDesktopPasteController();

        Object? firstError;
        unawaited(
          controller.checkCapability().then<void>(
            (_) {},
            onError: (Object e) => firstError = e,
          ),
        );
        async.elapse(const Duration(seconds: 6));
        expect(firstError, isA<TimeoutException>());

        // Steady polling while the read stays silent: no new native call.
        final errors = <Object>[];
        final poll = Timer.periodic(const Duration(seconds: 1), (_) {
          unawaited(
            controller.checkCapability().then<void>(
              (_) {},
              onError: (Object e) => errors.add(e),
            ),
          );
        });
        async.elapse(const Duration(minutes: 2));
        poll.cancel();
        async.flushMicrotasks();

        expect(sends, 1, reason: 'a silent read must not stack new calls');
        expect(errors, hasLength(120));
        expect(errors, everyElement(isA<TimeoutException>()));
      });
    },
  );

  test('checkCapability: sends again once the stuck read has answered', () {
    fakeAsync((async) {
      var sends = 0;
      final first = Completer<Object?>();
      messenger.setMockMethodCallHandler(channel, (call) {
        sends++;
        return sends == 1
            ? first.future
            : Future<Object?>.value({'status': 'ready'});
      });
      final controller = MacOSDesktopPasteController();

      unawaited(
        controller.checkCapability().then<void>((_) {}, onError: (_) {}),
      );
      async.elapse(const Duration(seconds: 6));

      first.complete(<String, Object?>{'status': 'permission_missing'});
      async.flushMicrotasks();

      NativeCapabilityResult? result;
      unawaited(controller.checkCapability().then((r) => result = r));
      async.flushMicrotasks();
      expect(sends, 2);
      expect(result?.status, NativeCapabilityStatus.ready);
    });
  });

  test(
    'secureInputState: a silent native side reports unsupported, no stacking',
    () {
      fakeAsync((async) {
        var sends = 0;
        messenger.setMockMethodCallHandler(channel, (call) {
          sends++;
          return Completer<Object?>().future;
        });
        final controller = MacOSDesktopPasteController();

        final states = <SecureInputState>[];
        final poll = Timer.periodic(const Duration(seconds: 2), (_) {
          unawaited(controller.secureInputState().then(states.add));
        });
        async.elapse(const Duration(minutes: 1));
        poll.cancel();
        async.flushMicrotasks();

        expect(sends, 1);
        expect(states, isNotEmpty);
        expect(states, everyElement(SecureInputState.unsupported));
      });
    },
  );

  test('a prompting checkCapability is sent even while a read is stuck', () {
    fakeAsync((async) {
      var sends = 0;
      messenger.setMockMethodCallHandler(channel, (call) {
        sends++;
        return Completer<Object?>().future;
      });
      final controller = MacOSDesktopPasteController();

      unawaited(
        controller.checkCapability().then<void>((_) {}, onError: (_) {}),
      );
      async.elapse(const Duration(seconds: 6));
      unawaited(
        controller
            .checkCapability(promptIfMissing: true)
            .then<void>((_) {}, onError: (_) {}),
      );
      async.flushMicrotasks();
      expect(sends, 2);
    });
  });

  test('cancelPendingReads releases a waiting read at once and leaves no '
      'deadline behind', () {
    fakeAsync((async) {
      messenger.setMockMethodCallHandler(
        channel,
        (call) => Completer<Object?>().future,
      );
      final controller = MacOSDesktopPasteController();

      Object? error;
      unawaited(
        controller.checkCapability().then<void>(
          (_) {},
          onError: (Object e) => error = e,
        ),
      );
      async.flushMicrotasks();
      controller.cancelPendingReads();
      async.flushMicrotasks();

      expect(error, isA<TimeoutException>());
      expect(async.pendingTimers, isEmpty);
    });
  });
}
