/// Loopback-only HTTP clients (WP-43a A-M1): traffic to the automation API
/// and to hooks must go direct, never through an HTTP proxy from the
/// environment, because that would hand the bearer token and payloads to it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/automation_api/automation_api_client.dart';

void main() {
  final loopback = Uri.parse('http://127.0.0.1:8765/v1/status');

  test('the platform default would use an environment proxy', () {
    // Documents why the override is needed: the default resolves to the proxy.
    final resolved = HttpClient.findProxyFromEnvironment(
      loopback,
      environment: {'http_proxy': 'http://proxy.example:3128'},
    );
    expect(resolved, isNot('DIRECT'));
  });

  test('automation traffic resolves every target to DIRECT', () {
    expect(automationProxyDecision(loopback), 'DIRECT');
    expect(
      automationProxyDecision(Uri.parse('http://localhost:8766/')),
      'DIRECT',
    );
  });

  test('the loopback client factory returns a usable client', () {
    final client = newLoopbackHttpClient();
    addTearDown(() => client.close(force: true));
    expect(client, isA<HttpClient>());
  });
}
