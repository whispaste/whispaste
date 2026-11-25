/// Safety net around a user's own model in use (#1789): when it fails, the
/// recording or the Smart Mode text goes to a checked model instead, so the
/// dictation is not lost.
///
/// - [UserModelGuardedTranscriber] wraps the transcriber of an own speech
///   model. A failure in [Transcriber.prepare] or a transcription marks the
///   model failed, returns the settings to a checked model
///   ([UserModelUse.fallBackFromSpeech]) and hands the same audio to that
///   model. Without one installed, the error goes on as `stt_server_failed`,
///   so the recording waits as pending audio for a retry.
/// - [UserModelGuardedSmartModeEngine] does the same for an own GGUF model:
///   the bundled model takes over the instruction; without it, the error goes
///   on and Smart Mode keeps the raw transcript as for any failure.
///
/// While native code runs the own model in this process, a crash marker
/// names it; a crash there takes the model out of use at the next start
/// ([UserModelUse.recoverAtStart]).
library;

import '../../core/logging/app_logger.dart';
import '../smart_mode/smart_mode_engine.dart';
import '../transcription/transcriber_interface.dart';

final _log = AppLogger('UserModelGuard');

/// What a guard needs from [UserModelUse]; a fake in tests.
abstract class UserModelGuardHost {
  /// Whether own model [id] is ready.
  bool isReady(String id);

  void markInFlight(String id);

  void clearInFlight();

  /// Takes speech model [id] out of use; true when a checked model took over.
  Future<bool> fallBackFromSpeech(String id);

  /// Takes Smart Mode model [id] out of use; true when the bundled model is
  /// installed.
  Future<bool> fallBackFromSmartMode(String id);
}

/// The guarded transcriber of own speech model [modelId].
class UserModelGuardedTranscriber
    implements Transcriber, WavFileTranscriber, ModelReportingTranscriber {
  UserModelGuardedTranscriber({
    required this.modelId,
    required this.inner,
    required this.host,
    required this.fallback,
    required this.fallbackModelId,
  });

  final String modelId;

  /// The own model's transcriber.
  final Transcriber inner;
  final UserModelGuardHost host;

  /// The transcriber for the settings after a fallback; read only then.
  final Transcriber Function() fallback;

  /// Model identity of [fallback], so history names the model that wrote.
  final String Function() fallbackModelId;

  Transcriber? _replacement;

  @override
  String? lastUsedModelId;

  @override
  Future<void> prepare() async {
    final replacement = _replacement;
    if (replacement != null) return replacement.prepare();
    if (!host.isReady(modelId)) {
      await _fallBack();
      return _replacement!.prepare();
    }
    try {
      await _guarded(inner.prepare);
    } on Object catch (e) {
      if (_isCancel(e)) rethrow;
      _log.warning('Own model $modelId did not start: ${e.runtimeType}');
      await _fallBack();
      await _replacement!.prepare();
    }
  }

  @override
  Future<String> transcribe(List<int> wavBytes, {String? language}) =>
      _run((t) => t.transcribe(wavBytes, language: language));

  @override
  Future<String> transcribeWavFile(
    String wavPath,
    List<int> wavBytes, {
    String? language,
  }) => _run(
    (t) => t is WavFileTranscriber
        ? (t as WavFileTranscriber).transcribeWavFile(
            wavPath,
            wavBytes,
            language: language,
          )
        : t.transcribe(wavBytes, language: language),
  );

  Future<String> _run(Future<String> Function(Transcriber t) call) async {
    lastUsedModelId = null;
    final replacement = _replacement;
    if (replacement != null) return _onReplacement(replacement, call);
    try {
      final text = await _guarded(() => call(inner));
      lastUsedModelId = modelId;
      return text;
    } on Object catch (e) {
      if (_isCancel(e)) rethrow;
      _log.warning('Own model $modelId failed to transcribe: ${e.runtimeType}');
      await _fallBack();
      final next = _replacement!;
      await next.prepare();
      return _onReplacement(next, call);
    }
  }

  Future<String> _onReplacement(
    Transcriber t,
    Future<String> Function(Transcriber t) call,
  ) async {
    final text = await call(t);
    lastUsedModelId = t is ModelReportingTranscriber
        ? (t as ModelReportingTranscriber).lastUsedModelId ?? fallbackModelId()
        : fallbackModelId();
    return text;
  }

  /// Takes the model out of use and picks the replacement. Throws the
  /// retryable `stt_server_failed` when no checked model is installed.
  Future<void> _fallBack() async {
    final replaced = await host.fallBackFromSpeech(modelId);
    if (!replaced) {
      throw const TranscriberException(
        'stt_server_failed',
        reason: TranscriberFailureReason.notReady,
      );
    }
    _replacement = fallback();
  }

  Future<T> _guarded<T>(Future<T> Function() call) async {
    host.markInFlight(modelId);
    try {
      return await call();
    } finally {
      host.clearInFlight();
    }
  }

  @override
  void release() {
    final replacement = _replacement;
    if (replacement != null) {
      replacement.release();
    } else {
      inner.release();
    }
  }
}

bool _isCancel(Object e) =>
    e is TranscriberException && e.reason == TranscriberFailureReason.cancelled;

/// The guarded Smart Mode engine of own GGUF model [modelId].
class UserModelGuardedSmartModeEngine implements SmartModeEngine {
  UserModelGuardedSmartModeEngine({
    required this.modelId,
    required this.inner,
    required this.host,
    required this.fallback,
  });

  final String modelId;
  final SmartModeEngine inner;
  final UserModelGuardHost host;

  /// The bundled model's engine, built only after a fallback.
  final SmartModeEngine Function() fallback;

  SmartModeEngine? _replacement;
  bool _cancelled = false;

  /// Whether the own model was taken out of use.
  bool get fellBack => _replacement != null;

  @override
  Future<String> run({
    required String systemPrompt,
    required String userText,
  }) async {
    final replacement = _replacement;
    if (replacement != null) {
      return replacement.run(systemPrompt: systemPrompt, userText: userText);
    }
    _cancelled = false;
    host.markInFlight(modelId);
    try {
      return await inner.run(systemPrompt: systemPrompt, userText: userText);
    } on Object catch (e) {
      // A run the caller aborted (its own timeout) is no model failure.
      if (_cancelled) rethrow;
      _log.warning('Own Smart Mode model $modelId failed: ${e.runtimeType}');
      final bundled = await host.fallBackFromSmartMode(modelId);
      if (!bundled) rethrow;
      final next = fallback();
      _replacement = next;
      return next.run(systemPrompt: systemPrompt, userText: userText);
    } finally {
      host.clearInFlight();
    }
  }

  @override
  Future<void> cancel() async {
    _cancelled = true;
    await (_replacement ?? inner).cancel();
  }
}
