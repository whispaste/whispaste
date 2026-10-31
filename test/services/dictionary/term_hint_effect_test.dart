import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/dictionary/term_hint_effect.dart';

void main() {
  group('termHintEffectFor', () {
    test('on-device Whisper passes terms as an initial prompt', () {
      expect(
        termHintEffectFor(
          provider: SttProviderType.onDevice,
          engine: OnDeviceEngine.whisper,
        ),
        TermHintEffect.promptHint,
      );
    });

    test('OpenAI passes terms as the transcription prompt', () {
      expect(
        termHintEffectFor(
          provider: SttProviderType.openAI,
          engine: OnDeviceEngine.whisper,
        ),
        TermHintEffect.promptHint,
      );
    });

    test('on-device Parakeet has no prompt channel: replacements only', () {
      expect(
        termHintEffectFor(
          provider: SttProviderType.onDevice,
          engine: OnDeviceEngine.parakeet,
        ),
        TermHintEffect.replacementOnly,
      );
    });

    test('Deepgram takes the terms as keyterms: prompt hint', () {
      expect(
        termHintEffectFor(
          provider: SttProviderType.deepgram,
          engine: OnDeviceEngine.whisper,
        ),
        TermHintEffect.promptHint,
      );
    });
  });
}
