/// Smart-Mode engine interface — one call per dictation plus a way to abort
/// it. The local implementation ([SmartModeFfiEngine]) keeps its model
/// resident in a worker isolate between calls (idle-unloaded, see its doc
/// comment); callers never manage that lifecycle themselves.
abstract class SmartModeEngine {
  /// Runs one Smart-Mode preset against [userText] and returns the model's
  /// response. Throws [StateError] on load/decode failure.
  Future<String> run({required String systemPrompt, required String userText});

  /// Aborts every in-flight [run] — called by callers whose own timeout
  /// fired, so a generation they already gave up on stops consuming CPU/GPU
  /// instead of running to completion in the background. The aborted [run]
  /// futures complete with an error. No-op when nothing is in flight.
  Future<void> cancel();
}

/// An engine that runs a write job itself (#251), with a time budget and an
/// output limit of its own instead of the cleanup ones. Only the OpenAI
/// engine is one; the write service runs every other engine through [run].
abstract interface class SmartWriteEngine implements SmartModeEngine {
  /// How long one write request may take before it counts as timed out.
  Duration get writeTimeout;

  /// Runs one write job. [jobId] ties the log lines of one run together;
  /// logs never carry prompt or answer text. A failure the user should see
  /// as such is a [SmartWriteEngineException].
  ///
  /// [jsonSchema] asks for a structured answer (`json_schema` response
  /// format: `name`, `strict`, `schema`), used by the snippet choice (#252);
  /// an engine without structured output ignores it and the caller parses
  /// the answer tolerantly.
  Future<String> write({
    required String systemPrompt,
    required String userText,
    required String jobId,
    Map<String, Object>? jsonSchema,
  });

  /// Aborts the running write job [jobId] in the HTTP client; its [write]
  /// then fails with [smartWriteCancelledCode]. No-op for an unknown or
  /// finished job, so a cleanup on the same engine keeps running.
  void cancelWrite(String jobId);
}

/// Code of a write job the user cancelled: the caller has already dropped it,
/// so it is never shown.
const smartWriteCancelledCode = 'smart_write_cancelled';

/// A failed write job with the error code shown to the user
/// (`smart_write_openai_*`). The message never carries prompt or answer text.
class SmartWriteEngineException implements Exception {
  const SmartWriteEngineException(this.code);

  final String code;

  @override
  String toString() => 'SmartWriteEngineException($code)';
}
