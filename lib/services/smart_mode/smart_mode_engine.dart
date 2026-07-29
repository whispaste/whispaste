/// Smart-Mode-v2 prototype interface — a single blocking call, deliberately
/// scoped down from [WhisperEngine]'s load()/transcribe()/unload() lifecycle:
/// this prototype re-loads the GGUF on every call rather than keeping a
/// resident model (see [SmartModeFfiEngine] doc comment). Proving the
/// sandbox-embed mechanism works comes first; a persistent-context,
/// isolate-hosted version (mirroring whisper_isolate_engine.dart) is the
/// natural next step once this is validated end-to-end in a real MAS build.
abstract class SmartModeEngine {
  /// Runs one Smart-Mode preset against [userText] and returns the model's
  /// response. Throws [StateError] on load/decode failure.
  Future<String> run({required String systemPrompt, required String userText});
}
