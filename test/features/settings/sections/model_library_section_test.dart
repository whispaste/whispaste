/// Click sequences of the model library (#1514): offline note, own models
/// apart and marked "not checked", using one, removing with confirmation, the add
/// dialog's refusal of a bad address, and the "Manage models" link.
library;

import 'dart:async';
import 'dart:io';

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/model_library.dart';
import 'package:whispaste/core/config/selectable_speech_models.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/text/byte_size.dart';
import 'package:whispaste/features/settings/sections/model_library_section.dart';
import 'package:whispaste/features/settings/widgets/hf_model_search_panel.dart';
import 'package:whispaste/services/smart_mode/smart_mode_model_download_service.dart';
import 'package:whispaste/services/speech_recommendation.dart';
import 'package:whispaste/services/user_models/hf_model_search.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_check.dart';
import 'package:whispaste/services/user_models/user_model_checker.dart';
import 'package:whispaste/services/user_models/user_model_inspector.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';
import 'package:whispaste/services/user_models/user_model_store.dart';
import 'package:whispaste/services/user_models/user_models_provider.dart';

import '../../../fixtures/test_helpers.dart';

class _Checker implements UserModelChecker {
  @override
  Future<UserModelCheckReport> check(UserModel model) async =>
      const UserModelCheckReport(inspection: InspectionResult.ok());
}

final _initialSettings = AppSettings.defaults.copyWithSections(
  smartMode: AppSettings.defaults.smartMode.copyWith(provider: 'openai'),
);

class _Settings extends SettingsNotifier {
  @override
  Future<AppSettings> build() async => _initialSettings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _initialSettings));
  }
}

const _ownId = 'user-0123456789ab';

