import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/transcription/cloud_request.dart';
import 'package:whispaste/services/transcription/transcriber_exception.dart';

void main() {
  group('retryCloudRequest', () {
    test('retries a rate limit and a server error, then returns', () async {
      final outcomes = <Object>[
        const TranscriberException(
          'busy',
          reason: TranscriberFailureReason.rateLimited,
        ),
        const TranscriberException(
          'down',
          reason: TranscriberFailureReason.serverError,
        ),
        'ok',
      ];
      final waits = <Duration>[];
      var attempts = 0;

      final result = await retryCloudRequest<String>(() async {
        attempts++;
        final next = outcomes.removeAt(0);
        if (next is TranscriberException) throw next;
        return next as String;
      }, wait: (d) async => waits.add(d));

      expect(result, 'ok');
      expect(attempts, 3);
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 4)]);
    });

    test(
      'gives up after three attempts and rethrows the last failure',
      () async {
        var attempts = 0;
        await expectLater(
          retryCloudRequest<String>(() async {
            attempts++;
            throw const TranscriberException(
              'timeout',
              reason: TranscriberFailureReason.timeout,
            );
          }, wait: (_) async {}),
          throwsA(
            isA<TranscriberException>().having(
              (e) => e.reason,
              'reason',
              TranscriberFailureReason.timeout,
            ),
          ),
        );
        expect(attempts, kCloudMaxAttempts);
      },
    );

    test('uses the Retry-After wait the server asked for, capped', () async {
      final waits = <Duration>[];
      var attempts = 0;
      await retryCloudRequest<String>(() async {
        attempts++;
        if (attempts == 1) {
          throw const TranscriberException(
            'busy',
            reason: TranscriberFailureReason.rateLimited,
            retryAfter: Duration(seconds: 7),
          );
        }
        if (attempts == 2) {
          throw const TranscriberException(
            'busy',
            reason: TranscriberFailureReason.rateLimited,
            retryAfter: Duration(seconds: 90),
          );
        }
        return 'ok';
      }, wait: (d) async => waits.add(d));

      expect(waits, [const Duration(seconds: 7), kCloudRetryMaxDelay]);
    });

    test('does not retry quota, auth or unknown failures', () async {
      for (final reason in [
        TranscriberFailureReason.quotaExceeded,
        TranscriberFailureReason.authError,
        TranscriberFailureReason.unknown,
      ]) {
        var attempts = 0;
        await expectLater(
          retryCloudRequest<String>(() async {
            attempts++;
            throw TranscriberException('x', reason: reason);
          }, wait: (_) async {}),
          throwsA(isA<TranscriberException>()),
        );
        expect(attempts, 1, reason: reason.name);
      }
    });

    test('sends no attempt once the user has cancelled', () async {
      var attempts = 0;
      await expectLater(
        retryCloudRequest<String>(
          () async {
            attempts++;
            return 'never';
          },
          isCancelled: () => true,
          wait: (_) async {},
        ),
        throwsA(
          isA<TranscriberException>().having(
            (e) => e.reason,
            'reason',
            TranscriberFailureReason.cancelled,
          ),
        ),
      );
      expect(attempts, 0);
    });
  });
}
