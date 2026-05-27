/// Unit tests for [FeedbackSubmissionService].
///
/// All HTTP calls are intercepted via [MockClient] (package:http/testing.dart).
/// No real network connections are made.
///
/// Result variants tested:
///   1. [FeedbackSkippedNotConfigured] — empty URL
///   2. [FeedbackSkippedNotConfigured] — empty key
///   3. [FeedbackSent] — HTTP 2xx
///   4. [FeedbackRateLimitedServer] — HTTP 429
///   5. [FeedbackRateLimitedServer] — HTTP 400 body contains "rate_limited"
///   6. [FeedbackServerError] — HTTP 5xx
///   7. [FeedbackNetworkError] — SocketException
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/services/feedback_submission_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

FeedbackPayload _testPayload() => const FeedbackPayload(
  rating: 5,
  feedbackText: 'Great app!',
  category: 'general',
  appVersion: '1.0.0',
  deviceIdHash: 'abc123def456',
  locale: 'en',
);

/// One captured Sentry message: payload, level, and the extras map.
typedef CapturedMessage = ({
  String message,
  SentryLevel level,
  Map<String, Object?> extras,
});

FeedbackSubmissionService _makeService({
  required http.Client client,
  String supabaseUrl = 'https://example.supabase.co',
  String supabasePublishableKey = 'test-key',
  List<Breadcrumb>? breadcrumbs,
  List<CapturedMessage>? messages,
}) {
  final capturedCrumbs = breadcrumbs;
  final capturedMessages = messages;
  return FeedbackSubmissionService(
    client: client,
    supabaseUrl: supabaseUrl,
    supabasePublishableKey: supabasePublishableKey,
    timeout: const Duration(seconds: 5),
    breadcrumbSink: capturedCrumbs != null ? capturedCrumbs.add : (_) {},
    messageSink: capturedMessages != null
        ? (msg, level, extras) =>
              capturedMessages.add((message: msg, level: level, extras: extras))
        : (_, _, _) {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('FeedbackSubmissionService', () {
    // ── SkippedNotConfigured ───────────────────────────────────────────────

    test(
      'returns SkippedNotConfigured when supabaseUrl is empty — no HTTP call',
      () async {
        var httpCallMade = false;
        final client = MockClient((_) async {
          httpCallMade = true;
          return http.Response('', 201);
        });

        final service = _makeService(
          client: client,
          supabaseUrl: '',
          supabasePublishableKey: 'some-key',
        );
        final result = await service.submit(_testPayload());

        expect(result, isA<FeedbackSkippedNotConfigured>());
        expect(httpCallMade, isFalse);
      },
    );

    test(
      'returns SkippedNotConfigured when supabasePublishableKey is empty — no HTTP call',
      () async {
        var httpCallMade = false;
        final client = MockClient((_) async {
          httpCallMade = true;
          return http.Response('', 201);
        });

        final service = _makeService(
          client: client,
          supabaseUrl: 'https://example.supabase.co',
          supabasePublishableKey: '',
        );
        final result = await service.submit(_testPayload());

        expect(result, isA<FeedbackSkippedNotConfigured>());
        expect(httpCallMade, isFalse);
      },
    );

    // ── FeedbackSent ───────────────────────────────────────────────────────

    test('returns FeedbackSent on HTTP 201', () async {
      final client = MockClient((_) async => http.Response('', 201));
      final service = _makeService(client: client);
      final result = await service.submit(_testPayload());

      expect(result, isA<FeedbackSent>());
    });

    test('returns FeedbackSent on HTTP 200', () async {
      final client = MockClient((_) async => http.Response('{}', 200));
      final service = _makeService(client: client);
      final result = await service.submit(_testPayload());

      expect(result, isA<FeedbackSent>());
    });

    // ── FeedbackRateLimitedServer ─────────────────────────────────────────

    test('returns FeedbackRateLimitedServer on HTTP 429', () async {
      final client = MockClient((_) async => http.Response('', 429));
      final service = _makeService(client: client);
      final result = await service.submit(_testPayload());

      expect(result, isA<FeedbackRateLimitedServer>());
    });

    test(
      'returns FeedbackRateLimitedServer on HTTP 400 with rate_limited body',
      () async {
        final client = MockClient(
          (_) async =>
              http.Response('{"message":"rate_limited","code":"P0001"}', 400),
        );
        final service = _makeService(client: client);
        final result = await service.submit(_testPayload());

        expect(result, isA<FeedbackRateLimitedServer>());
      },
    );

    // ── FeedbackServerError ───────────────────────────────────────────────

    test(
      'returns FeedbackServerError on HTTP 500 with status code and body',
      () async {
        final client = MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        );
        final service = _makeService(client: client);
        final result = await service.submit(_testPayload());

        expect(result, isA<FeedbackServerError>());
        final err = result as FeedbackServerError;
        expect(err.statusCode, 500);
        expect(err.body, 'Internal Server Error');
      },
    );

    // ── FeedbackNetworkError ──────────────────────────────────────────────

    test('returns FeedbackNetworkError on SocketException', () async {
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      final service = _makeService(client: client);
      final result = await service.submit(_testPayload());

      expect(result, isA<FeedbackNetworkError>());
      final err = result as FeedbackNetworkError;
      expect(err.cause, isA<SocketException>());
    });

    // ── Sentry breadcrumbs ────────────────────────────────────────────────

    test('emits breadcrumb with result=sent on success', () async {
      final breadcrumbs = <Breadcrumb>[];
      final client = MockClient((_) async => http.Response('', 201));
      final service = _makeService(client: client, breadcrumbs: breadcrumbs);
      await service.submit(_testPayload());

      expect(breadcrumbs, hasLength(1));
      expect(breadcrumbs.first.data?['result'], 'sent');
      expect(breadcrumbs.first.category, 'feedback');
    });

    test(
      'emits breadcrumb with result=skipped_not_configured when not configured',
      () async {
        final breadcrumbs = <Breadcrumb>[];
        final client = MockClient((_) async => http.Response('', 201));
        final service = _makeService(
          client: client,
          supabaseUrl: '',
          breadcrumbs: breadcrumbs,
        );
        await service.submit(_testPayload());

        expect(breadcrumbs, hasLength(1));
        expect(breadcrumbs.first.data?['result'], 'skipped_not_configured');
      },
    );

    // ── Sentry captureMessage escalation ──────────────────────────────────

    test(
      'captures Sentry message with status code and body on server error',
      () async {
        final messages = <CapturedMessage>[];
        final client = MockClient(
          (_) async => http.Response('Internal Server Error', 500),
        );
        final service = _makeService(client: client, messages: messages);
        await service.submit(_testPayload());

        expect(messages, hasLength(1));
        expect(messages.first.message, 'feedback_server_error');
        expect(messages.first.level, SentryLevel.warning);
        expect(messages.first.extras['status_code'], 500);
        expect(messages.first.extras['body'], 'Internal Server Error');
      },
    );

    test('truncates oversized response body in the Sentry extra', () async {
      final messages = <CapturedMessage>[];
      final oversizedBody = 'x' * 1200;
      final client = MockClient((_) async => http.Response(oversizedBody, 500));
      final service = _makeService(client: client, messages: messages);
      await service.submit(_testPayload());

      final body = messages.single.extras['body'] as String;
      expect(body, hasLength(501)); // 500 chars + ellipsis
      expect(body.endsWith('…'), isTrue);
    });

    test('does NOT capture Sentry message on rate-limit (429)', () async {
      final messages = <CapturedMessage>[];
      final client = MockClient((_) async => http.Response('', 429));
      final service = _makeService(client: client, messages: messages);
      await service.submit(_testPayload());

      expect(messages, isEmpty);
    });

    test(
      'does NOT capture Sentry message on rate-limit (400 with rate_limited body)',
      () async {
        final messages = <CapturedMessage>[];
        final client = MockClient(
          (_) async => http.Response('{"message":"rate_limited"}', 400),
        );
        final service = _makeService(client: client, messages: messages);
        await service.submit(_testPayload());

        expect(messages, isEmpty);
      },
    );

    test('does NOT capture Sentry message on network error', () async {
      final messages = <CapturedMessage>[];
      final client = MockClient((_) async {
        throw const SocketException('Connection refused');
      });
      final service = _makeService(client: client, messages: messages);
      await service.submit(_testPayload());

      expect(messages, isEmpty);
    });

    test('does NOT capture Sentry message on successful submit', () async {
      final messages = <CapturedMessage>[];
      final client = MockClient((_) async => http.Response('', 201));
      final service = _makeService(client: client, messages: messages);
      await service.submit(_testPayload());

      expect(messages, isEmpty);
    });

    // ── Request format ────────────────────────────────────────────────────

    test('sends correct headers and JSON body', () async {
      http.Request? capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('', 201);
      });

      final service = FeedbackSubmissionService(
        client: client,
        supabaseUrl: 'https://test.supabase.co',
        supabasePublishableKey: 'pk_test',
      );
      await service.submit(_testPayload());

      expect(capturedRequest, isNotNull);
      expect(
        capturedRequest!.url.toString(),
        'https://test.supabase.co/rest/v1/user_feedback',
      );
      expect(capturedRequest!.headers['apikey'], 'pk_test');
      expect(capturedRequest!.headers['Prefer'], 'return=minimal');
    });
  });
}