/// Answers every Hugging Face search with one runnable GGUF repo and counts
/// the requests, so a test can prove none went out before consent.
class _HubAdapter implements HttpClientAdapter {
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return ResponseBody.fromString(
      jsonEncode([
        {
          'id': 'someone/tiny-chat-GGUF',
          'downloads': 5,
          'likes': 1,
          'cardData': {'license': 'cc-by-nc-4.0'},
          'siblings': [
            {'rfilename': 'tiny-Q4_K_M.gguf'},
          ],
          'gguf': {'architecture': 'llama', 'chat_template': 't'},
        },
      ]),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Finder _key(String id) => find.byKey(ValueKey(id));

void main() {
  late Directory tmp;
  late UserModelStore store;
  late _HubAdapter hub;

  setUp(() {
    hub = _HubAdapter();
    tmp = Directory.systemTemp.createTempSync('model_library_section');
    store = UserModelStore(root: '${tmp.path}/user');
    Directory(store.modelDir(_ownId)).createSync(recursive: true);
    store.writeSync(
      UserModelsData(
        models: [
          UserModel(
            id: _ownId,
            name: 'My text model',
            runtime: UserModelRuntime.llamaCpp,
            sourceKind: UserModelSourceKind.huggingFace,
            files: const [
              UserModelFile(
                role: UserModelFileRole.model,
                name: 'm.gguf',
                sizeBytes: 2048,
              ),
            ],
            addedAt: DateTime.utc(2026, 11, 17),
            status: UserModelStatus.ready,
          ),
        ],
      ),
    );
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool offline = false,
    List<SelectableSpeechModel> speech = const [],
    List<String> languages = const ['en'],
  }) async {
    await tester.pumpWidget(
      makeTestable(
        const SingleChildScrollView(child: ModelLibrarySection()),
        locale: const Locale('en'),
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          userModelStoreProvider.overrideWithValue(store),
          userModelInstallerProvider.overrideWithValue(
            UserModelInstaller(store: store, checker: _Checker()),
          ),
          speechRecommendationProvider.overrideWith(
            (ref) => Completer<SpeechRecommendation>().future,
          ),
          dictationLanguagesProvider.overrideWithValue(languages),
          speechLibraryEntriesProvider.overrideWith(
            (ref) => speechLibraryEntries(
              speech,
              dictationLanguages: ref.watch(dictationLanguagesProvider),
              own: ref.watch(userModelsProvider),
            ),
          ),
          smartModeLibraryEntriesProvider.overrideWith(
            (ref) => smartModeLibraryEntries(
              settings: ref.watch(settingsProvider).value ?? _initialSettings,
              download: const SmartModeDownloadState(modelDownloaded: true),
              localEngineAvailable: true,
              own: ref.watch(userModelsProvider),
            ),
          ),
          modelLibraryOfflineProvider.overrideWith((ref) => offline),
          hfModelSearchFactoryProvider.overrideWithValue(
            (hasConsent) => HfModelSearch(
              hasConsent: hasConsent,
              dio: Dio()..httpClientAdapter = hub,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(ModelLibrarySection)),
    );
  }

  testWidgets('offline is said once, above both sections', (tester) async {
    await pump(tester, offline: true);
    expect(_key('model-library-offline'), findsOneWidget);
  });

  testWidgets('a model without a dictation language says which on its row '
      '(#1953)', (tester) async {
    await pump(
      tester,
      languages: const ['de', 'ja'],
      speech: [
        SelectableSpeechModel(
          engine: SpeechModelEngine.parakeet,
          modelId: 'parakeet',
          displayName: (_) => 'Parakeet',
          group: SpeechModelGroup.local,
          state: const SpeechModelReady(),
        ),
      ],
    );
    expect(_key('model-library-parakeet-not-for'), findsOneWidget);
    expect(find.textContaining('Japanese'), findsWidgets);
  });

  testWidgets('Gemma is recommended; the own model is marked not checked', (
    tester,
  ) async {
    await pump(tester);
    expect(_key('model-library-offline'), findsNothing);
    expect(_key('model-library-gemma-recommended'), findsOneWidget);
    expect(_key('model-library-$_ownId-not-verified'), findsOneWidget);
  });

  testWidgets('"Use" puts the own model into Smart Mode (#1789)', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.ensureVisible(_key('model-library-$_ownId-activate'));
    await tester.tap(_key('model-library-$_ownId-activate'));
    await tester.pumpAndSettle();
    final settings = container.read(settingsProvider).value!;
    expect(settings.smartMode.localModel, _ownId);
    expect(_key('model-library-$_ownId-activate'), findsNothing);
  });

  testWidgets('remove asks first, names the space, then the model is gone', (
    tester,
  ) async {
    final container = await pump(tester);
    await tester.ensureVisible(_key('model-library-$_ownId-remove'));
    await tester.tap(_key('model-library-$_ownId-remove'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('This frees ${formatByteSize(2048)}'),
      findsOneWidget,
    );

    await tester.tap(_key('confirm-dialog-cancel'));
    await tester.pumpAndSettle();
    expect(container.read(userModelsProvider).models, hasLength(1));

    await tester.tap(_key('model-library-$_ownId-remove'));
    await tester.pumpAndSettle();
    await tester.tap(_key('confirm-dialog-confirm'));
    await tester.pumpAndSettle();
    expect(container.read(userModelsProvider).models, isEmpty);
    expect(_key('model-library-$_ownId'), findsNothing);
    expect(Directory(store.modelDir(_ownId)).existsSync(), isFalse);
  });

  testWidgets('the add dialog refuses a plain http address', (tester) async {
    await pump(tester);
    await tester.tap(_key('model-library-add-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_key('model-library-own-smartMode-add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Address or file'));
    await tester.pumpAndSettle();

    await tester.enterText(
      _key('model-library-add-address'),
      'http://example.com/model.gguf',
    );
    await tester.tap(_key('model-library-add-check'));
    await tester.pumpAndSettle();
    expect(_key('model-library-add-error'), findsOneWidget);
    expect(_key('model-library-add-summary'), findsNothing);

    await tester.tap(_key('model-library-add-cancel'));
    await tester.pumpAndSettle();
    expect(_key('model-library-add-address'), findsNothing);
  });

  testWidgets('Hugging Face search asks nothing before consent (#2047)', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(_key('model-library-add-menu'));
    await tester.pumpAndSettle();
    await tester.tap(_key('model-library-own-smartMode-add'));
    await tester.pumpAndSettle();

    expect(_key('model-library-hf-consent'), findsOneWidget);
    expect(hub.requests, isEmpty);

    await tester.tap(_key('model-library-hf-consent-accept'));
    await tester.pumpAndSettle();
    expect(hub.requests, isNotEmpty);
    expect(hub.requests.first.host, 'huggingface.co');
    expect(store.readSync().hfSearchConsent, isTrue);
    expect(find.text('tiny-chat-GGUF'), findsOneWidget);
    // Non-commercial licenses are labelled, not hidden.
    expect(find.textContaining('Non-commercial'), findsOneWidget);

    await tester.tap(_key('model-library-add-cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('search trims and ignores case; empty results can reset', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), '  MY TEXT  ');
    await tester.pumpAndSettle();
    expect(_key('model-library-$_ownId'), findsOneWidget);
    expect(_key('model-library-gemma'), findsNothing);
    await tester.enterText(find.byType(TextField), 'absent model');
    await tester.pumpAndSettle();
    expect(_key('model-library-$_ownId'), findsNothing);
    await tester.tap(_key('model-library-reset'));
    await tester.pumpAndSettle();
    expect(_key('model-library-$_ownId'), findsOneWidget);
    expect(_key('model-library-gemma'), findsOneWidget);
  });

  testWidgets('installed filter excludes cloud and composes with type', (
    tester,
  ) async {
    await pump(tester);
    expect(_key('model-library-smart-openai'), findsOneWidget);
    await tester.tap(find.text('All models'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Installed on device').last);
    await tester.pumpAndSettle();
    expect(_key('model-library-gemma'), findsOneWidget);
    expect(_key('model-library-$_ownId'), findsOneWidget);
    expect(_key('model-library-smart-openai'), findsNothing);
    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speech recognition').last);
    await tester.pumpAndSettle();
    expect(_key('model-library-gemma'), findsNothing);
    expect(_key('model-library-reset'), findsOneWidget);
  });

  testWidgets('own model details explain how they are used', (tester) async {
    await pump(tester);
    final details = _key('model-library-$_ownId-details');
    await tester.ensureVisible(details);
    await tester.tap(details);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('your checked model takes over'),
      findsOneWidget,
    );
    await tester.tap(_key('model-library-details-close'));
    await tester.pumpAndSettle();
    expect(_key('model-library-details-close'), findsNothing);
  });
}
