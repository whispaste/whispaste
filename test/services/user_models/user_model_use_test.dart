/// Using an own model (#1789): where the choice lives in the settings, the
/// dock's entries, and the startup recovery that takes a crashed or broken
/// model out of use.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/core/config/stt_choice.dart';
import 'package:whispaste/core/l10n/generated/app_localizations_en.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_store.dart';
import 'package:whispaste/services/user_models/user_model_use.dart';
import 'package:whispaste/services/user_models/user_models_provider.dart';
import 'package:whispaste/widgets/recording_behavior.dart'
    show userModelFallbackMessage;

UserModel _own(
  String id,
  UserModelRuntime runtime, {
  UserModelStatus status = UserModelStatus.ready,
}) => UserModel(
  id: id,
  name: 'Model $id',
  runtime: runtime,
  family: runtime == UserModelRuntime.sherpaOnnx
      ? SherpaFamily.transducer
      : null,
  sourceKind: UserModelSourceKind.file,
  files: const [
    UserModelFile(role: UserModelFileRole.model, name: 'model.gguf'),
  ],
  addedAt: DateTime.utc(2026, 11, 19),
  status: status,
);

const _whisperId = 'user-aaaaaaaaaaaa';
const _sherpaId = 'user-bbbbbbbbbbbb';
const _ggufId = 'user-cccccccccccc';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;

  @override
  Future<void> updateSettings(
    AppSettings Function(AppSettings current) update,
  ) async {
    state = AsyncData(update(state.value ?? initial));
  }
}

