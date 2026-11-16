/// Contract test for `POST /v1/contact` as the app sends it (#998): field
/// names and values the API validates, and how each answer of the API maps
/// onto a [FeedbackSubmissionResult]. All HTTP goes through [MockClient].
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:whispaste/services/feedback_submission_service.dart';

const _base = 'https://api.example.test';
final _install = 'a' * 64;

ContactPayload _payload({
  String kind = 'problem',
  String message = 'The hotkey stops working after sleep.',
  String lang = 'de',
  String email = '',
  int? rating,
  String? appVersion,
  String? os,
  bool publishConsent = false,
  String? withdrawTokenHash,
}) => ContactPayload(
  kind: kind,
  message: message,
  lang: lang,
  elapsedMs: 12000,
  installHash: _install,
  email: email,
  rating: rating,
  appVersion: appVersion,
  os: os,
  publishConsent: publishConsent,
  withdrawTokenHash: withdrawTokenHash,
);

typedef _Captured = ({String message, Map<String, Object?> extras});

FeedbackSubmissionService _service(
  http.Client client, {
  List<_Captured>? messages,
  String baseUrl = _base,
}) => FeedbackSubmissionService(
  client: client,
  baseUrl: baseUrl,
  timeout: const Duration(seconds: 5),
  breadcrumbSink: (_) {},
  messageSink: (message, level, extras) =>
      messages?.add((message: message, extras: extras)),
);

void main() {
  group('request', () {
    test('posts JSON to /v1/contact with the fields the API expects', () async {
      late http.Request sent;
      final service = _service(
        MockClient((request) async {
          sent = request;
          return http.Response('', 202);
        }),
      );

      await service.submitContact(
        _payload(
          email: 'me@example.org',
          rating: 4,
          appVersion: '1.2.3',
          os: 'linux',
        ),
      );

      expect(sent.method, 'POST');
      expect(sent.url.toString(), '$_base/v1/contact');
      expect(sent.headers['Content-Type'], startsWith('application/json'));
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body, {
        'source': 'app',
        'kind': 'problem',
        'message': 'The hotkey stops working after sleep.',
        'email': 'me@example.org',
        'lang': 'de',
        'website': '',
        'elapsed': 12000,
        'install': _install,
        'rating': 4,
        'appVersion': '1.2.3',
        'os': 'linux',
      });
    });

    test('without diagnostics no version or system leaves the app', () {
      final body = _payload().toJson();
      expect(body.containsKey('appVersion'), isFalse);
      expect(body.containsKey('os'), isFalse);
      expect(body['email'], '');
      expect(body['rating'], isNull);
    });

    test('an unsupported language falls back to en', () {
      expect(_payload(lang: 'ja').toJson()['lang'], 'en');
      for (final lang in kContactLangs) {
        expect(_payload(lang: lang).toJson()['lang'], lang);
      }
    });

    test('every form category is a kind the API accepts', () {
      expect(kContactKinds, {'problem', 'idea', 'question', 'other', 'praise'});
    });

    test('quote consent only travels with praise and a token hash', () {
      final hash = 'b' * 64;
      final praise = _payload(
        kind: 'praise',
        publishConsent: true,
        withdrawTokenHash: hash,
      ).toJson();
      expect(praise['publish_consent'], isTrue);
      expect(praise['consent_text_version'], kFeedbackConsentTextVersion);
      expect(praise['withdraw_token_hash'], hash);

      final idea = _payload(
        kind: 'idea',
        publishConsent: true,
        withdrawTokenHash: hash,
      ).toJson();
      expect(idea.containsKey('publish_consent'), isFalse);
      expect(idea.containsKey('withdraw_token_hash'), isFalse);
    });

    test('contactOsName maps the platform onto the API values', () {
      expect(contactOsName('macos'), 'macos');
      expect(contactOsName('windows'), 'windows');
      expect(contactOsName('linux'), 'linux');
      expect(contactOsName('fuchsia'), isNull);
    });
  });

  group('answers', () {
    Future<FeedbackSubmissionResult> answer(
      int status, {
      String body = '',
      List<_Captured>? messages,
    }) => _service(
      MockClient((_) async => http.Response(body, status)),
      messages: messages,
    ).submitContact(_payload());

    test('202 is sent', () async {
      expect(await answer(202), isA<FeedbackSent>());
    });

    test('429 is the server rate limit', () async {
      expect(await answer(429), isA<FeedbackRateLimitedServer>());
    });

    test('422 keeps the field of the Problem Details, not the text', () async {
      final messages = <_Captured>[];
      final result = await answer(
        422,
        body: jsonEncode({
          'title': 'Invalid field',
          'status': 422,
          'field': 'message',
          'message': 'secret user text',
        }),
        messages: messages,
      );
      expect(result, isA<FeedbackServerError>());
      final error = result as FeedbackServerError;
      expect(error.statusCode, 422);
      expect(error.body, contains('"field":"message"'));
      expect(error.body, isNot(contains('secret user text')));
      // A client error is not a broken backend: no Sentry event.
      expect(messages, isEmpty);
    });

    for (final status in [403, 413]) {
      test('$status is an error the user can retry from the draft', () async {
        final result = await answer(status);
        expect(result, isA<FeedbackServerError>());
        expect((result as FeedbackServerError).statusCode, status);
      });
    }

    for (final status in [502, 503]) {
      test('$status is an error and reported to Sentry', () async {
        final messages = <_Captured>[];
        final result = await answer(status, messages: messages);
        expect(result, isA<FeedbackServerError>());
        expect(messages.single.message, 'contact_server_error');
        expect(messages.single.extras['status_code'], status);
      });
    }

    test('a network failure is a NetworkError', () async {
      final result = await _service(
        MockClient((_) => throw const SocketException('offline')),
      ).submitContact(_payload());
      expect(result, isA<FeedbackNetworkError>());
    });

    test('without an API URL nothing is sent', () async {
      var calls = 0;
      final result = await _service(
        MockClient((_) async {
          calls++;
          return http.Response('', 202);
        }),
        baseUrl: '',
      ).submitContact(_payload());
      expect(result, isA<FeedbackSkippedNotConfigured>());
      expect(calls, 0);
    });
  });

  group('withdrawal', () {
    test('asks both endpoints with their own field name', () async {
      final requests = <http.Request>[];
      final outcome = await _service(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            '',
            request.url.path == '/v1/contact/withdraw' ? 202 : 204,
          );
        }),
      ).withdrawPublishConsent('token-1');

      expect(outcome, WithdrawalOutcome.confirmed);
      final byPath = {
        for (final r in requests)
          r.url.path: jsonDecode(r.body) as Map<String, Object?>,
      };
      expect(byPath['/v1/contact/withdraw'], {'withdraw_token': 'token-1'});
      expect(byPath['/v1/feedback/withdraw'], {'token': 'token-1'});
    });
  });

  test('breadcrumb sink is never handed the message text', () async {
    final crumbs = <Breadcrumb>[];
    await FeedbackSubmissionService(
      client: MockClient((_) async => http.Response('', 202)),
      baseUrl: _base,
      breadcrumbSink: crumbs.add,
      messageSink: (_, _, _) {},
    ).submitContact(_payload());
    expect(
      crumbs.map((c) => jsonEncode(c.data)).join(),
      isNot(contains('hotkey')),
    );
  });
}
