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

import 'bench_history.dart';
import 'engine_registry.dart';
import 'html_report.dart';
import 'model_store.dart';
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
    this.modelStore,
    this.engines,
    this.history,
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

  /// Optional model test bench — when present the report shows the model
  /// catalogue + download UI and the live test runs a chosen engine × model.
  final ModelStore? modelStore;

  /// Optional engine registry for the live test bench (whisper.cpp backends).
  final List<ProbeEngine>? engines;

  /// Optional persistent benchmark history — every live/batch run is appended
  /// here and rendered as a comparison table across sessions.
  final BenchHistory? history;

  /// Per-session guard token, embedded in the opened URL.
  final String token;

  final DateTime Function() _clock;
  final void Function(String) _log;

  late final List<_CandidateState> _states;
  final List<CandidateResult> _results = [];
  late DateTime _startedAt;
  bool _finished = false;
  ProbeReport? _report;

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
      } else if (path == '/api/models' && req.method == 'GET') {
        await _writeJson(req, HttpStatus.ok, {
          'models': modelStore?.statusJson() ?? const [],
        });
      } else if (path == '/api/engines' && req.method == 'GET') {
        await _writeJson(req, HttpStatus.ok, {
          'engines': engines != null ? enginesJson(engines!) : const [],
        });
      } else if (path == '/api/model/download' && req.method == 'POST') {
        await _handleModelDownload(req);
      } else if (path == '/api/transcribe' && req.method == 'POST') {
        await _handleTranscribe(req);
      } else if (path == '/api/transcribe-batch' && req.method == 'POST') {
        await _handleTranscribeBatch(req);
      } else if (path == '/api/shutdown' && req.method == 'POST') {
        await _handleShutdown(req);
      } else {
        await _writeText(req, HttpStatus.notFound, 'Nicht gefunden.');
      }
    } on Object catch (e, st) {
      _log('GPU-Probe-Server: Handler-Fehler bei ${req.uri.path}: $e\n$st');
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
    final report = _report;
    if (_finished && report != null) {
      // Render fresh each time so the model catalogue reflects current
      // download state (models can arrive after the probe finished).
      return formatProbeReportHtml(
        report,
        live: true,
        token: token,
        models: modelStore?.statusJson(),
        engines: engines != null ? enginesJson(engines!) : null,
        history: history?.load(),
      );
    }
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
    final q = req.uri.queryParameters;
    final engineId = q['engine'];
    final audioMs = int.tryParse(q['audioMs'] ?? '');

    // Engine × model bench path: route through the shared combo runner (records
    // history). The legacy demo path (a fixed candidate by id) stays separate.
    if (engineId != null && engines != null) {
      final bytes = await _readBody(req);
      final tmp = await _ensureTmpDir();
      final wavPath = p.join(tmp.path, 'live-${_liveCounter++}.wav');
      final wavFile = File(wavPath);
      await wavFile.writeAsBytes(bytes);
      final outcome = await _runEngineModel(
        engineId: engineId,
        modelId: q['model'],
        wavPath: wavPath,
        tmpPath: tmp.path,
        audioMs: audioMs,
        audioBytes: bytes.length,
      );
      await _deleteTmpWav(wavFile);
      await _writeJson(req, outcome.status, outcome.body);
      return;
    }

    // Legacy / demo path: a fixed candidate by id.
    final candidate = candidateById(q['candidate']);
    if (candidate == null) {
      await _writeJson(req, HttpStatus.notFound, {
        'error': 'Unbekannter Kandidat: ${q['candidate'] ?? '(keiner)'}',
      });
      return;
    }

    final bytes = await _readBody(req);
    final tmp = await _ensureTmpDir();
    final wavPath = p.join(tmp.path, 'live-${_liveCounter++}.wav');
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(bytes);

    _log(
      'LIVE-TEST start: candidate=${candidate.id} audioBytes=${bytes.length}',
    );

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
    await _deleteTmpWav(wavFile);

    final durationMs = result.durationMs ?? sw.elapsedMilliseconds;
    _log(
      'LIVE-TEST done: candidate=${candidate.id} '
      'outcome=${result.outcome.name} durationMs=$durationMs',
    );
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

  /// Multi-model batch: run ONE uploaded clip through several engine × model
  /// combos, append each to the history, and return a speed-ranked list
  /// (fastest `ok` first). Combos arrive as `engineId~modelId` pairs joined by
  /// commas in the `combos` query parameter.
  Future<void> _handleTranscribeBatch(HttpRequest req) async {
    final q = req.uri.queryParameters;
    final combos = _parseCombos(q['combos']);
    if (combos.isEmpty || engines == null) {
      await _writeJson(req, HttpStatus.badRequest, {
        'error': 'Keine Engine×Modell-Kombination angegeben.',
      });
      return;
    }
    final audioMs = int.tryParse(q['audioMs'] ?? '');
    final bytes = await _readBody(req);
    final tmp = await _ensureTmpDir();
    final wavPath = p.join(tmp.path, 'live-${_liveCounter++}.wav');
    final wavFile = File(wavPath);
    await wavFile.writeAsBytes(bytes);

    _log(
      'BATCH-TEST start: combos=${combos.length} audioBytes=${bytes.length}',
    );

    final runs = <Map<String, Object?>>[];
    for (final c in combos) {
      final outcome = await _runEngineModel(
        engineId: c.engineId,
        modelId: c.modelId.isEmpty ? null : c.modelId,
        wavPath: wavPath,
        tmpPath: tmp.path,
        audioMs: audioMs,
        audioBytes: bytes.length,
      );
      runs.add(outcome.body);
    }
    await _deleteTmpWav(wavFile);

    // Rank: successful runs by ascending engine time; everything else trails.
    runs.sort(_compareRuns);
    await _writeJson(req, HttpStatus.ok, {'runs': runs});
  }

  /// Resolves [engineId] + [modelId], runs the engine on [wavPath], records the
  /// run to history (when it actually ran), and returns an HTTP status + JSON
  /// body. Resolution failures come back as a 4xx body, never an exception.
  Future<({int status, Map<String, Object?> body})> _runEngineModel({
    required String engineId,
    required String wavPath,
    required String tmpPath,
    String? modelId,
    int? audioMs,
    int? audioBytes,
  }) async {
    ProbeEngine? engine;
    for (final e in engines ?? const <ProbeEngine>[]) {
      if (e.id == engineId) {
        engine = e;
        break;
      }
    }
    if (engine == null) {
      return (
        status: HttpStatus.notFound,
        body: {
          'engineId': engineId,
          'outcome': 'skipped',
          'error': 'Unbekannte Engine: $engineId',
        },
      );
    }

    var modelPath = contextTemplate.modelPath;
    String? modelLabel;
    final store = modelStore;
    if (store != null && modelId != null) {
      final mp = store.localPathIfPresent(modelId);
      if (mp == null) {
        return (
          status: HttpStatus.badRequest,
          body: {
            'engineId': engineId,
            'engineLabel': engine.label,
            'backend': engine.backend,
            'modelId': modelId,
            'outcome': 'skipped',
            'error': 'Modell nicht geladen: $modelId',
          },
        );
      }
      modelPath = mp;
      modelLabel = store.byId(modelId)?.label;
    }

    _log(
      'RUN start: engine=$engineId model=${modelId ?? '(template)'} '
      'modelPath=${sanitizePaths(modelPath)} audioBytes=${audioBytes ?? '-'}',
    );

    final ctx = ProbeContext(
      referenceWavPath: wavPath,
      modelPath: modelPath,
      workDir: tmpPath,
      language: contextTemplate.language,
      timeout: contextTemplate.timeout,
    );
    final sw = Stopwatch()..start();
    final result = await engine.candidate().run(ctx);
    sw.stop();

    final durationMs = result.durationMs ?? sw.elapsedMilliseconds;
    final rtf = (audioMs != null && audioMs > 0)
        ? durationMs / audioMs
        : result.realtimeFactor;

    _log(
      'RUN done: engine=$engineId outcome=${result.outcome.name} '
      'durationMs=$durationMs exit=${result.exitCode} '
      'text="${result.transcribedText ?? ''}" '
      'error=${result.errorDetail != null ? sanitizePaths(result.errorDetail!) : '-'} '
      'stderrTail=${result.stderrTail != null ? sanitizePaths(result.stderrTail!) : '-'}',
    );

    _recordHistory(
      BenchRun(
        timestamp: _clock(),
        engineId: engineId,
        engineLabel: engine.label,
        backend: engine.backend,
        outcome: result.outcome.name,
        modelId: modelId,
        modelLabel: modelLabel,
        durationMs: durationMs,
        audioMs: audioMs,
        realtimeFactor: rtf,
        transcribedText: result.transcribedText,
        version: version,
      ),
    );

    return (
      status: HttpStatus.ok,
      body: {
        'engineId': engineId,
        'engineLabel': engine.label,
        'backend': engine.backend,
        'isGpu': isGpuBackend(engine.backend),
        'modelId': ?modelId,
        'modelLabel': ?modelLabel,
        'outcome': result.outcome.name,
        // Transcription is the user's own speech — passed through verbatim.
        'transcribedText': result.transcribedText,
        'durationMs': durationMs,
        'audioMs': ?audioMs,
        'realtimeFactor': ?rtf,
        // errorDetail may carry a temp path → scrub before it leaves.
        if (result.errorDetail != null)
          'errorDetail': sanitizePaths(result.errorDetail!),
      },
    );
  }

  /// Appends [run] to the history, logging (not throwing) on a write error.
  void _recordHistory(BenchRun run) {
    final h = history;
    if (h == null) return;
    try {
      h.append(run);
    } on Object catch (e) {
      _log('GPU-Probe-Server: History-Schreiben fehlgeschlagen: $e');
    }
  }

  /// Parses the `combos` query value into `(engineId, modelId)` pairs.
  /// Format: `engineA~modelA,engineB~modelB`; a missing `~` means no model.
  List<({String engineId, String modelId})> _parseCombos(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final out = <({String engineId, String modelId})>[];
    for (final part in raw.split(',')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final sep = t.indexOf('~');
      if (sep < 0) {
        out.add((engineId: t, modelId: ''));
      } else {
        out.add((engineId: t.substring(0, sep), modelId: t.substring(sep + 1)));
      }
    }
    return out;
  }

  /// Ranks batch runs: `ok` first, then by ascending engine time (nulls last).
  static int _compareRuns(Map<String, Object?> a, Map<String, Object?> b) {
    final aok = a['outcome'] == 'ok';
    final bok = b['outcome'] == 'ok';
    if (aok != bok) return aok ? -1 : 1;
    final ad = (a['durationMs'] as num?)?.toInt();
    final bd = (b['durationMs'] as num?)?.toInt();
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  }

  Future<void> _deleteTmpWav(File wavFile) async {
    try {
      await wavFile.delete();
    } on Object catch (e) {
      _log('GPU-Probe-Server: Temp-WAV nicht löschbar: $e');
    }
  }

  Future<Directory> _ensureTmpDir() async {
    final dir = _liveTmpDir;
    if (dir != null) return dir;
    final created = await Directory.systemTemp.createTemp('whispaste-live-');
    _liveTmpDir = created;
    return created;
  }

  // -------------------------------------------------------------------------
  // Model download (progress fanned out over SSE)
  // -------------------------------------------------------------------------

  Future<void> _handleModelDownload(HttpRequest req) async {
    final id = req.uri.queryParameters['id'];
    final store = modelStore;
    if (store == null || id == null || store.byId(id) == null) {
      await _writeJson(req, HttpStatus.notFound, {
        'error': 'Unbekanntes Modell: ${id ?? '(keines)'}',
      });
      return;
    }
    // Kick off the download; progress ticks broadcast the model's status entry.
    unawaited(
      store.download(
        id,
        onChange: () {
          for (final m in store.statusJson()) {
            if (m['id'] == id) {
              _broadcast({'type': 'model', ...m});
              break;
            }
          }
        },
      ),
    );
    await _writeJson(req, HttpStatus.accepted, {'started': id});
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
  ModelStore? modelStore,
  List<ProbeEngine>? engines,
  BenchHistory? history,
}) async {
  final server = LiveProbeServer(
    candidates: candidates,
    contextTemplate: context,
    version: version,
    hardwareContext: hardwareContext,
    onComplete: onComplete,
    logger: logger,
    modelStore: modelStore,
    engines: engines,
    history: history,
  );
  final url = await server.start();
  await openBrowser(url);
  await server.awaitShutdown();
}