void main() {
  group('settings rules', () {
    test('own whisper.cpp keeps the whisper engine, sherpa gets its own', () {
      final whisper = settingsUsingOwnModel(
        AppSettings.defaults,
        _own(_whisperId, UserModelRuntime.whispercpp),
      );
      expect(whisper.onDeviceEngine, OnDeviceEngine.whisper);
      expect(ownSpeechModelIdIn(whisper), _whisperId);

      final sherpa = settingsUsingOwnModel(
        AppSettings.defaults,
        _own(_sherpaId, UserModelRuntime.sherpaOnnx),
      );
      expect(sherpa.onDeviceEngine, OnDeviceEngine.userModel);
      expect(ownSpeechModelIdIn(sherpa), _sherpaId);
      expect(ownSmartModelIdIn(sherpa), isNull);
    });

    test('a catalog or cloud choice names no own model', () {
      expect(ownSpeechModelIdIn(AppSettings.defaults), isNull);
      final cloud = settingsUsingOwnModel(
        AppSettings.defaults,
        _own(_whisperId, UserModelRuntime.whispercpp),
      ).copyWith(sttProvider: SttProviderType.openAI.value);
      expect(ownSpeechModelIdIn(cloud), isNull);
    });

    test('an own GGUF model sets local Smart Mode, Gemma clears it', () {
      final smart = settingsUsingOwnModel(
        AppSettings.defaults,
        _own(_ggufId, UserModelRuntime.llamaCpp),
      );
      expect(smart.smartMode.provider, SmartModeProviderType.local.value);
      expect(ownSmartModelIdIn(smart), _ggufId);
      expect(ownSmartModelIdIn(settingsWithoutOwnSmartModel(smart)), isNull);
      // Speech is untouched.
      expect(smart.stt, AppSettings.defaults.stt);
    });

    test('the own Smart Mode model is device-bound, and stored', () {
      final smart = settingsUsingOwnModel(
        AppSettings.defaults,
        _own(_ggufId, UserModelRuntime.llamaCpp),
      );
      final back = SmartModeSettings.fromMap(smart.smartMode.toMap());
      expect(back.localModel, _ggufId);
      expect(back, smart.smartMode);
    });
  });

  group('dock and tray choices', () {
    final l10n = L10nEn();

    test('ready own speech models are offered under their name', () {
      final choices = sttChoicesFrom(
        const [],
        l10n,
        own: [
          _own(_whisperId, UserModelRuntime.whispercpp),
          _own(_sherpaId, UserModelRuntime.sherpaOnnx),
          _own(_ggufId, UserModelRuntime.llamaCpp),
          _own(
            'user-dddddddddddd',
            UserModelRuntime.sherpaOnnx,
            status: UserModelStatus.failed,
          ),
        ],
      );
      expect(choices.map((c) => c.value), [
        'whisper:$_whisperId',
        'user_model:$_sherpaId',
      ]);
      expect(choices.first.label, 'Model $_whisperId');
      expect(choices.every((c) => c.onDevice), isTrue);
    });

    test('a choice round-trips through the settings', () {
      final picked = applySttChoice(
        AppSettings.defaults,
        'user_model:$_sherpaId',
      );
      expect(picked.onDeviceEngine, OnDeviceEngine.userModel);
      expect(picked.effectiveModelId, _sherpaId);
      expect(sttChoiceValue(picked), 'user_model:$_sherpaId');

      // The bare engine value names no model and changes nothing.
      expect(
        applySttChoice(AppSettings.defaults, OnDeviceEngine.userModel.value),
        AppSettings.defaults,
      );
    });
  });

  group('fallback notice text', () {
    test('a short headline; the model name and what happened follow '
        'below it', () {
      final l10n = L10nEn();
      final seen = <String>{};
      for (final purpose in UserModelPurpose.values) {
        for (final replaced in [true, false]) {
          final text = userModelFallbackMessage(
            l10n,
            UserModelFallbackNotice(
              modelName: 'someone/a-very-long-model-name-GGUF',
              purpose: purpose,
              replaced: replaced,
            ),
          );
          expect(text.cause, l10n.userModelFallbackTitle);
          expect(
            text.nextStep,
            contains('someone/a-very-long-model-name-GGUF'),
          );
          seen.add(text.nextStep);
        }
      }
      expect(seen, hasLength(UserModelPurpose.values.length * 2));
    });
  });

  group('recovery at start', () {
    late Directory dir;
    late UserModelStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('user_model_use_');
      store = UserModelStore(root: dir.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    ProviderContainer container(
      AppSettings settings, {
      Set<String> whisper = const {'whisper-small'},
    }) {
      final c = ProviderContainer(
        overrides: [
          userModelStoreProvider.overrideWithValue(store),
          settingsProvider.overrideWith(() => _Settings(settings)),
          installedSpeechProbeProvider.overrideWithValue(
            (_) => (whisper: whisper, parakeet: false, system: false),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'a model a run crashed in is marked and replaced, with notice',
      () async {
        final model = _own(_sherpaId, UserModelRuntime.sherpaOnnx);
        store.writeSync(UserModelsData(models: [model]));
        store.markInFlight(_sherpaId);

        final c = container(settingsUsingOwnModel(AppSettings.defaults, model));
        await c.read(settingsProvider.future);
        await c.read(userModelUseProvider).recoverAtStart();

        final after = store.readSync().byId(_sherpaId)!;
        expect(after.status, UserModelStatus.failed);
        expect(after.failure, UserModelFailure.crashed);
        final settings = c.read(settingsProvider).value!;
        expect(settings.onDeviceEngine, OnDeviceEngine.whisper);
        expect(settings.effectiveModelId, 'whisper-small');
        final notice = c.read(userModelFallbackNoticeProvider);
        expect(notice?.modelName, model.name);
        expect(notice?.replaced, isTrue);
      },
    );

    test('a ready model in use stays in use', () async {
      final model = _own(_whisperId, UserModelRuntime.whispercpp);
      store.writeSync(UserModelsData(models: [model]));
      final c = container(settingsUsingOwnModel(AppSettings.defaults, model));
      await c.read(settingsProvider.future);
      await c.read(userModelUseProvider).recoverAtStart();

      expect(ownSpeechModelIdIn(c.read(settingsProvider).value!), _whisperId);
      expect(c.read(userModelFallbackNoticeProvider), isNull);
    });

    test('without a checked model the selection stays and says so', () async {
      final model = _own(_sherpaId, UserModelRuntime.sherpaOnnx);
      store.writeSync(UserModelsData(models: [model]));
      final c = container(
        settingsUsingOwnModel(AppSettings.defaults, model),
        whisper: const {},
      );
      await c.read(settingsProvider.future);
      final replaced = await c
          .read(userModelUseProvider)
          .fallBackFromSpeech(_sherpaId);

      expect(replaced, isFalse);
      expect(store.readSync().byId(_sherpaId)!.isReady, isFalse);
      expect(c.read(userModelFallbackNoticeProvider)?.replaced, isFalse);
    });

    test('activating remembers the catalog choice as the fallback', () async {
      final model = _own(_sherpaId, UserModelRuntime.sherpaOnnx);
      store.writeSync(UserModelsData(models: [model]));
      final start = AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.onDevice.value,
        sttEngine: OnDeviceEngine.whisper.value,
        sttModel: 'whisper-small',
      );
      final c = container(start);
      await c.read(settingsProvider.future);
      await c.read(userModelUseProvider).activate(model);

      expect(store.readSync().speechFallback?.modelId, 'whisper-small');
      expect(ownSpeechModelIdIn(c.read(settingsProvider).value!), _sherpaId);
    });
  });
}
