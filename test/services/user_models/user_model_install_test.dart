/// `user_models.json`, format check and the add flow from picked files
/// (#1789): a model only becomes ready after a passed check; a failed or
/// crashed check keeps it out of use with the reason.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_check.dart';
import 'package:whispaste/services/user_models/user_model_checker.dart';
import 'package:whispaste/services/user_models/user_model_inspector.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';
import 'package:whispaste/services/user_models/user_model_store.dart';

class _FakeChecker implements UserModelChecker {
  _FakeChecker(this.report);
  final UserModelCheckReport report;
  final checked = <String>[];

  @override
  Future<UserModelCheckReport> check(UserModel model) async {
    checked.add(model.id);
    return report;
  }
}

Uint8List _gguf({String? arch = 'llama', String? template = '{{x}}'}) {
  final b = BytesBuilder();
  void u32(int v) =>
      b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u64(int v) =>
      b.add((ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List());
  void str(String s) {
    u64(s.length);
    b.add(s.codeUnits);
  }

  u32(0x46554747);
  u32(3);
  u64(0);
  final kvs = <(String, String)>[
    if (arch != null) ('general.architecture', arch),
    ('general.name', 'test'),
    if (template != null) ('tokenizer.chat_template', template),
  ];
  u64(kvs.length);
  for (final (k, v) in kvs) {
    str(k);
    u32(8);
    str(v);
  }
  return b.toBytes();
}

void main() {
  late Directory tmp;
  late UserModelStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('user_models_test');
    store = UserModelStore(root: '${tmp.path}/user');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, List<int> bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  group('GGUF format check', () {
    test('architecture and chat template are read', () {
      final ok = inspectGguf(write('a.gguf', _gguf()).path);
      expect(ok.ok, isTrue);
      expect(ok.architecture, 'llama');
    });

    test('no chat template, embedding model, wrong magic', () {
      expect(
        inspectGguf(write('b.gguf', _gguf(template: null)).path).failure,
        UserModelFailure.noChatTemplate,
      );
      expect(
        inspectGguf(write('c.gguf', _gguf(arch: 'bert')).path).failure,
        UserModelFailure.unsupportedArchitecture,
      );
      expect(
        inspectGguf(write('d.gguf', [1, 2, 3, 4, 5, 6, 7, 8]).path).failure,
        UserModelFailure.badFormat,
      );
    });
  });

  test('store: round trip, damaged entries skipped, crash marker once', () {
    final model = UserModel(
      id: 'user-0123456789ab',
      name: 'm',
      runtime: UserModelRuntime.llamaCpp,
      sourceKind: UserModelSourceKind.file,
      files: const [
        UserModelFile(role: UserModelFileRole.model, name: 'm.gguf'),
      ],
      addedAt: DateTime.utc(2026, 11, 17),
    );
    store.writeSync(
      UserModelsData(models: [model], confirmedHosts: {'a.example'}),
    );
    final back = store.readSync();
    expect(back.byId(model.id)?.runtime, UserModelRuntime.llamaCpp);
    expect(back.confirmedHosts, {'a.example'});

    expect(
      UserModelsData.fromJson({
        'models': [
          {
            'id': '../evil',
            'name': 'x',
            'runtime': 'llama_cpp',
            'source': 'file',
            'files': [],
          },
          model.toJson(),
        ],
      }).models.map((m) => m.id),
      [model.id],
    );

    store.markInFlight(model.id);
    expect(store.takeCrashedModelId(), model.id);
    expect(store.takeCrashedModelId(), isNull);
  });

  group('installer with picked files', () {
    UserModelDraft draft() {
      final src = write('model-Q4_K_M.gguf', _gguf());
      return (draftFromLocalFiles(
                [src.path],
                runtime: UserModelRuntime.llamaCpp,
                sizes: {src.path: src.lengthSync()},
              )
              as DraftOk)
          .draft;
    }

    test('a passed check makes the model ready, hash remembered', () async {
      final checker = _FakeChecker(
        const UserModelCheckReport(inspection: InspectionResult.ok()),
      );
      final installer = UserModelInstaller(store: store, checker: checker);
      final model = await installer.install(draft());
      expect(model.status, UserModelStatus.ready);
      expect(model.files.single.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(checker.checked, [model.id]);
      expect(store.readSync().byId(model.id)?.isReady, isTrue);
      expect(
        File('${store.modelDir(model.id)}/model-Q4_K_M.gguf').existsSync(),
        isTrue,
      );
    });

    test(
      'a crashed check keeps the model out of use, with the reason',
      () async {
        final installer = UserModelInstaller(
          store: store,
          checker: _FakeChecker(
            const UserModelCheckReport(
              inspection: InspectionResult.ok(),
              testFailure: UserModelFailure.crashed,
            ),
          ),
        );
        final model = await installer.install(draft());
        expect(model.status, UserModelStatus.failed);
        expect(model.failure, UserModelFailure.crashed);
      },
    );

    test('remove deletes entry and files at any time', () async {
      final installer = UserModelInstaller(
        store: store,
        checker: _FakeChecker(
          const UserModelCheckReport(inspection: InspectionResult.ok()),
        ),
      );
      final model = await installer.install(draft());
      installer.remove(model.id);
      expect(store.readSync().models, isEmpty);
      expect(Directory(store.modelDir(model.id)).existsSync(), isFalse);
    });

    test(
      'at start: crash marker and unfinished checks become failed',
      () async {
        final installer = UserModelInstaller(
          store: store,
          checker: _FakeChecker(
            const UserModelCheckReport(inspection: InspectionResult.ok()),
          ),
        );
        final ready = await installer.install(draft());
        store.markInFlight(ready.id);
        expect(installer.recoverAtStart(), [ready.id]);
        expect(
          store.readSync().byId(ready.id)?.failure,
          UserModelFailure.crashed,
        );
      },
    );

    test('a model failing in use is marked and never active again', () async {
      final installer = UserModelInstaller(
        store: store,
        checker: _FakeChecker(
          const UserModelCheckReport(inspection: InspectionResult.ok()),
        ),
      );
      final model = await installer.install(draft());
      installer.markFailedInUse(model.id);
      final after = store.readSync().byId(model.id)!;
      expect(after.isReady, isFalse);
      expect(after.failure, UserModelFailure.failedInUse);
    });
  });
}
