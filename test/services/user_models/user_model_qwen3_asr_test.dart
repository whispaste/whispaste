/// Qwen3-ASR as a user's own sherpa-onnx model (#153): recognised from the
/// repo layout (tokenizer in a subfolder, no `tokens.txt`), stored flat under
/// the names sherpa-onnx looks up, checked like every other family and
/// configured with the model folder as tokenizer folder.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/user_models/hf_repo_resolver.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_address.dart';
import 'package:whispaste/services/user_models/user_model_detection.dart';
import 'package:whispaste/services/user_models/user_model_inspector.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';
import 'package:whispaste/services/user_models/user_models_provider.dart';
import 'package:whispaste/services/user_models/user_sherpa_engine.dart';

/// The layout of the sherpa-onnx Qwen3-ASR exports on Hugging Face.
const _repoFiles = [
  'README.md',
  'conv_frontend.onnx',
  'encoder.int8.onnx',
  'decoder.int8.onnx',
  'tokenizer/merges.txt',
  'tokenizer/tokenizer_config.json',
  'tokenizer/vocab.json',
];

List<SourceFile> _sources(List<String> paths) => [
  for (final path in paths) SourceFile(path: path, sizeBytes: 10),
];

void main() {
  group('detection', () {
    test('the repo layout gives one Qwen3-ASR candidate', () {
      final candidates = detectUserModelCandidates(
        _sources(_repoFiles),
        repoName: 'someone/sherpa-onnx-qwen3-asr-0.6B-int8',
      );
      expect(candidates, hasLength(1));
      final c = candidates.single;
      expect(c.family, SherpaFamily.qwen3Asr);
      expect(
        {for (final f in c.files) f.role: f.source.path},
        {
          UserModelFileRole.convFrontend: 'conv_frontend.onnx',
          UserModelFileRole.encoder: 'encoder.int8.onnx',
          UserModelFileRole.decoder: 'decoder.int8.onnx',
          UserModelFileRole.tokenizerVocab: 'tokenizer/vocab.json',
          UserModelFileRole.tokenizerMerges: 'tokenizer/merges.txt',
          UserModelFileRole.tokenizerConfig: 'tokenizer/tokenizer_config.json',
        },
      );
    });

    test('the repo name does not matter, the files decide', () {
      final c = detectUserModelCandidates(_sources(_repoFiles)).single;
      expect(c.family, SherpaFamily.qwen3Asr);
    });

    test('without the tokenizer there is no candidate', () {
      final candidates = detectUserModelCandidates(
        _sources(_repoFiles.where((f) => !f.startsWith('tokenizer/')).toList()),
      );
      expect(candidates, isEmpty);
    });

    test('model files from a subfolder are never mixed in', () {
      // Only the tokenizer may come from below; a second export in a
      // subfolder stays its own candidate.
      final candidates = detectUserModelCandidates(
        _sources([
          ..._repoFiles,
          'fp16/conv_frontend.onnx',
          'fp16/encoder.onnx',
          'fp16/decoder.onnx',
        ]),
      );
      final root = candidates.firstWhere(
        (c) => c.files.any((f) => f.source.path == 'encoder.int8.onnx'),
      );
      expect(
        root.files.where((f) => f.source.path.startsWith('fp16/')),
        isEmpty,
      );
    });

    test('a tokens file in a subfolder completes any family', () {
      final c = detectUserModelCandidates(
        _sources(['model.int8.onnx', 'extra/tokens.txt']),
        repoName: 'org/sherpa-onnx-sense-voice-small',
      ).single;
      expect(c.family, SherpaFamily.senseVoice);
      expect(c.fileFor(UserModelFileRole.tokens), 'extra/tokens.txt');
    });

    test('a file address keeps the tokenizer folder below it', () {
      final snapshot = parseHfModelInfo(
        {
          'sha': 'c0ffee'.padRight(40, '0'),
          'siblings': [
            for (final f in _repoFiles) {'rfilename': f, 'size': 1},
          ],
        },
        address:
            UserModelAddress.parse(
                  'https://huggingface.co/org/repo/blob/main/encoder.int8.onnx',
                )
                as HuggingFaceAddress,
      );
      expect(
        snapshot.files.map((f) => f.path),
        containsAll(['tokenizer/vocab.json', 'decoder.int8.onnx']),
      );
    });
  });

  test('the draft stores the tokenizer flat under its fixed names', () {
    final snapshot = HfRepoSnapshot(
      repoId: 'org/qwen3',
      commit: 'c0ffee'.padRight(40, '0'),
      files: _sources(_repoFiles),
    );
    final c = detectUserModelCandidates(snapshot.files).single;
    final draft = draftFromHfSnapshot(snapshot, c);
    expect(draft.files.map((f) => f.name), [
      'conv_frontend.onnx',
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'vocab.json',
      'merges.txt',
      'tokenizer_config.json',
    ]);
    final vocab = draft.files.firstWhere(
      (f) => f.role == UserModelFileRole.tokenizerVocab,
    );
    expect(vocab.url, endsWith('/tokenizer/vocab.json'));
  });

  test('a stored Qwen3-ASR model survives a round trip', () {
    final model = UserModel(
      id: 'user-abc',
      name: 'org/qwen3',
      runtime: UserModelRuntime.sherpaOnnx,
      family: SherpaFamily.qwen3Asr,
      sourceKind: UserModelSourceKind.huggingFace,
      files: const [
        UserModelFile(role: UserModelFileRole.convFrontend, name: 'c.onnx'),
        UserModelFile(role: UserModelFileRole.tokenizerVocab, name: 'v.json'),
      ],
      addedAt: DateTime.utc(2026, 11, 24),
    );
    final back = UserModel.fromJson(jsonDecode(jsonEncode(model.toJson())))!;
    expect(back.family, SherpaFamily.qwen3Asr);
    expect(back.files.map((f) => f.role), [
      UserModelFileRole.convFrontend,
      UserModelFileRole.tokenizerVocab,
    ]);
  });

  group('on disk', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wp_qwen3_'));
    tearDown(() => dir.deleteSync(recursive: true));

    UserModel model() => UserModel(
      id: 'user-q',
      name: 'q',
      runtime: UserModelRuntime.sherpaOnnx,
      family: SherpaFamily.qwen3Asr,
      sourceKind: UserModelSourceKind.file,
      files: [
        for (final (role, name) in [
          (UserModelFileRole.convFrontend, 'conv_frontend.onnx'),
          (UserModelFileRole.encoder, 'encoder.int8.onnx'),
          (UserModelFileRole.decoder, 'decoder.int8.onnx'),
          (UserModelFileRole.tokenizerVocab, 'vocab.json'),
          (UserModelFileRole.tokenizerMerges, 'merges.txt'),
          (UserModelFileRole.tokenizerConfig, 'tokenizer_config.json'),
        ])
          UserModelFile(role: role, name: name),
      ],
      addedAt: DateTime.utc(2026),
    );

    void write(String name, Object content) {
      final f = File(p.join(dir.path, name))..createSync(recursive: true);
      content is List<int>
          ? f.writeAsBytesSync(content)
          : f.writeAsStringSync('$content');
    }

    void writeModel({String merges = '#version: 0.2\nĠ t\nĠ a\nh e\n'}) {
      for (final n in [
        'conv_frontend.onnx',
        'encoder.int8.onnx',
        'decoder.int8.onnx',
      ]) {
        write(n, [0x08, 0x08, 0, 0]);
      }
      write('vocab.json', '{"a": 0, "b": 1}');
      write('merges.txt', merges);
      write('tokenizer_config.json', '{"model_max_length": 131072}');
    }

    test('the format check accepts the tokenizer files', () {
      writeModel();
      expect(inspectUserModel(model(), dir.path).ok, isTrue);
    });

    test('a broken tokenizer file fails the format check', () {
      writeModel(merges: 'not a merges file at all\n<html>\n<body>\n');
      final result = inspectUserModel(model(), dir.path);
      expect(result.failure, UserModelFailure.badFormat);
      write('merges.txt', 'Ġ t\nĠ a\n');
      write('vocab.json', '<html></html>');
      expect(
        inspectUserModel(model(), dir.path).failure,
        UserModelFailure.badFormat,
      );
    });

    test('the engine reads the tokenizer from the model folder', () {
      final config = userSherpaModelConfig(model(), dir.path, numThreads: 2);
      expect(config.qwen3Asr.tokenizer, dir.path);
      expect(
        config.qwen3Asr.convFrontend,
        p.join(dir.path, 'conv_frontend.onnx'),
      );
      expect(config.qwen3Asr.decoder, p.join(dir.path, 'decoder.int8.onnx'));
      expect(config.qwen3Asr.maxNewTokens, kQwen3AsrMaxNewTokens);
      expect(config.tokens, isEmpty);
      expect(config.transducer.encoder, isEmpty);
    });

    test('picking only the ONNX files finds the tokenizer below them', () {
      writeModel();
      // The download layout: tokenizer in its own folder.
      Directory(p.join(dir.path, 'tok')).createSync();
      for (final n in ['vocab.json', 'merges.txt', 'tokenizer_config.json']) {
        File(p.join(dir.path, n)).renameSync(p.join(dir.path, 'tok', n));
      }
      final picked = [
        for (final n in [
          'conv_frontend.onnx',
          'encoder.int8.onnx',
          'decoder.int8.onnx',
        ])
          p.join(dir.path, n),
      ];
      final result = prepareDraftFromFiles(
        picked,
        purpose: UserModelPurpose.speech,
      );
      expect(result, isA<UserModelSourceOk>());
      final draft = (result as UserModelSourceOk).draft;
      expect(draft.family, SherpaFamily.qwen3Asr);
      expect(
        draft.localPaths['vocab.json'],
        p.join(dir.path, 'tok', 'vocab.json'),
      );
    });
  });
}

extension on UserModelCandidate {
  String? fileFor(UserModelFileRole role) {
    for (final f in files) {
      if (f.role == role) return f.source.path;
    }
    return null;
  }
}
