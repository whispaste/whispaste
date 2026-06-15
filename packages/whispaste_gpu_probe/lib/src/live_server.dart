/// Local live-probe server for WhisPaste-GPU-Probe.
///
/// In serve mode the tool starts a tiny HTTP server bound to loopback
/// (`127.0.0.1`, ephemeral port) BEFORE running the probe, opens the browser
/// at its URL, and:
///   - streams per-candidate progress over Server-Sent-Events while the probe
///     runs (the page shows an "Analyse läuft…" shell), then
///   - serves the finished report (with per-candidate "Live testen" buttons),
///   - runs a real microphone recording through any chosen candidate engine on
///     `POST /api/transcribe`, returning transcription + latency, and
///   - shuts down cleanly on `POST /api/shutdown` (the report's "beenden"
///     button).
///
/// A per-session token (random, in the opened URL) guards every route so other
/// local processes cannot read the report or drive the microphone endpoint.
///
/// A `file://` HTML report can neither record audio nor launch an engine — the
/// loopback server is the only way to test the real engines with live speech.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:whispaste_diagnostics/whispaste_diagnostics.dart'
    show sanitizePaths;

import 'html_report.dart';
import 'probe_types.dart';

/// Run state of a single candidate, mirrored to the progress shell.
enum CandidateRunState { pending, running, finished }

class _CandidateState {
  _CandidateState(this.id, this.label);
  final String id;
  final String label;
  CandidateRunState state = CandidateRunState.pending;
  Outcome? outcome;
}

