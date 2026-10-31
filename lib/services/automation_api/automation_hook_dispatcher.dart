/// Delivers automation events to user-configured loopback hooks (ticket / 8.3).
///
/// Each delivery:
/// - re-checks the target at send time and connects to the pinned loopback
///   address (see [pinLoopbackHookTarget]);
/// - never follows redirects (a 3xx is a failure, not a new target);
/// - is bounded by [timeout] for connect, response and body drain;
/// - is retried at most once, after [retryBackoff], and only for timeouts,
///   network errors and 5xx answers;
/// - leaves exactly one failure line per hook when it gives up. The line
///   names the scheme, host and port, never the path, query or payload.
///
/// A second event for the same hook and event name is skipped while the
/// first one is still in flight, so a slow hook cannot pile up connections.
///
/// Pure Dart with an injected logger, so it can be used from the app and
/// from plain-Dart tools.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/config/automation_hooks.dart';
import 'automation_api_client.dart';

/// Resolves a host name to its addresses. Injected in tests and by the app.
typedef AutomationHostLookup =
    Future<List<InternetAddress>> Function(String host);

class AutomationHookDispatcher {
  AutomationHookDispatcher({
    required this.hooks,
    this.timeout = const Duration(seconds: 3),
    this.retryBackoff = const Duration(milliseconds: 500),
    AutomationHostLookup? lookup,
    HttpClient Function()? clientFactory,
    this.onFailure,
    DateTime Function()? now,
  }) : _lookup = lookup ?? InternetAddress.lookup,
       _clientFactory = clientFactory ?? newLoopbackHttpClient,
       _now = now ?? DateTime.now;

  /// Current hook list. Read at every dispatch, so settings edits apply
  /// to the next event.
  final List<AutomationHook> Function() hooks;
  final Duration timeout;
  final Duration retryBackoff;
  final AutomationHostLookup _lookup;
  final HttpClient Function() _clientFactory;
  final DateTime Function() _now;

  /// Receives one line per failed or skipped delivery.
  final void Function(String message)? onFailure;

  final Set<String> _inFlight = {};

  /// Sends [event] to every hook that subscribed to it. Completes when all
  /// deliveries have finished or given up. Never throws: a failure in
  /// settings access or in a delivery is logged and swallowed, so the
  /// caller (the transcription pipeline, the notes editor) is never
  /// affected.
  Future<void> dispatch({
    required String event,
    required Map<String, Object?> data,
  }) async {
    final List<AutomationHook> targets;
    try {
      targets = hooks().where((h) => h.events.contains(event)).toList();
    } on Object catch (e) {
      _fail(
        'automation hook $event skipped: settings unavailable (${e.runtimeType})',
      );
      return;
    }
    if (targets.isEmpty) return;

    final body = jsonEncode(
      buildAutomationEventPayload(event: event, at: _now(), data: data),
    );
    await Future.wait([
      for (final hook in targets) _deliver(hook, event, body),
    ]);
  }

  Future<void> _deliver(AutomationHook hook, String event, String body) async {
    final key = '${hook.url}|$event';
    final where = _describe(hook.url);
    if (!_inFlight.add(key)) {
      _fail(
        'automation hook $event to $where skipped: previous delivery still running',
      );
      return;
    }
    try {
      for (var attempt = 1; attempt <= 2; attempt++) {
        final outcome = await _attempt(hook.url, body);
        if (outcome.delivered) return;
        if (!outcome.retryable || attempt == 2) {
          _fail('automation hook $event to $where failed: ${outcome.reason}');
          return;
        }
        await Future<void>.delayed(retryBackoff);
      }
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<_Outcome> _attempt(String rawUrl, String body) async {
    final original = Uri.tryParse(rawUrl);
    if (original == null) {
      return const _Outcome.rejected('target is not a valid URL');
    }
    Uri? pinned;
    try {
      pinned = await pinLoopbackHookTarget(original, lookup: _lookup);
    } on Object {
      pinned = null;
    }
    if (pinned == null) {
      return const _Outcome.rejected('target is not loopback at send time');
    }

    final client = _clientFactory()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final request = await client.postUrl(pinned).timeout(timeout);
      request
        ..followRedirects = false
        ..maxRedirects = 0;
      // Keep the name the user configured in the Host header, even though
      // the socket goes to the pinned address.
      request.headers
        ..contentType = ContentType.json
        ..host = original.host
        ..port = original.hasPort ? original.port : 80;
      request.add(utf8.encode(body));

      final response = await request.close().timeout(timeout);
      await response.drain<void>().timeout(timeout);
      final status = response.statusCode;
      if (status >= 200 && status < 300) return const _Outcome.delivered();
      if (status >= 300 && status < 400) {
        return _Outcome.failed(
          'redirect $status not followed',
          retryable: false,
        );
      }
      return _Outcome.failed('HTTP $status', retryable: status >= 500);
    } on TimeoutException {
      return const _Outcome.failed('timeout', retryable: true);
    } on SocketException {
      return const _Outcome.failed('network error', retryable: true);
    } on HttpException {
      return const _Outcome.failed('HTTP protocol error', retryable: true);
    } on Object catch (e) {
      return _Outcome.failed('error ${e.runtimeType}', retryable: true);
    } finally {
      client.close(force: true);
    }
  }

  void _fail(String message) => onFailure?.call(message);
}

/// `scheme://host:port` for log lines; never the path or query.
String _describe(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null) return '<invalid URL>';
  final port = uri.hasPort ? ':${uri.port}' : '';
  final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
  return '${uri.scheme}://$host$port';
}

class _Outcome {
  const _Outcome.delivered() : delivered = true, retryable = false, reason = '';
  const _Outcome.rejected(this.reason) : delivered = false, retryable = false;
  const _Outcome.failed(this.reason, {required this.retryable})
    : delivered = false;

  final bool delivered;
  final bool retryable;
  final String reason;
}
