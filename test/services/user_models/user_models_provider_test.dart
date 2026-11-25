/// The steps of "Add own model" in the model library (#1514, #1789): what
/// the user typed or picked becomes a draft for the right section or a
/// reason; the notifier lists, adds, stops and removes own models.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/hf_repo_resolver.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_check.dart';
import 'package:whispaste/services/user_models/user_model_checker.dart';
import 'package:whispaste/services/user_models/user_model_detection.dart';
import 'package:whispaste/services/user_models/user_model_inspector.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';
import 'package:whispaste/services/user_models/user_model_store.dart';
import 'package:whispaste/services/user_models/user_models_provider.dart';

class _Checker implements UserModelChecker {
  _Checker({this.failure, this.gate});
  final UserModelFailure? failure;
  final Completer<void>? gate;

  @override
  Future<UserModelCheckReport> check(UserModel model) async {
    await gate?.future;
    return UserModelCheckReport(
      inspection: const InspectionResult.ok(),
      testFailure: failure,
    );
  }
}

HfRepoSnapshot _snapshot(List<String> names) => HfRepoSnapshot(
  repoId: 'someone/models',
  commit: 'a' * 40,
  license: 'mit',
  files: [
    for (final n in names)
      SourceFile(path: n, sizeBytes: 1000, sha256: 'b' * 64),
  ],
);

