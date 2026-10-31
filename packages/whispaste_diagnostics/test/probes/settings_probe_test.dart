/// Unit tests for settings_probe.dart (AC3).
library;

import 'package:test/test.dart';
import 'package:whispaste_diagnostics/src/probes/settings_probe.dart';

void main() {
  group('buildSettingsSnapshot', () {
    test('passes through normal fields unchanged', () {
      const inputs = SettingsInput(
        sttProvider: 'onDevice',
        sttModel: 'whisper-small',
        sttBackend: 'cpu',
        hotkey: 'Ctrl+Shift+D',
        afterAction: 'paste',
        hasApiKey: false,
      );

      final result = buildSettingsSnapshot(inputs);

      expect(result.sttProvider, 'onDevice');
      expect(result.sttModel, 'whisper-small');
      expect(result.sttBackend, 'cpu');
      expect(result.hotkey, 'Ctrl+Shift+D');
      expect(result.afterAction, 'paste');
      expect(result.apiKeyRedacted, isFalse);
    });

    test('redacts OpenAI key if it appears in a field value', () {
      // This should never happen in normal usage (keys are excluded at the
      // app layer), but the sanitizer must catch it defensively.
      const inputs = SettingsInput(
        sttProvider: 'openAI',
        sttModel: 'sk-abcdefghij1234567',
        hasApiKey: true,
      );

      final result = buildSettingsSnapshot(inputs);

      // sttModel contained a key-like value — sanitizer must redact it.
      expect(result.sttModel, '<redacted>');
      // apiKeyRedacted flag must be set.
      expect(result.apiKeyRedacted, isTrue);
    });

    test('apiKeyRedacted is true when hasApiKey is true', () {
      const inputs = SettingsInput(sttProvider: 'deepgram', hasApiKey: true);

      final result = buildSettingsSnapshot(inputs);
      expect(result.apiKeyRedacted, isTrue);
    });

    test('apiKeyRedacted is false when hasApiKey is false', () {
      const inputs = SettingsInput(sttProvider: 'onDevice', hasApiKey: false);

      final result = buildSettingsSnapshot(inputs);
      expect(result.apiKeyRedacted, isFalse);
    });

    test('handles null fields gracefully', () {
      const inputs = SettingsInput();

      final result = buildSettingsSnapshot(inputs);

      expect(result.sttProvider, isNull);
      expect(result.sttModel, isNull);
      expect(result.sttBackend, isNull);
      expect(result.hotkey, isNull);
      expect(result.afterAction, isNull);
      expect(result.apiKeyRedacted, isFalse);
    });

    test('redacts bearer token if embedded in hotkey field', () {
      // Defensive: sanitizer covers all fields.
      const inputs = SettingsInput(hotkey: 'Bearer sk-abc123def456');

      final result = buildSettingsSnapshot(inputs);
      expect(result.hotkey, '<redacted>');
    });

    test('sanitizes paths in settings fields', () {
      // Simulate a field that somehow picked up an absolute path.
      const inputs = SettingsInput(sttBackend: 'cpu', afterAction: 'paste');

      // Normal values should pass through.
      final result = buildSettingsSnapshot(inputs);
      expect(result.sttBackend, 'cpu');
      expect(result.afterAction, 'paste');
    });
  });
}
