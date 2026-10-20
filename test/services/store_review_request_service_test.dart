import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/store_review_request_service.dart';

const _channel = MethodChannel(kStoreReviewChannelName);

void _answer(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('requestNativeStoreReview outcome mapping', () {
    for (final status in ['requested', 'succeeded', 'canceled']) {
      test('"$status" counts as a request made', () async {
        _answer((_) async => status);
        expect(await requestNativeStoreReview(), NativeReviewOutcome.requested);
      });
    }

    test('"unavailable" leaves the prompt due', () async {
      _answer((_) async => 'unavailable');
      expect(await requestNativeStoreReview(), NativeReviewOutcome.unavailable);
    });

    for (final status in ['networkError', 'serverError']) {
      test('"$status" is a failed request', () async {
        _answer((_) async => status);
        expect(await requestNativeStoreReview(), NativeReviewOutcome.failed);
      });
    }

    test('an unknown or null answer is a failed request', () async {
      _answer((_) async => null);
      expect(await requestNativeStoreReview(), NativeReviewOutcome.failed);
    });
  });

  group('requestNativeStoreReview channel errors', () {
    test(
      'a missing channel (non-store build) is unavailable, not thrown',
      () async {
        // No mock handler registered: the platform side does not exist.
        expect(
          await requestNativeStoreReview(),
          NativeReviewOutcome.unavailable,
        );
      },
    );

    test('a PlatformException from the runner is a failed request', () async {
      _answer(
        (_) async =>
            throw PlatformException(code: 'store_error', message: 'boom'),
      );
      expect(await requestNativeStoreReview(), NativeReviewOutcome.failed);
    });
  });
}
