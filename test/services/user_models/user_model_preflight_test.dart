/// Before a user's own model is downloaded (#1789): terms confirmed, hosts
/// confirmed, size against free space; and the first-download checksum.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_address.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';

UserModelDraft _draft(String url, {int size = 1000}) => UserModelDraft(
  name: 'm.gguf',
  runtime: UserModelRuntime.llamaCpp,
  sourceKind: UserModelSourceKind.url,
  files: [
    UserModelFile(
      role: UserModelFileRole.model,
      name: 'm.gguf',
      url: url,
      sizeBytes: size,
    ),
  ],
);

void main() {
  const own = 'https://models.example.org/m.gguf';

  test('no terms, no download', () {
    expect(
      preflightUserModel(
        _draft(own),
        termsConfirmed: false,
        confirmedHosts: {'models.example.org'},
        freeBytes: null,
      ),
      isA<TermsNotConfirmed>(),
    );
  });

  test('a host outside the allowlist must be confirmed first', () {
    final issue = preflightUserModel(
      _draft(own),
      termsConfirmed: true,
      confirmedHosts: const {},
      freeBytes: null,
    );
    expect(issue, isA<HostsNotConfirmed>());
    expect((issue! as HostsNotConfirmed).hosts, {'models.example.org'});
    expect(
      preflightUserModel(
        _draft('https://huggingface.co/o/r/resolve/${'a' * 40}/m.gguf'),
        termsConfirmed: true,
        confirmedHosts: const {},
        freeBytes: null,
      ),
      isNull,
      reason: 'Hugging Face is on the fixed allowlist',
    );
  });

  test('too little space stops it, an unknown answer does not', () {
    final draft = _draft(own, size: 1 << 30);
    expect(
      preflightUserModel(
        draft,
        termsConfirmed: true,
        confirmedHosts: {'models.example.org'},
        freeBytes: 1 << 30,
      ),
      isA<NotEnoughSpace>(),
    );
    expect(
      preflightUserModel(
        draft,
        termsConfirmed: true,
        confirmedHosts: {'models.example.org'},
        freeBytes: null,
      ),
      isNull,
    );
    expect(
      preflightUserModel(
        draft,
        termsConfirmed: true,
        confirmedHosts: {'models.example.org'},
        freeBytes: 4 << 30,
      ),
      isNull,
    );
  });

  test('checksum: remembered first, reported when the file changes', () {
    expect(compareFileHash(expected: null, actual: 'aa'), HashCheck.remembered);
    expect(compareFileHash(expected: 'AA', actual: 'aa'), HashCheck.matches);
    expect(compareFileHash(expected: 'aa', actual: 'bb'), HashCheck.changed);
  });

  test('size from the answer to a one-byte range request', () {
    expect(
      sizeFromHeaders(status: 206, contentRange: 'bytes 0-0/12345'),
      12345,
    );
    expect(sizeFromHeaders(status: 206, contentRange: 'bytes 0-0/*'), isNull);
    expect(sizeFromHeaders(status: 200, contentLength: '99'), 99);
    expect(sizeFromHeaders(status: 404, contentLength: '99'), isNull);
  });

  group('direct addresses and picked files', () {
    test('sherpa-onnx files are matched to the roles of the family', () {
      final result = draftFromDirectUrls(
        [
          for (final n in ['model.int8.onnx', 'tokens.txt'])
            UserModelAddress.parse('https://models.example.org/x/$n')
                as DirectFileAddress,
        ],
        runtime: UserModelRuntime.sherpaOnnx,
        family: SherpaFamily.senseVoice,
      );
      final draft = (result as DraftOk).draft;
      expect(draft.files.map((f) => f.role), [
        UserModelFileRole.model,
        UserModelFileRole.tokens,
      ]);
      expect(draft.sizeKnown, isFalse);
    });

    test('missing files are named', () {
      final result = draftFromLocalFiles(
        ['/tmp/encoder.onnx', '/tmp/tokens.txt'],
        runtime: UserModelRuntime.sherpaOnnx,
        family: SherpaFamily.transducer,
      );
      expect((result as DraftFailed).missing, [
        UserModelFileRole.decoder,
        UserModelFileRole.joiner,
      ]);
    });

    test('one file for whisper.cpp and llama.cpp, stored safely', () {
      final result = draftFromLocalFiles([
        '/tmp/ggml-tiny.bin',
      ], runtime: UserModelRuntime.whispercpp);
      final draft = (result as DraftOk).draft;
      expect(draft.files.single.name, 'ggml-model.bin');
      expect(draft.localPaths['ggml-model.bin'], '/tmp/ggml-tiny.bin');
      expect(
        draftFromLocalFiles([
          '/tmp/a.gguf',
          '/tmp/b.gguf',
        ], runtime: UserModelRuntime.llamaCpp),
        isA<DraftFailed>(),
      );
      expect(
        targetFileName(
          UserModelRuntime.llamaCpp,
          UserModelFileRole.model,
          'a b?.gguf',
        ),
        'a_b_.gguf',
      );
    });
  });

  test('new ids are user ids', () {
    expect(newUserModelId(), matches(RegExp(r'^user-[0-9a-f]{12}$')));
  });
}
