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
