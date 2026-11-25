/// Address check for a user's own model (#1789): only HTTPS on the default
/// port, no credentials, Hugging Face recognised in its usual forms.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/download_allowlist.dart';
import 'package:whispaste/services/user_models/user_model_address.dart';

UserModelAddressError? _error(String s) => switch (UserModelAddress.parse(s)) {
  RejectedAddress(:final error) => error,
  _ => null,
};

void main() {
  group('refused addresses', () {
    test('empty, not a URL, not HTTPS', () {
      expect(_error('   '), UserModelAddressError.empty);
      expect(_error('model.gguf'), UserModelAddressError.notAUrl);
      expect(
        _error('http://example.org/m.gguf'),
        UserModelAddressError.notHttps,
      );
      expect(
        _error('ftp://example.org/m.gguf'),
        UserModelAddressError.notHttps,
      );
      expect(_error('file:///tmp/m.gguf'), UserModelAddressError.notHttps);
    });

    test('credentials and other ports', () {
      expect(
        _error('https://user:pw@example.org/m.gguf'),
        UserModelAddressError.credentials,
      );
      expect(
        _error('https://example.org:8443/m.gguf'),
        UserModelAddressError.port,
      );
      expect(_error('https://example.org:443/m.gguf'), isNull);
    });
  });

  group('Hugging Face', () {
    test('repo page, tree, blob, resolve and hf.co', () {
      final page = UserModelAddress.parse('https://huggingface.co/org/repo');
      expect(page, isA<HuggingFaceAddress>());
      expect((page as HuggingFaceAddress).repoId, 'org/repo');
      expect(page.revision, isNull);

      final tree =
          UserModelAddress.parse(
                'https://huggingface.co/org/repo/tree/v1/sub/dir',
              )
              as HuggingFaceAddress;
      expect(tree.revision, 'v1');
      expect(tree.path, 'sub/dir');
      expect(tree.pointsAtFile, isFalse);

      final blob =
          UserModelAddress.parse(
                'https://hf.co/org/repo/blob/main/m-Q4_K_M.gguf',
              )
              as HuggingFaceAddress;
      expect(blob.path, 'm-Q4_K_M.gguf');
      expect(blob.pointsAtFile, isTrue);

      final resolve =
          UserModelAddress.parse(
                'https://huggingface.co/org/repo/resolve/main/ggml-x.bin?download=true',
              )
              as HuggingFaceAddress;
      expect(resolve.path, 'ggml-x.bin');
      expect(resolve.pointsAtFile, isTrue);
    });

    test('site pages are not repos', () {
      expect(
        UserModelAddress.parse('https://huggingface.co/datasets/a/b'),
        isA<DirectFileAddress>(),
      );
      expect(
        UserModelAddress.parse('https://huggingface.co/spaces/a/b'),
        isA<DirectFileAddress>(),
      );
    });

    test('pinned download address and commit detection', () {
      expect(
        huggingFaceResolveUrl(
          repoId: 'org/repo',
          commit: 'a' * 40,
          path: 'sub dir/m.gguf',
        ),
        'https://huggingface.co/org/repo/resolve/${'a' * 40}/sub%20dir/m.gguf',
      );
      expect(isCommitHash('a' * 40), isTrue);
      expect(isCommitHash('main'), isFalse);
    });
  });

  test('a direct address keeps host and file name', () {
    final a =
        UserModelAddress.parse('https://Models.Example.org/x/model.gguf#frag')
            as DirectFileAddress;
    expect(a.host, 'models.example.org');
    expect(a.fileName, 'model.gguf');
  });

  group('confirmed hosts next to the fixed allowlist', () {
    final uri = Uri.parse('https://models.example.org/m.gguf');

    test('catalog downloads still refuse the host', () {
      expect(
        () => assertAllowedDownloadUri(uri),
        throwsA(
          isA<DownloadUrlRejectedException>().having(
            (e) => e is DownloadHostNotConfirmedException,
            'not-confirmed variant',
            isFalse,
          ),
        ),
      );
    });

    test('an unconfirmed host names itself for the confirmation', () {
      expect(
        () => assertAllowedDownloadUri(uri, confirmedHosts: const {}),
        throwsA(
          isA<DownloadHostNotConfirmedException>().having(
            (e) => e.host,
            'host',
            'models.example.org',
          ),
        ),
      );
    });

    test('a confirmed host passes, matched exactly, not as a domain', () {
      assertAllowedDownloadUri(uri, confirmedHosts: {'models.example.org'});
      expect(
        () => assertAllowedDownloadUri(
          Uri.parse('https://evil.models.example.org/m.gguf'),
          confirmedHosts: {'models.example.org'},
        ),
        throwsA(isA<DownloadHostNotConfirmedException>()),
      );
    });

    test('a confirmed host never allows plain HTTP', () {
      expect(
        () => assertAllowedDownloadUri(
          Uri.parse('http://models.example.org/m.gguf'),
          confirmedHosts: {'models.example.org'},
        ),
        throwsA(isA<DownloadUrlRejectedException>()),
      );
    });
  });
}
