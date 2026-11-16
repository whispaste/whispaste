/// The polled microphone status read must end in a timeout that never reads
/// as granted or denied, must not send another platform call while the first
/// one is still unanswered, and must stop the overview's endless "pending"
/// once the check keeps failing (#326). Simulated time only.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/permissions/mic_permission_notifier.dart';
import 'package:whispaste/services/permissions/permissions_overview_provider.dart';

class _SilentMicChecker implements MicPermissionChecker {
  int calls = 0;

  @override
  Future<bool> check({required bool request}) {
    calls++;
    return Completer<bool>().future;
  }
}

/// Answers with [answer], or never while it is `null`.
class _SwitchableMicChecker implements MicPermissionChecker {
  bool? answer;
  int calls = 0;
  final pending = <Completer<bool>>[];

  @override
  Future<bool> check({required bool request}) {
    calls++;
    final value = answer;
    if (value != null) return Future.value(value);
    final completer = Completer<bool>();
    pending.add(completer);
    return completer.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unanswered status read turns an open status into unresponsive '
      'after the second timeout, and an answer clears it', () {
    fakeAsync((async) {
      final checker = _SwitchableMicChecker();
      final container = ProviderContainer(
        overrides: [micPermissionCheckerProvider.overrideWithValue(checker)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(micPermissionNotifierProvider.notifier);
      MicPermissionStatus status() =>
          container.read(micPermissionNotifierProvider).status;

      // One read only, as the Settings section does: the notifier follows up
      // on its own.
      unawaited(notifier.check());
      async.elapse(const Duration(seconds: 6));
      expect(status(), MicPermissionStatus.unknown, reason: 'one slow reply');

      async.elapse(const Duration(seconds: 5));
      expect(status(), MicPermissionStatus.unresponsive);
      expect(checker.calls, 1, reason: 'the follow-up must not stack calls');
      expect(
        container.read(permissionsOverviewProvider).first,
        const PermissionOverviewEntry(
          id: PermissionOverviewId.microphone,
          status: PermissionOverviewStatus.unresponsive,
          optional: false,
        ),
      );

      checker.pending.single.complete(false);
      checker.answer = false;
      async.flushMicrotasks();
      unawaited(notifier.check());
      async.flushMicrotasks();
      expect(
        status(),
        MicPermissionStatus.unknown,
        reason: 'an answered false is not a denial',
      );
    });
  });

  test('timeouts never overwrite a known grant', () {
    fakeAsync((async) {
      final checker = _SwitchableMicChecker()..answer = true;
      final container = ProviderContainer(
        overrides: [micPermissionCheckerProvider.overrideWithValue(checker)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(micPermissionNotifierProvider.notifier);
      unawaited(notifier.check());
      async.flushMicrotasks();
      checker.answer = null;
      for (var i = 0; i < 3; i++) {
        unawaited(notifier.check());
        async.elapse(const Duration(seconds: 6));
      }
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.granted,
      );
    });
  });

  test('a silent status read keeps the state and does not stack calls', () {
    fakeAsync((async) {
      final checker = _SilentMicChecker();
      final container = ProviderContainer(
        overrides: [micPermissionCheckerProvider.overrideWithValue(checker)],
      );
      addTearDown(container.dispose);
      final notifier = container.read(micPermissionNotifierProvider.notifier);
      final before = container.read(micPermissionNotifierProvider).status;

      final results = <bool>[];
      final poll = Timer.periodic(const Duration(seconds: 1), (_) {
        unawaited(notifier.check().then(results.add));
      });
      async.elapse(const Duration(minutes: 1));
      poll.cancel();
      async.flushMicrotasks();

      expect(checker.calls, 1, reason: 'a silent read must not stack calls');
      expect(results, isNotEmpty);
      expect(results, everyElement(isFalse));
      expect(before, MicPermissionStatus.unknown);
      expect(
        container.read(micPermissionNotifierProvider).status,
        MicPermissionStatus.unresponsive,
        reason: 'a timeout is never read as denied or granted',
      );
    });
  });
}
