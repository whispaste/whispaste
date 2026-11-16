/// API keys area (#208): the one place where provider keys are entered.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/linux_keyring_lock_probe.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/features/settings/sections/api_keys_section.dart';
import 'package:whispaste/features/settings/sections/smart_mode_section.dart';
import 'package:whispaste/features/settings/sections/stt_section.dart';
import 'package:whispaste/features/settings/widgets/wp_settings_group.dart';
import 'package:whispaste/services/smart_mode/smart_mode_ffi_engine.dart'
    show smartModeLocalEngineAvailableProvider;

import '../../fixtures/test_helpers.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.current);
  AppSettings current;

  @override
  Future<AppSettings> build() async => current;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    current = updater(state.value ?? current);
    state = AsyncData(current);
  }
}

final _l10n = L10nEn();

AppSettings _cloudEverywhere({String openAiKey = ''}) {
  final s = AppSettings.defaults.copyWith(
    sttProvider: SttProviderType.openAI.value,
    openAiApiKey: openAiKey,
  );
  return s.copyWithSections(
    smartMode: s.smartMode.copyWith(
      provider: SmartModeProviderType.openAI.value,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Settings settings, {
  Widget? child,
  KeyringAvailability keyring = KeyringAvailability.usable,
}) async {
  await tester.pumpWidget(
    makeTestable(
      SingleChildScrollView(child: child ?? const ApiKeysSection()),
      size: const Size(1280, 2400),
      overrides: [
        settingsProvider.overrideWith(() => settings),
        apiKeysKeyringProvider.overrideWith((ref) async => keyring),
        smartModeLocalEngineAvailableProvider.overrideWithValue(true),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

final _obscuredField = find.byWidgetPredicate(
  (w) => w is EditableText && w.obscureText,
);

String _statusLabel(WidgetTester tester, ApiKeyProvider p) => tester
    .getSemantics(
      find.bySemanticsIdentifier('settings-api-keys-${p.id}-status'),
    )
    .label;

void main() {
  group('apiKeyStatus', () {
    test('a stored key wins over any keyring state', () {
      for (final a in KeyringAvailability.values) {
        expect(apiKeyStatus('sk-1', a), ApiKeyStatus.stored);
      }
    });

    test('an empty key on a locked keyring is not reported missing', () {
      expect(
        apiKeyStatus('', KeyringAvailability.locked),
        ApiKeyStatus.keyringLocked,
      );
      expect(
        apiKeyStatus(' ', KeyringAvailability.unreachable),
        ApiKeyStatus.keyringLocked,
      );
      expect(
        apiKeyStatus('', KeyringAvailability.usable),
        ApiKeyStatus.missing,
      );
      expect(
        apiKeyStatus('', KeyringAvailability.missing),
        ApiKeyStatus.missing,
      );
    });
  });

  testWidgets('speech, Smart Mode and the API keys area hold exactly one '
      'OpenAI input; the other two only link to it', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _Settings(_cloudEverywhere()),
      child: const Column(
        children: [
          SpeechRecognitionSection(),
          SmartModeSection(),
          ApiKeysSection(),
        ],
      ),
    );

    expect(
      find.bySemanticsIdentifier('settings-api-keys-openai-field'),
      findsOneWidget,
    );
    // The page holds the OpenAI and the Deepgram field, nothing else does.
    expect(_obscuredField, findsNWidgets(2));
    for (final section in [SpeechRecognitionSection, SmartModeSection]) {
      expect(
        find.descendant(of: find.byType(section), matching: _obscuredField),
        findsNothing,
      );
    }
    expect(
      find.bySemanticsIdentifier('settings-stt-api-keys-link'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier('settings-smart-mode-api-keys-link'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('typing a key takes effect at once and keeps the other key', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final settings = _Settings(
      AppSettings.defaults.copyWith(deepgramApiKey: 'dg-kept'),
    );
    await _pump(tester, settings);
    expect(
      _statusLabel(tester, ApiKeyProvider.openAi),
      _l10n.settingsApiKeyStatusMissing,
    );

    await tester.enterText(
      find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is WpSettingsRow && w.rowId == 'api-keys-openai',
        ),
        matching: find.byType(EditableText),
      ),
      'sk-new',
    );
    await tester.pumpAndSettle();

    expect(settings.current.openAiApiKey, 'sk-new');
    expect(settings.current.deepgramApiKey, 'dg-kept');
    expect(
      _statusLabel(tester, ApiKeyProvider.openAi),
      _l10n.settingsApiKeyStatusStored,
    );
    semantics.dispose();
  });

  testWidgets('a locked keyring shows "locked", never "missing"', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      _Settings(AppSettings.defaults),
      keyring: KeyringAvailability.locked,
    );
    for (final p in ApiKeyProvider.values) {
      expect(_statusLabel(tester, p), _l10n.settingsApiKeyStatusKeyringLocked);
    }
    semantics.dispose();
  });

  testWidgets('the Automation API token is not on the API keys page', (
    tester,
  ) async {
    await _pump(tester, _Settings(AppSettings.defaults));
    expect(
      find.byWidgetPredicate(
        (w) => w is WpSettingsRow && w.rowId.contains('automation'),
      ),
      findsNothing,
    );
    expect(find.text(_l10n.settingsAutomationApiToken), findsNothing);
  });
}
