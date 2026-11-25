/// Hugging Face pinning and recognition of a user's own model (#1789): the
/// commit the API names is fixed into every download address, the LFS hash
/// comes along, and runtime/family come from the file names.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/hf_repo_resolver.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_address.dart';
import 'package:whispaste/services/user_models/user_model_detection.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';

final _commit = 'c0ffee'.padRight(40, '0');
final _sha = 'ab' * 32;

Map<String, Object?> _info(
  List<Map<String, Object?>> siblings, {
  Object? gated,
}) => {
  'sha': _commit,
  'gated': ?gated,
  'siblings': siblings,
  'cardData': {'license': 'apache-2.0'},
};

HuggingFaceAddress _addr(String s) =>
    UserModelAddress.parse(s) as HuggingFaceAddress;

void main() {
  group('parseHfModelInfo', () {
    test('pins the commit and keeps size, hash and license', () {
      final snap = parseHfModelInfo(
        _info([
          {
            'rfilename': 'm-Q4_K_M.gguf',
            'size': 10,
            'lfs': {'size': 4000, 'sha256': _sha},
          },
          {'rfilename': 'README.md', 'size': 5},
        ]),
        address: _addr('https://huggingface.co/org/repo'),
      );
      expect(snap.commit, _commit);
      expect(snap.license, 'apache-2.0');
      final gguf = snap.files.firstWhere((f) => f.path == 'm-Q4_K_M.gguf');
      expect(gguf.sizeBytes, 4000);
      expect(gguf.sha256, _sha);
    });

    test('gated repos are refused, WhisPaste downloads anonymously', () {
      expect(
        () => parseHfModelInfo(
          _info(const [], gated: 'manual'),
          address: _addr('https://huggingface.co/org/repo'),
        ),
        throwsA(
          isA<HfResolveException>().having(
            (e) => e.error,
            'error',
            HfResolveError.gated,
          ),
        ),
      );
    });

    test('a file address keeps its sherpa folder, a missing path fails', () {
      final snap = parseHfModelInfo(
        _info([
          {'rfilename': 'a/model.int8.onnx'},
          {'rfilename': 'a/tokens.txt'},
          {'rfilename': 'b/other.onnx'},
        ]),
        address: _addr(
          'https://huggingface.co/o/r/blob/main/a/model.int8.onnx',
        ),
      );
      expect(snap.files.map((f) => f.path), [
        'a/model.int8.onnx',
        'a/tokens.txt',
      ]);
      expect(
        () => parseHfModelInfo(
          _info([
            {'rfilename': 'x.gguf'},
          ]),
          address: _addr('https://huggingface.co/o/r/tree/main/nope'),
        ),
        throwsA(isA<HfResolveException>()),
      );
    });

    test('the API is asked for the named revision, main otherwise', () {
      expect(
        hfModelApiUri(_addr('https://huggingface.co/o/r')).path,
        '/api/models/o/r/revision/main',
      );
      expect(
        hfModelApiUri(_addr('https://huggingface.co/o/r/tree/v2')).path,
        '/api/models/o/r/revision/v2',
      );
    });
  });

  group('detection', () {
    test('sherpa-onnx SenseVoice by naming scheme and repo name', () {
      final c = detectUserModelCandidates(const [
        SourceFile(path: 'model.onnx'),
        SourceFile(path: 'model.int8.onnx'),
        SourceFile(path: 'tokens.txt'),
      ], repoName: 'csukuangfj/sherpa-onnx-sense-voice-zh-en');
      expect(c.first.runtime, UserModelRuntime.sherpaOnnx);
      expect(c.first.family, SherpaFamily.senseVoice);
      expect(
        c.first.files
            .firstWhere((f) => f.role == UserModelFileRole.model)
            .source
            .path,
        'model.int8.onnx',
      );
    });

    test('NeMo transducer versus plain transducer', () {
      const files = [
        SourceFile(path: 'encoder.int8.onnx'),
        SourceFile(path: 'decoder.int8.onnx'),
        SourceFile(path: 'joiner.int8.onnx'),
        SourceFile(path: 'tokens.txt'),
      ];
      expect(
        detectUserModelCandidates(
          files,
          repoName: 'x/parakeet-tdt',
        ).first.family,
        SherpaFamily.nemoTransducer,
      );
      expect(
        detectUserModelCandidates(files, repoName: 'x/zipformer').first.family,
        SherpaFamily.transducer,
      );
    });

    test('GGUF Q4_K_M first, shards and projectors left out', () {
      final c = detectUserModelCandidates(const [
        SourceFile(path: 'm-Q8_0.gguf'),
        SourceFile(path: 'm-Q4_K_M.gguf'),
        SourceFile(path: 'mmproj-m.gguf'),
        SourceFile(path: 'big-00001-of-00002.gguf'),
      ]);
      expect(c.map((x) => x.label), ['m-Q4_K_M.gguf', 'm-Q8_0.gguf']);
    });

    test('whisper.cpp GGML, without encoder side files', () {
      final c = detectUserModelCandidates(const [
        SourceFile(path: 'ggml-small-q5_1.bin'),
        SourceFile(path: 'ggml-small-encoder.mlmodelc.zip'),
        SourceFile(path: 'ggml-small-encoder-openvino.bin'),
      ]);
      expect(c.single.runtime, UserModelRuntime.whispercpp);
    });

    test('unknown names give no candidate', () {
      expect(
        detectUserModelCandidates(const [SourceFile(path: 'weights.pt')]),
        isEmpty,
      );
    });
  });

  test('a HF draft pins every file address to the commit', () {
    final snap = HfRepoSnapshot(
      repoId: 'org/repo',
      commit: _commit,
      files: [
        SourceFile(path: 'sub/ggml-tiny.bin', sizeBytes: 77, sha256: _sha),
      ],
    );
    final draft = draftFromHfSnapshot(
      snap,
      detectUserModelCandidates(snap.files).single,
    );
    final file = draft.files.single;
    expect(
      file.url,
      'https://huggingface.co/org/repo/resolve/$_commit/sub/ggml-tiny.bin',
    );
    expect(file.name, 'ggml-model.bin');
    expect(file.sha256, _sha);
    expect(draft.revision, _commit);
    expect(draft.sourceAddress, 'https://huggingface.co/org/repo');
  });
}
