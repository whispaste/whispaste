/// Delivery tests for automation hooks (ticket / 8.3) against a real
/// loopback HTTP server. Covers the payload, the event filter, the
/// send-time loopback re-check (including a DNS answer that moved to a
/// public address), no redirects, a timeout, at most one retry, and the
/// in-flight guard.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/automation_hooks.dart';
import 'package:whispaste/services/automation_api/automation_hook_dispatcher.dart';

class _Received {
  _Received(this.path, this.body, this.headers);
  final String path;
  final String body;
  final HttpHeaders headers;
}

/// Loopback server whose responses are scripted per request.
class _HookServer {
  _HookServer._(this._server);

  final HttpServer _server;
  final List<_Received> received = [];

  /// Called with the 0-based request index; returns the status to send, or
  /// `null` to hold the connection open (for the timeout test).
  int? Function(int index) respondWith = (_) => 200;

  static Future<_HookServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hook = _HookServer._(server);
    server.listen(hook._handle);
    return hook;
  }

  int get port => _server.port;

  Future<void> _handle(HttpRequest request) async {
    final index = received.length;
    final body = await utf8.decodeStream(request);
    received.add(_Received(request.uri.path, body, request.headers));
    final status = respondWith(index);
    if (status == null) return;
    if (status >= 300 && status < 400) {
      request.response.headers.set('location', 'http://127.0.0.1:$port/moved');
    }
    request.response.statusCode = status;
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

/// A connection that never completes, controlled solely by fake_async's clock.
class _HangingClient implements HttpClient {
  int attempts = 0;
  int closes = 0;

  @override
  Duration? connectionTimeout;

  @override
  Duration idleTimeout = Duration.zero;

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    attempts++;
    return Completer<HttpClientRequest>().future;
  }

  @override
  void close({bool force = false}) => closes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // test/flutter_test_config.dart installs the widget-test binding for every
  // file, which fakes all dart:io HTTP with a synthetic 400. These tests talk
  // to the real loopback server, so they need the real HttpClient.
  setUpAll(() => HttpOverrides.global = null);

  late _HookServer server;
  final failures = <String>[];

  setUp(() async {
    server = await _HookServer.start();
    failures.clear();
  });

  tearDown(() async {
    await server.close();
  });

  AutomationHookDispatcher dispatcher(
    List<AutomationHook> hooks, {
    Duration timeout = const Duration(seconds: 2),
    Future<List<InternetAddress>> Function(String)? lookup,
    HttpClient Function()? clientFactory,
  }) => AutomationHookDispatcher(
    hooks: () => hooks,
    timeout: timeout,
    retryBackoff: Duration.zero,
    lookup: lookup ?? (h) async => [InternetAddress.loopbackIPv4],
    clientFactory: clientFactory,
    onFailure: failures.add,
  );

  AutomationHook hookAt(String path, {String host = '127.0.0.1'}) =>
      AutomationHook(
        url: 'http://$host:${server.port}$path',
        events: const {'transcript.finished'},
      );

  test('posts the versioned payload to a matching loopback hook', () async {
    await dispatcher([
      hookAt('/hook'),
    ]).dispatch(event: 'transcript.finished', data: {'transcript': 'hallo'});

    expect(server.received, hasLength(1));
    final sent = server.received.single;
    expect(sent.path, '/hook');
    expect(sent.headers.contentType?.mimeType, 'application/json');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['schema'], 'whispaste.automation-event');
    expect(body['version'], 1);
    expect(body['event'], 'transcript.finished');
    expect(body['data'], {'transcript': 'hallo'});
    expect(failures, isEmpty);
  });

  test('a hook is not called for an event it did not subscribe to', () async {
    await dispatcher([
      hookAt('/hook'),
    ]).dispatch(event: 'note.changed', data: const {});
    expect(server.received, isEmpty);
  });

  test(
    'a hook that is not loopback at send time is never connected to',
    () async {
      var clientCreated = false;
      const remote = AutomationHook(
        url: 'http://8.8.8.8/hook',
        events: {'transcript.finished'},
      );
      await dispatcher(
        [remote],
        clientFactory: () {
          clientCreated = true;
          return HttpClient();
        },
      ).dispatch(event: 'transcript.finished', data: const {});

      expect(clientCreated, isFalse);
      expect(failures.single, contains('not loopback'));
    },
  );

  test(
    'localhost whose DNS answer moved to a public address is refused',
    () async {
      var lookups = 0;
      await dispatcher(
        [hookAt('/hook', host: 'localhost')],
        lookup: (host) async {
          lookups++;
          return [InternetAddress('93.184.216.34')];
        },
      ).dispatch(event: 'transcript.finished', data: const {});

      expect(lookups, 1, reason: 'resolved at send time, not cached');
      expect(server.received, isEmpty);
      expect(failures.single, contains('not loopback'));
    },
  );

  test('the DNS answer is re-checked on every send', () async {
    var answer = InternetAddress.loopbackIPv4;
    final d = dispatcher([
      hookAt('/hook', host: 'localhost'),
    ], lookup: (_) async => [answer]);
    await d.dispatch(event: 'transcript.finished', data: const {});
    answer = InternetAddress('10.0.0.7');
    await d.dispatch(event: 'transcript.finished', data: const {});

    expect(server.received, hasLength(1));
    expect(failures, hasLength(1));
  });

  test('redirects are not followed and are reported as a failure', () async {
    server.respondWith = (i) => i == 0 ? 302 : 200;
    await dispatcher([
      hookAt('/start'),
    ]).dispatch(event: 'transcript.finished', data: const {});

    expect(server.received.map((r) => r.path), ['/start']);
    expect(failures.single, contains('302'));
  });

  test(
    'a 5xx is retried exactly once, and a success on retry counts',
    () async {
      server.respondWith = (i) => i == 0 ? 500 : 200;
      await dispatcher([
        hookAt('/hook'),
      ]).dispatch(event: 'transcript.finished', data: const {});
      expect(server.received, hasLength(2));
      expect(failures, isEmpty);
    },
  );

  test(
    'two failing attempts stop there: at most one retry, one log line',
    () async {
      server.respondWith = (_) => 503;
      await dispatcher([
        hookAt('/hook'),
      ]).dispatch(event: 'transcript.finished', data: const {});
      expect(server.received, hasLength(2));
      expect(failures, hasLength(1));
      expect(failures.single, contains('503'));
      expect(
        failures.single,
        isNot(contains('/hook')),
        reason: 'the log names the host and port only, never the path',
      );
    },
  );

  test('a client error (4xx) is not retried', () async {
    server.respondWith = (_) => 404;
    await dispatcher([
      hookAt('/hook'),
    ]).dispatch(event: 'transcript.finished', data: const {});
    expect(server.received, hasLength(1));
    expect(failures.single, contains('404'));
  });

  test('a hook that never answers times out and is retried once', () {
    fakeAsync((time) {
      final client = _HangingClient();
      var completed = false;
      dispatcher([hookAt('/hang')], clientFactory: () => client)
          .dispatch(event: 'transcript.finished', data: const {})
          .then((_) => completed = true);
      time.elapse(const Duration(seconds: 2));
      expect(completed, isFalse);
      expect(client.attempts, 2);
      time.elapse(const Duration(seconds: 2));
      expect(completed, isTrue);
      expect(client.closes, 2);
      expect(failures.single, contains('timeout'));
    });
  });

  test(
    'a second event while the first delivery is still running is skipped',
    () {
      fakeAsync((time) {
        final client = _HangingClient();
        final d = dispatcher([hookAt('/hang')], clientFactory: () => client);
        var completed = false;
        d
            .dispatch(event: 'transcript.finished', data: const {})
            .then((_) => completed = true);
        time.flushMicrotasks();
        expect(client.attempts, 1);
        expect(completed, isFalse);
        d.dispatch(event: 'transcript.finished', data: const {});
        time.flushMicrotasks();
        expect(client.attempts, 1);
        expect(failures.single, contains('still running'));
        time.elapse(const Duration(seconds: 4));
        expect(completed, isTrue);
      });
    },
  );

  test('a dispatch never throws into the caller', () async {
    final broken = AutomationHookDispatcher(
      hooks: () => throw StateError('settings unavailable'),
      onFailure: failures.add,
    );
    await expectLater(
      broken.dispatch(event: 'transcript.finished', data: const {}),
      completes,
    );
  });
}
