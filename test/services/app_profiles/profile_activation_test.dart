import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/app_profiles/app_profile.dart';
import 'package:whispaste/services/app_profiles/profile_activation.dart';

void main() {
  final base = AppSettings.defaults;

  test('a profile writes only the fields it sets', () {
    final out = settingsWithProfile(
      base,
      const AppProfile(
        id: 'mail',
        name: 'Mail',
        asrLanguage: 'de',
        smartMode: AppProfileSmartMode.translate,
      ),
    );
    expect(out.stt.language, 'de');
    expect(out.smartMode.standardPreset, 'translate');
    expect(out.audioInput.microphone, base.audioInput.microphone);
    expect(
      out.afterTranscriptionSection.afterTranscription,
      base.afterTranscriptionSection.afterTranscription,
    );
  });

  test('a profile without fields leaves the settings unchanged', () {
    final out = settingsWithProfile(base, const AppProfile(id: 'x', name: 'X'));
    expect(out.stt.language, base.stt.language);
    expect(out.smartMode.standardPreset, base.smartMode.standardPreset);
  });

  test('applying the same profile twice gives the same settings', () {
    const profile = AppProfile(
      id: 'mail',
      name: 'Mail',
      asrLanguage: 'de',
      microphone: 'USB',
    );
    final once = settingsWithProfile(base, profile);
    final twice = settingsWithProfile(once, profile);
    expect(twice.stt.language, once.stt.language);
    expect(twice.audioInput.microphone, once.audioInput.microphone);
  });
}