void main() {
  group('address', () {
    test('a refused address says so without asking the network', () async {
      var asked = false;
      final result = await prepareDraftFromAddress(
        'http://example.com/model.gguf',
        purpose: UserModelPurpose.smartMode,
        confirmedHosts: const {},
        probeSize: (_, _) async {
          asked = true;
          return 1;
        },
      );
      expect(
        (result as UserModelSourceFailed).error,
        UserModelSourceError.address,
      );
      expect(asked, isFalse);
    });

    test(
      'a Hugging Face repo gives the model of the section, pinned',
      () async {
        final repo = _snapshot(['ggml-base.bin', 'model-Q4_K_M.gguf']);
        final speech = await prepareDraftFromAddress(
          'https://huggingface.co/someone/models',
          purpose: UserModelPurpose.speech,
          confirmedHosts: const {},
          resolve: (_) async => repo,
        );
        final draft = (speech as UserModelSourceOk).draft;
        expect(draft.runtime, UserModelRuntime.whispercpp);
        expect(draft.revision, 'a' * 40);
        expect(draft.files.single.url, contains('/resolve/${'a' * 40}/'));

        final smart = await prepareDraftFromAddress(
          'https://huggingface.co/someone/models',
          purpose: UserModelPurpose.smartMode,
          confirmedHosts: const {},
          resolve: (_) async => repo,
        );
        expect(
          (smart as UserModelSourceOk).draft.runtime,
          UserModelRuntime.llamaCpp,
        );
      },
    );

    test('a repo with only a model for the other section is refused', () async {
      final result = await prepareDraftFromAddress(
        'https://huggingface.co/someone/models',
        purpose: UserModelPurpose.speech,
        confirmedHosts: const {},
        resolve: (_) async => _snapshot(['model-Q4_K_M.gguf']),
      );
      expect(
        (result as UserModelSourceFailed).error,
        UserModelSourceError.wrongPurpose,
      );
    });

    test('gated and missing repos get their own reason', () async {
      Future<UserModelSourceResult> run(HfResolveError e) =>
          prepareDraftFromAddress(
            'https://huggingface.co/someone/models',
            purpose: UserModelPurpose.speech,
            confirmedHosts: const {},
            resolve: (_) async => throw HfResolveException(e),
          );
      expect(
        ((await run(HfResolveError.gated)) as UserModelSourceFailed).error,
        UserModelSourceError.gated,
      );
      expect(
        ((await run(HfResolveError.notFound)) as UserModelSourceFailed).error,
        UserModelSourceError.notFound,
      );
      expect(
        ((await run(HfResolveError.network)) as UserModelSourceFailed).error,
        UserModelSourceError.network,
      );
    });

    test('a direct file takes its size from the server', () async {
      final result = await prepareDraftFromAddress(
        'https://files.example.org/models/ggml-small.bin',
        purpose: UserModelPurpose.speech,
        confirmedHosts: const {},
        probeSize: (_, _) async => 4242,
      );
      final draft = (result as UserModelSourceOk).draft;
      expect(draft.totalBytes, 4242);
      expect(draft.hosts, {'files.example.org'});
      expect(hostsToConfirm(draft, const {}), {'files.example.org'});
    });

    test('one sherpa-onnx file is not a whole model', () async {
      final result = await prepareDraftFromAddress(
        'https://files.example.org/encoder.onnx',
        purpose: UserModelPurpose.speech,
        confirmedHosts: const {},
        probeSize: (_, _) async => 1,
      );
      expect(
        (result as UserModelSourceFailed).error,
        UserModelSourceError.needsAllFiles,
      );
    });
  });

  group('picked files', () {
    test('a GGUF file is a Smart Mode model, not a speech model', () {
      final paths = ['/x/model-Q4_K_M.gguf'];
      final smart = prepareDraftFromFiles(
        paths,
        purpose: UserModelPurpose.smartMode,
        sizes: {paths.single: 10},
      );
      expect(
        (smart as UserModelSourceOk).draft.sourceKind,
        UserModelSourceKind.file,
      );
      final speech = prepareDraftFromFiles(
        paths,
        purpose: UserModelPurpose.speech,
        sizes: {paths.single: 10},
      );
      expect(
        (speech as UserModelSourceFailed).error,
        UserModelSourceError.wrongPurpose,
      );
    });

    test('a file of no known kind is refused', () {
      final result = prepareDraftFromFiles(
        ['/x/notes.txt'],
        purpose: UserModelPurpose.speech,
        sizes: {'/x/notes.txt': 1},
      );
      expect(
        (result as UserModelSourceFailed).error,
        UserModelSourceError.noModel,
      );
    });
  });

  group('notifier', () {
    late Directory tmp;
    late UserModelStore store;
    late File source;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('user_models_provider');
      store = UserModelStore(root: '${tmp.path}/user');
      source = File('${tmp.path}/model-Q4_K_M.gguf')
        ..writeAsBytesSync(List.filled(64, 1));
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    ProviderContainer container(UserModelChecker checker) {
      final c = ProviderContainer(
        overrides: [
          userModelStoreProvider.overrideWithValue(store),
          userModelInstallerProvider.overrideWithValue(
            UserModelInstaller(store: store, checker: checker),
          ),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    UserModelDraft draft() =>
        (prepareDraftFromFiles([
                  source.path,
                ], purpose: UserModelPurpose.smartMode)
                as UserModelSourceOk)
            .draft;

    test('an addition shows progress, then the model in its section', () async {
      final gate = Completer<void>();
      final c = container(_Checker(gate: gate));
      final running = c.read(userModelsProvider.notifier).install(draft());
      await pumpEventQueue();
      final during = c.read(userModelsProvider);
      expect(during.busy, isTrue);
      // Listed while it is fetched and checked, so its progress shows.
      expect(
        during.forPurpose(UserModelPurpose.smartMode).single.id,
        during.installingId,
      );
      gate.complete();
      final model = await running;
      expect(model?.isReady, isTrue);
      final state = c.read(userModelsProvider);
      expect(state.busy, isFalse);
      expect(state.forPurpose(UserModelPurpose.smartMode).single.id, model!.id);
      expect(state.forPurpose(UserModelPurpose.speech), isEmpty);
    });

    test(
      'a failed check stays listed with its reason; remove clears it',
      () async {
        final c = container(
          _Checker(failure: UserModelFailure.shortTestFailed),
        );
        final model = await c
            .read(userModelsProvider.notifier)
            .install(draft());
        expect(model?.failure, UserModelFailure.shortTestFailed);
        expect(
          c.read(userModelsProvider).models.single.status,
          UserModelStatus.failed,
        );
        c.read(userModelsProvider.notifier).remove(model!.id);
        expect(c.read(userModelsProvider).models, isEmpty);
        expect(Directory(store.modelDir(model.id)).existsSync(), isFalse);
      },
    );

    test('a stopped addition leaves nothing behind', () async {
      final gate = Completer<void>();
      final c = container(_Checker(gate: gate));
      final notifier = c.read(userModelsProvider.notifier);
      final running = notifier.install(draft());
      await pumpEventQueue();
      notifier.cancel();
      gate.complete();
      expect(await running, isNull);
      expect(c.read(userModelsProvider).models, isEmpty);
    });

    test('confirmed hosts are remembered', () {
      final c = container(_Checker());
      c.read(userModelsProvider.notifier).confirmHosts({'Files.Example.org'});
      expect(c.read(userModelsProvider).confirmedHosts, {'files.example.org'});
      expect(store.readSync().confirmedHosts, {'files.example.org'});
    });
  });
}
