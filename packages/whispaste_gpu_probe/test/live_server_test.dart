/// Tests for [LiveProbeServer] — token guard, progress→report state machine,
/// SSE snapshot, the live-transcription endpoint and clean shutdown.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

/// Candidate whose run blocks on [gate] so the test can observe the
/// "running" (progress shell) phase before releasing it.
class _GateCandidate implements ProbeCandidate {
  _GateCandidate(this.id, this.gate);

  @override
  final String id;
  final Completer<void> gate;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    await gate.future;
    return CandidateResult(
      candidateId: id,
      outcome: Outcome.ok,
      durationMs: 123,
      transcribedText: 'hallo welt',
    );
  }
}

Future<String> _getBody(HttpClient client, Uri url) async {
  final res = await (await client.getUrl(url)).close();
  return res.transform(utf8.decoder).join();
}

Future<void> _waitUntil(bool Function() cond) async {
  for (var i = 0; i < 400; i++) {
    if (cond()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition not met within timeout');
}

void main() {
  group('generateSessionToken', () {
    test('is 32 lowercase hex chars', () {
      final t = generateSessionToken(Random(1));
      expect(t, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('is deterministic for a seeded Random', () {
      expect(
        generateSessionToken(Random(42)),
        generateSessionToken(Random(42)),
      );
    });
  });

  group('LiveProbeServer state (no HTTP)', () {
    test('indexHtml is the progress shell before the probe finishes', () {
      final server = LiveProbeServer(
        candidates: [_GateCandidate('whisper-cpp-cpu', Completer<void>())],
        contextTemplate: const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        ),
        version: '9.9-test',
        random: Random(3),
      );
      final html = server.indexHtml();
      expect(html, contains('Analyse läuft'));
      expect(html, contains('whisper-cpp-cpu'));
      expect(server.isFinished, isFalse);
    });

    test('snapshot lists every candidate as pending initially', () {
      final server = LiveProbeServer(
        candidates: [
          _GateCandidate('a', Completer<void>()),
          _GateCandidate('b', Completer<void>()),
        ],
        contextTemplate: const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        ),
        version: 't',
        random: Random(3),
      );
      final snap = server.snapshot();
      expect(snap['finished'], isFalse);
      final states = snap['states'] as List;
      expect(states.length, 2);
      expect((states.first as Map)['state'], 'pending');
    });

    test('candidateById finds known and rejects unknown ids', () {
      final server = LiveProbeServer(
        candidates: [_GateCandidate('known', Completer<void>())],
        contextTemplate: const ProbeContext(
          referenceWavPath: '',
          modelPath: '',
          workDir: '',
        ),
        version: 't',
        random: Random(3),
      );
      expect(server.candidateById('known'), isNotNull);
      expect(server.candidateById('nope'), isNull);
      expect(server.candidateById(null), isNull);
    });
  });

  group('LiveProbeServer over HTTP', () {
    late LiveProbeServer server;
    late Completer<void> gate;
    late Uri url;
    late HttpClient client;
    ProbeReport? completedReport;

    setUp(() async {
      gate = Completer<void>();
      completedReport = null;
      server = LiveProbeServer(
        candidates: [_GateCandidate('whisper-cpp-cpu', gate)],
        contextTemplate: const ProbeContext(
          referenceWavPath: '',
          modelPath: '/models/ggml-small.bin',
          workDir: '',
        ),
        version: '9.9-test',
        random: Random(7),
        logger: (_) {},
        onComplete: (r) async => completedReport = r,
      );
      url = await server.start();
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    test('opened URL carries the session token', () {
      expect(url.queryParameters['t'], server.token);
      expect(url.host, '127.0.0.1');
    });

    test('rejects requests without the token (403)', () async {
      final noToken = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: url.port,
        path: '/',
      );
      final res = await (await client.getUrl(noToken)).close();
      expect(res.statusCode, HttpStatus.forbidden);
      await res.drain<void>();
    });

    test('serves the progress shell while the probe runs', () async {
      final html = await _getBody(client, url);
      expect(html, contains('Analyse läuft'));
      expect(server.isFinished, isFalse);
    });

    test(
      'serves the live report once finished, then writes artifacts',
      () async {
        gate.complete();
        await _waitUntil(() => server.isFinished);
        final html = await _getBody(client, url);
        expect(html, contains('Geschwindigkeits-Ranking'));
        expect(html, contains('LIVE'));
        expect(html, contains('live-btn'));
        // onComplete fired with the finished report.
        await _waitUntil(() => completedReport != null);
        expect(completedReport!.results.single.candidateId, 'whisper-cpp-cpu');
      },
    );

    test(
      'transcribe endpoint runs the candidate on the uploaded audio',
      () async {
        gate.complete();
        await _waitUntil(() => server.isFinished);
        final tUrl = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: url.port,
          path: '/api/transcribe',
          queryParameters: {'candidate': 'whisper-cpp-cpu', 't': server.token},
        );
        final req = await client.postUrl(tUrl);
        req.add(const [82, 73, 70, 70]); // fake "RIFF" header bytes
        final res = await req.close();
        final body = await res.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, Object?>;
        expect(json['outcome'], 'ok');
        expect(json['transcribedText'], 'hallo welt');
        expect(json['durationMs'], 123);
      },
    );

    test('transcribe with unknown candidate returns 404', () async {
      gate.complete();
      await _waitUntil(() => server.isFinished);
      final tUrl = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: url.port,
        path: '/api/transcribe',
        queryParameters: {'candidate': 'ghost', 't': server.token},
      );
      final res = await (await client.postUrl(tUrl)).close();
      expect(res.statusCode, HttpStatus.notFound);
      await res.drain<void>();
    });

    test('shutdown endpoint completes awaitShutdown', () async {
      final sUrl = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: url.port,
        path: '/api/shutdown',
        queryParameters: {'t': server.token},
      );
      final res = await (await client.postUrl(sUrl)).close();
      expect(res.statusCode, HttpStatus.ok);
      await res.drain<void>();
      await server.awaitShutdown(); // resolves once the server stops
    });
  });
}
