import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:whispaste/services/transcription/cloud_request.dart';

void main() {
  group('cloudRequestTimeout', () {
    test('an empty or tiny upload keeps the 60 s base', () {
      expect(cloudRequestTimeout(0), const Duration(seconds: 60));
      // A 10 s dictation (320 KB) adds about 5 s at the assumed uplink.
      expect(cloudRequestTimeout(320000), const Duration(seconds: 60 + 5));
    });

    test('a 10-minute OpenAI slice gets its upload time at 0.5 Mbit/s', () {
      // 19.2 MB at 62 500 bytes/s is about 307 s, plus the 60 s base.
      expect(cloudRequestTimeout(19200000), const Duration(seconds: 60 + 307));
    });

    test('a 60-minute Deepgram upload (115 MB) fits under the cap', () {
      final timeout = cloudRequestTimeout(115200000);

      expect(timeout, const Duration(seconds: 60 + 1843));
      expect(timeout, lessThan(kCloudRequestMaxTimeout));
    });

    test('is capped at 40 minutes for very large bodies', () {
      expect(
        cloudRequestTimeout(10 * 1000 * 1000 * 1000),
        kCloudRequestMaxTimeout,
      );
      expect(kCloudRequestMaxTimeout, const Duration(minutes: 40));
    });

    test('grows monotonically with the body size', () {
      var previous = cloudRequestTimeout(0);
      for (final size in [1000000, 5000000, 19200000, 115200000]) {
        final current = cloudRequestTimeout(size);
        expect(current, greaterThan(previous));
        previous = current;
      }
    });
  });

  group('sendCloudSttRequest', () {
    test('a body that stalls after the headers ends at the timeout', () async {
      // The server sends its headers and then no body. The timeout must cover
      // reading the body too, not only the wait for the headers.
      final outcome =
          await sendCloudSttRequest(
                http.Request('POST', Uri.parse('http://localhost:1234/v1/x')),
                timeout: const Duration(milliseconds: 100),
                client: _StalledBodyClient(),
              )
              .then<Object>((_) => 'completed', onError: (Object e) => e)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => 'still waiting for the body',
              );

      expect(outcome, isA<TimeoutException>());
    });
  });
}

/// Answers 200 at once, then never delivers or ends the body.
class _StalledBodyClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(Stream<List<int>>.multi((_) {}), 200);
}