/// Builds a hex session token from [random] (16 bytes → 32 hex chars).
String generateSessionToken(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Owns the loopback HTTP server, the background probe run, the SSE fan-out and
/// the live-transcription endpoint.
class LiveProbeServer {
  LiveProbeServer({
    required this.candidates,
    required this.contextTemplate,
    required this.version,
    this.hardwareContext,
    this.onComplete,
    DateTime Function()? clock,
    void Function(String)? logger,
    Random? random,
  }) : _clock = clock ?? DateTime.now,
       _log = logger ?? print,
       token = generateSessionToken(random ?? Random.secure()) {
    _states = [for (final c in candidates) _CandidateState(c.id, c.id)];
  }

  /// Candidates to run, in order.
  final List<ProbeCandidate> candidates;

  /// Template context — model path, work dir, language, timeout. The live
  /// transcription endpoint clones it with the uploaded WAV as input.
  final ProbeContext contextTemplate;

  /// Tool version stamp.
  final String version;

  /// Optional hardware context for the report.
  final HardwareContext? hardwareContext;

  /// Called once with the finished report (e.g. to write the disk artifacts).
  final Future<void> Function(ProbeReport report)? onComplete;

  /// Per-session guard token, embedded in the opened URL.
  final String token;

  final DateTime Function() _clock;
  final void Function(String) _log;

  late final List<_CandidateState> _states;
  final List<CandidateResult> _results = [];
  late DateTime _startedAt;
  bool _finished = false;
  ProbeReport? _report;
  String? _reportHtml;

  final Set<HttpResponse> _sseClients = {};
  HttpServer? _server;
  Directory? _liveTmpDir;
  int _liveCounter = 0;
  final Completer<void> _shutdown = Completer<void>();

  /// True once the probe loop has finished and the report is rendered.
  bool get isFinished => _finished;

  /// The finished report, or null while the probe is still running.
  ProbeReport? get report => _report;

  /// Binds the server to [address] (default loopback) on [port] (default 0 =
  /// ephemeral), starts the background probe, and returns the URL to open —
  /// including the session token.
  Future<Uri> start({InternetAddress? address, int port = 0}) async {
    _startedAt = _clock();
    final server = await HttpServer.bind(
      address ?? InternetAddress.loopbackIPv4,
      port,
    );
    _server = server;
    server.listen(
      _handle,
      onError: (Object e) => _log('GPU-Probe-Server: Anfrage-Fehler: $e'),
    );
    unawaited(_runProbe());
    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: server.port,
      path: '/',
      queryParameters: {'t': token},
    );
  }

  /// Completes when the server has shut down (via `/api/shutdown` or [stop]).
  Future<void> awaitShutdown() => _shutdown.future;

  /// Stops the server, closes SSE clients, removes the live temp dir.
  Future<void> stop() async {
    await _closeSseClients();
    await _server?.close(force: true);
    _server = null;
    try {
      await _liveTmpDir?.delete(recursive: true);
    } on Object catch (e) {
      _log('GPU-Probe-Server: Temp-Aufräumen fehlgeschlagen: $e');
    }
    if (!_shutdown.isCompleted) _shutdown.complete();
  }

  // -------------------------------------------------------------------------
  // Background probe loop
  // -------------------------------------------------------------------------

  Future<void> _runProbe() async {
    final total = candidates.length;
    for (var i = 0; i < total; i++) {
      final candidate = candidates[i];
      _states[i].state = CandidateRunState.running;
      _log('${i + 1} von $total — ${candidate.id}');
      _broadcast({
        'type': 'start',
        'index': i,
        'total': total,
        'id': candidate.id,
      });

      final result = await candidate.run(contextTemplate);

      _results.add(result);
      _states[i]
        ..state = CandidateRunState.finished
        ..outcome = result.outcome;
      _log('${candidate.id}: ${result.outcome.name}');
      _broadcast({
        'type': 'finish',
        'index': i,
        'id': candidate.id,
        'outcome': result.outcome.name,
      });
    }

    final report = ProbeReport(
      timestamp: _startedAt,
      results: _results,
      version: version,
      hardwareContext: hardwareContext,
    );
    _report = report;
    _reportHtml = formatProbeReportHtml(report, live: true, token: token);
    _finished = true;
    _broadcast({'type': 'done'});

    if (onComplete != null) {
      try {
        await onComplete!(report);
      } on Object catch (e) {
        _log('GPU-Probe-Server: Artefakt-Schreiben fehlgeschlagen: $e');
      }
    }
  }

  // -------------------------------------------------------------------------
  // Request routing
  // -------------------------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    try {
      if (req.uri.queryParameters['t'] != token) {
        await _writeText(
          req,
          HttpStatus.forbidden,
          'Ungültiges oder fehlendes Session-Token.',
        );
        return;
      }
      final path = req.uri.path;
      if (path == '/' && req.method == 'GET') {
        await _handleIndex(req);
      } else if (path == '/events' && req.method == 'GET') {
        _handleSse(req);
      } else if (path == '/api/transcribe' && req.method == 'POST') {
        await _handleTranscribe(req);
      } else if (path == '/api/shutdown' && req.method == 'POST') {
        await _handleShutdown(req);
      } else {
        await _writeText(req, HttpStatus.notFound, 'Nicht gefunden.');
      }
    } on Object catch (e) {
      try {
        await _writeText(
          req,
          HttpStatus.internalServerError,
          'Server-Fehler: $e',
        );
      } on Object catch (writeErr) {
        // Response already (partly) sent — log and move on.
        _log('GPU-Probe-Server: Fehlerantwort nicht sendbar: $writeErr');
      }
    }
  }

  /// Returns the HTML for `GET /`: the progress shell while running, the full
  /// report once finished.
  String indexHtml() {
    if (_finished && _reportHtml != null) return _reportHtml!;
    return formatProgressShellHtml(
      candidates: [for (final s in _states) (id: s.id, label: s.label)],
      version: version,
      timestamp: _clock(),
      token: token,
    );
  }

  Future<void> _handleIndex(HttpRequest req) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(indexHtml());
    await req.response.close();
  }

  // -------------------------------------------------------------------------
  // SSE progress stream
  // -------------------------------------------------------------------------

  /// Snapshot of all candidate states for a freshly-connected SSE client.
  Map<String, Object?> snapshot() => {
    'type': 'snapshot',
    'finished': _finished,
    'states': [
      for (final s in _states)
        {
          'id': s.id,
          'state': switch (s.state) {
            CandidateRunState.pending => 'pending',
            CandidateRunState.running => 'running',
            CandidateRunState.finished => 'finished',
          },
          if (s.outcome != null) 'outcome': s.outcome!.name,
        },
    ],
  };

  void _handleSse(HttpRequest req) {
    final res = req.response;
    res.statusCode = HttpStatus.ok;
    res.headers
      ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
      ..set(HttpHeaders.cacheControlHeader, 'no-cache')
      ..set('Connection', 'keep-alive')
      ..set('X-Accel-Buffering', 'no');
    res.bufferOutput = false;
    _sseClients.add(res);
    _writeSse(res, snapshot());
    if (_finished) _writeSse(res, {'type': 'done'});
    res.done
        .then((_) => _sseClients.remove(res))
        .catchError((_) => _sseClients.remove(res));
  }

  void _writeSse(HttpResponse res, Map<String, Object?> data) {
    try {
      res.write('data: ${jsonEncode(data)}\n\n');
    } on Object {
      _sseClients.remove(res);
    }
  }

  void _broadcast(Map<String, Object?> data) {
    for (final res in _sseClients.toList()) {
      _writeSse(res, data);
    }
  }

  Future<void> _closeSseClients() async {
    for (final res in _sseClients.toList()) {
      try {
        await res.close();
      } on Object catch (e) {
        _log('GPU-Probe-Server: SSE-Client-Schließen fehlgeschlagen: $e');
      }
    }
    _sseClients.clear();
  }

  // -------------------------------------------------------------------------
  // Live transcription
  // -------------------------------------------------------------------------

  /// Finds a candidate by id, or null.
  ProbeCandidate? candidateById(String? id) {
    if (id == null) return null;
    for (final c in candidates) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _handleTranscribe(HttpRequest req) async {
    final id = req.uri.queryParameters['candidate'];
    final candidate = candidateById(id);
    if (candidate == null) {
      await _writeJson(req, HttpStatus.notFound, {
        'error': 'Unbekannter Kandidat: ${id ?? '(keiner)'}',
      });
      return;
    }

    final bytes = await _readBody(req);
    final tmp = await _ensureTmpDir();
    final wavPath = p.join(tmp.path, 'live-${_liveCounter++}.wav');
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(bytes);

    final ctx = ProbeContext(
      referenceWavPath: wavPath,
      modelPath: contextTemplate.modelPath,
      workDir: tmp.path,
      language: contextTemplate.language,
      timeout: contextTemplate.timeout,
    );

    final sw = Stopwatch()..start();
    final result = await candidate.run(ctx);
    sw.stop();

    try {
      await wavFile.delete();
    } on Object catch (e) {
      _log('GPU-Probe-Server: Temp-WAV nicht löschbar: $e');
    }

    final durationMs = result.durationMs ?? sw.elapsedMilliseconds;
    await _writeJson(req, HttpStatus.ok, {
      'candidateId': result.candidateId,
      'outcome': result.outcome.name,
      // Transcription is the user's own speech — passed through verbatim.
      'transcribedText': result.transcribedText,
      'durationMs': durationMs,
      'realtimeFactor': result.realtimeFactor,
      // errorDetail may carry a temp path → scrub before it leaves the process.
      if (result.errorDetail != null)
        'errorDetail': sanitizePaths(result.errorDetail!),
    });
  }

  Future<Directory> _ensureTmpDir() async {
    final dir = _liveTmpDir;
    if (dir != null) return dir;
    final created = await Directory.systemTemp.createTemp('whispaste-live-');
    _liveTmpDir = created;
    return created;
  }

  // -------------------------------------------------------------------------
  // Shutdown
  // -------------------------------------------------------------------------

  Future<void> _handleShutdown(HttpRequest req) async {
    await _writeJson(req, HttpStatus.ok, {'ok': true});
    // Close after the response has flushed so the browser gets its 200.
    unawaited(stop());
  }

  // -------------------------------------------------------------------------
  // Low-level response helpers
  // -------------------------------------------------------------------------

  Future<List<int>> _readBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  Future<void> _writeText(HttpRequest req, int status, String body) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(body);
    await req.response.close();
  }

  Future<void> _writeJson(
    HttpRequest req,
    int status,
    Map<String, Object?> body,
  ) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await req.response.close();
  }
}

/// High-level serve-mode entry point used by the CLI.
///
/// Binds the server, opens the browser at its URL via [openBrowser], and
/// awaits a clean shutdown. [onComplete] (if given) receives the finished
/// report — the CLI uses it to write the JSON/MD/HTML/ZIP artifacts.
Future<void> runLiveProbe({
  required List<ProbeCandidate> candidates,
  required ProbeContext context,
  required String version,
  required Future<void> Function(Uri url) openBrowser,
  HardwareContext? hardwareContext,
  Future<void> Function(ProbeReport report)? onComplete,
  void Function(String)? logger,
}) async {
  final server = LiveProbeServer(
    candidates: candidates,
    contextTemplate: context,
    version: version,
    hardwareContext: hardwareContext,
    onComplete: onComplete,
    logger: logger,
  );
  final url = await server.start();
  await openBrowser(url);
  await server.awaitShutdown();
}
