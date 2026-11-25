/// Fallback when a user's own speech model fails (#1789): back to the last
/// checked catalog choice, never to another user model.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_fallback.dart';

void main() {
  const small = SpeechFallbackChoice(
    engine: 'whisper',
    modelId: 'whisper-small',
  );

  test('the remembered catalog choice wins when it is still installed', () {
    expect(
      pickSpeechFallback(
        remembered: small,
        installedWhisper: {'whisper-small', 'whisper-large-v3-turbo'},
        parakeetInstalled: true,
        systemReady: true,
      ),
      isA<SpeechFallbackChoice>()
          .having((c) => c.engine, 'engine', 'whisper')
          .having((c) => c.modelId, 'model', 'whisper-small'),
    );
  });

  test('a removed remembered model falls to the best installed Whisper', () {
    final pick = pickSpeechFallback(
      remembered: small,
      installedWhisper: {'whisper-medium'},
      parakeetInstalled: true,
      systemReady: false,
    );
    expect(pick?.modelId, 'whisper-medium');
  });

  test('then Parakeet, then the system engine, keeping no user id', () {
    final parakeet = pickSpeechFallback(
      remembered: const SpeechFallbackChoice(
        engine: 'whisper',
        modelId: 'user-abc123',
      ),
      installedWhisper: const {},
      parakeetInstalled: true,
      systemReady: true,
    );
    expect(parakeet?.engine, 'parakeet');
    expect(parakeet?.modelId, '');

    final system = pickSpeechFallback(
      remembered: null,
      installedWhisper: const {},
      parakeetInstalled: false,
      systemReady: true,
    );
    expect(system?.engine, 'system');
  });

  test('a user model is never a fallback target', () {
    expect(
      pickSpeechFallback(
        remembered: const SpeechFallbackChoice(
          engine: kUserModelEngineValue,
          modelId: '',
        ),
        installedWhisper: const {},
        parakeetInstalled: false,
        systemReady: false,
      ),
      isNull,
    );
  });

  test('an unknown engine value is not trusted', () {
    final pick = pickSpeechFallback(
      remembered: const SpeechFallbackChoice(engine: 'future', modelId: ''),
      installedWhisper: {'whisper-small'},
      parakeetInstalled: false,
      systemReady: false,
    );
    expect(pick?.modelId, 'whisper-small');
  });

  test('only catalog choices are remembered before switching', () {
    expect(
      currentCatalogSpeechChoice(engine: 'parakeet', whisperModelId: 'x'),
      isNotNull,
    );
    expect(
      currentCatalogSpeechChoice(engine: 'whisper', whisperModelId: 'user-1'),
      isNull,
    );
    expect(
      currentCatalogSpeechChoice(
        engine: kUserModelEngineValue,
        whisperModelId: 'whisper-small',
      ),
      isNull,
    );
  });

  test('a cancel is not a model failure', () {
    expect(userModelFailureFallsBack(cancelled: true), isFalse);
    expect(userModelFailureFallsBack(cancelled: false), isTrue);
  });
}
