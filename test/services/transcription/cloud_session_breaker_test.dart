import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/transcription/cloud_request.dart';
import 'package:whispaste/services/transcription/cloud_session_breaker.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

typedef _Reason = TranscriberFailureReason;

void main() {
  late DateTime now;
  late CloudSessionBreaker breaker;
  const t = 'openai|u|k';

  setUp(() {
    now = DateTime(2026, 1, 1);
    breaker = CloudSessionBreaker(now: () => now);
  });

  void fail(String target, [_Reason r = _Reason.serverError]) {
    breaker.acquire(target);
    breaker.onFailure(target, r);
  }

  void open() {
    for (var i = 0; i < kCloudBreakerThreshold; i++) {
      fail(t);
    }
  }

  test('opens after three outage failures in a row, then fails at once', () {
    fail(t, _Reason.networkError);
    fail(t, _Reason.timeout);
    breaker.acquire(t);
    breaker.onFailure(t, _Reason.rateLimited);
    expect(() => breaker.acquire(t), throwsA(isA<TranscriberException>()));
  });

  test('a success in between resets the count', () {
    fail(t);
    fail(t);
    breaker.onSuccess(t);
    fail(t);
    fail(t);
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('auth, quota, rejected and bad format never open it', () {
    for (final r in [
      _Reason.authError,
      _Reason.quotaExceeded,
      _Reason.unknown,
      _Reason.badResponse,
      _Reason.modelMissing,
    ]) {
      for (var i = 0; i < 10; i++) {
        fail(t, r);
      }
    }
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('a non-outage answer resets earlier outage failures', () {
    fail(t);
    fail(t);
    fail(t, _Reason.authError);
    fail(t);
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('blocked request reports the last reason and the remaining pause', () {
    open();
    now = now.add(const Duration(seconds: 20));
    try {
      breaker.acquire(t);
      fail('should throw');
    } on TranscriberException catch (e) {
      expect(e.reason, _Reason.serverError);
      expect(e.retryAfter, const Duration(seconds: 40));
    }
  });

  test('after one minute exactly one probe goes out', () {
    open();
    now = now.add(const Duration(seconds: 59));
    expect(() => breaker.acquire(t), throwsA(isA<TranscriberException>()));
    now = now.add(const Duration(seconds: 1));
    expect(() => breaker.acquire(t), returnsNormally);
    expect(() => breaker.acquire(t), throwsA(isA<TranscriberException>()));
  });

  test('probe success closes the breaker', () {
    open();
    now = now.add(kCloudBreakerBasePause);
    breaker.acquire(t);
    breaker.onSuccess(t);
    expect(() => breaker.acquire(t), returnsNormally);
    fail(t);
    fail(t);
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('probe failure doubles the pause up to ten minutes', () {
    open();
    var pause = kCloudBreakerBasePause;
    for (var i = 0; i < 6; i++) {
      now = now.add(pause);
      breaker.acquire(t);
      breaker.onFailure(t, _Reason.timeout);
      pause = pause * 2 > kCloudBreakerMaxPause
          ? kCloudBreakerMaxPause
          : pause * 2;
      now = now.add(pause - const Duration(seconds: 1));
      expect(() => breaker.acquire(t), throwsA(isA<TranscriberException>()));
      now = now.add(const Duration(seconds: 1));
      // Hand the probe slot back for the next loop round's own acquire.
      breaker.onAborted(t);
    }
    expect(pause, kCloudBreakerMaxPause);
  });

  test('probe with a non-outage answer closes the breaker', () {
    open();
    now = now.add(kCloudBreakerBasePause);
    breaker.acquire(t);
    breaker.onFailure(t, _Reason.authError);
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('an aborted probe frees the slot without a verdict', () {
    open();
    now = now.add(kCloudBreakerBasePause);
    breaker.acquire(t);
    breaker.onAborted(t);
    expect(() => breaker.acquire(t), returnsNormally);
  });

  test('targets are independent; key and provider change the target', () {
    final a = cloudBreakerTarget(provider: 'openai', address: 'u', key: 'k1');
    final b = cloudBreakerTarget(provider: 'openai', address: 'u', key: 'k2');
    final c = cloudBreakerTarget(provider: 'custom', address: 'u', key: 'k1');
    expect({a, b, c}, hasLength(3));
    expect(a, isNot(contains('k1')));
    open();
    expect(() => breaker.acquire(a), returnsNormally);
  });

  group('retryCloudRequest with breaker', () {
    Future<void> send(String target, Object Function() outcome) async {
      await retryCloudRequest<void>(
        () async {
          final o = outcome();
          if (o is Exception) throw o;
        },
        breaker: breaker,
        breakerTarget: target,
        wait: (_) async {},
      );
    }

    const down = TranscriberException('down', reason: _Reason.serverError);

    test(
      'one failed dictation opens it; the next fails without attempts',
      () async {
        var attempts = 0;
        await expectLater(
          send(t, () {
            attempts++;
            return down;
          }),
          throwsA(isA<TranscriberException>()),
        );
        expect(attempts, kCloudMaxAttempts);
        await expectLater(
          send(t, () {
            attempts++;
            return down;
          }),
          throwsA(isA<TranscriberException>()),
        );
        expect(attempts, kCloudMaxAttempts);
      },
    );

    test('probe after the pause reaches the service and closes it', () async {
      for (var i = 0; i < 3; i++) {
        await send(t, () => down).catchError((_) {});
      }
      now = now.add(kCloudBreakerBasePause);
      var attempts = 0;
      await send(t, () {
        attempts++;
        return 'ok';
      });
      expect(attempts, 1);
      await send(t, () => 'ok');
    });

    test('a failing probe makes only one attempt', () async {
      for (var i = 0; i < 3; i++) {
        await send(t, () => down).catchError((_) {});
      }
      now = now.add(kCloudBreakerBasePause);
      var attempts = 0;
      await send(t, () {
        attempts++;
        return down;
      }).catchError((_) {});
      expect(attempts, 1);
    });

    test('a cancelled probe does not count', () async {
      for (var i = 0; i < 3; i++) {
        await send(t, () => down).catchError((_) {});
      }
      now = now.add(kCloudBreakerBasePause);
      await send(
        t,
        () => const TranscriberException('c', reason: _Reason.cancelled),
      ).catchError((_) {});
      var attempts = 0;
      await send(t, () {
        attempts++;
        return 'ok';
      });
      expect(attempts, 1);
    });
  });
}
