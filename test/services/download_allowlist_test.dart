/// Unit tests for the download host allowlist ([assertAllowedDownloadUri]) and
/// the redirect-checking transport ([getWithAllowlistedRedirects]).
///
/// No real network: every request goes through a fake [HttpClientAdapter].
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/download_allowlist.dart';

/// Records every request and answers from [handler].
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok() => ResponseBody.fromString('ok', 200);

ResponseBody _redirect(String location, {int status = 302}) =>
    ResponseBody.fromString(
      '',
      status,
      headers: {
        'location': [location],
      },
    );

Dio _dioWith(_RecordingAdapter adapter) => Dio()..httpClientAdapter = adapter;

void main() {
  group('assertAllowedDownloadUri — accepts the real download hosts', () {
    const realUrls = [
      'https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/resolve/main/encoder.int8.onnx',
      'https://huggingface.co/ggml-org/parakeet-GGUF/resolve/35156454d1a39de06863303dd209fd2bed6ee079/ggml-parakeet-tdt-0.6b-v3-q8_0.bin',
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin',
      'https://huggingface.co/unsloth/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q4_K_M.gguf',
      'https://us.aws.cdn.hf.co/xet-bridge-us/641ab5d15d107c5c5f346372/abc?X-Xet-Cas-Uid=public',
      'https://github.com/whispaste/whispaste/releases/download/cuda-ggml-v1.9.5-cu12.8-r1/WhisPaste-CUDA-ggml-v1.9.5-cu12.8-r1-linux-x64.tar.gz',
      'https://release-assets.githubusercontent.com/github-production-release-asset/1/abc',
      'https://api.github.com/repos/whispaste/whispaste/releases/latest',
      'https://raw.githubusercontent.com/whispaste/whispaste/beta-appcast-pointer/appcast-beta.xml',
      // Other HuggingFace CDN hosts, picked per region and storage backend.
      'https://cdn-lfs-eu-1.hf.co/repos/ab/cd/file?sig=1',
      'https://cdn-lfs-us-1.hf.co/repos/ab/cd/file?sig=1',
      'https://cas-bridge.xethub.hf.co/xet-bridge-us/abc?sig=1',
      'https://cdn-lfs.huggingface.co/repos/ab/cd/file?sig=1',
      'https://objects.githubusercontent.com/github-production-release-asset-2e65be/1/abc',
    ];

    for (final url in realUrls) {
      test(url, () {
        expect(() => assertAllowedDownloadUri(Uri.parse(url)), returnsNormally);
      });
    }
  });

  group('assertAllowedDownloadUri — rejects everything else', () {
    const rejected = {
      'plain http on an allowed host': 'http://huggingface.co/x/model.bin',
      'look-alike suffix': 'https://huggingface.co.evil.com/x/model.bin',
      'look-alike prefix': 'https://evilhuggingface.co/x/model.bin',
      'userinfo trick': 'https://huggingface.co@evil.example/x/model.bin',
      'foreign host': 'https://evil.example/x/model.bin',
      'github look-alike': 'https://github.com.evil.example/x/y',
      'hf look-alike prefix': 'https://evilhf.co/x/model.bin',
      'hf look-alike suffix': 'https://cdn.hf.co.evil.com/x/model.bin',
      'bare vendor domain without subdomain trust': 'https://hf.co.example/x',
      'other githubusercontent subdomain':
          'https://gist.githubusercontent.com/x',
      'non-default port on allowed host': 'https://huggingface.co:8443/x',
      'file scheme': 'file:///etc/passwd',
      'no host': 'https:///x/model.bin',
    };

    rejected.forEach((label, url) {
      test(label, () {
        expect(
          () => assertAllowedDownloadUri(Uri.parse(url)),
          throwsA(isA<DownloadUrlRejectedException>()),
        );
      });
    });

    test('rejection message names the blocked host', () {
      expect(
        () => assertAllowedDownloadUri(
          Uri.parse('https://huggingface.co.evil.com/x'),
        ),
        throwsA(
          isA<DownloadUrlRejectedException>().having(
            (e) => e.toString(),
            'message',
            contains('huggingface.co.evil.com'),
          ),
        ),
      );
    });
  });

  test('every allowlisted host documents why it is reachable', () {
    for (final entry in kDownloadHostAllowlist.entries) {
      expect(entry.key, entry.key.toLowerCase());
      expect(entry.key, isNot(contains('*')), reason: 'exact hosts only');
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: '${entry.key} needs a reason',
      );
    }
    for (final entry in kDownloadDomainAllowlist.entries) {
      expect(entry.key, entry.key.toLowerCase());
      expect(entry.key, isNot(startsWith('.')));
      expect(entry.value.trim(), isNotEmpty);
    }
  });

  group('getWithAllowlistedRedirects', () {
    test('rejects a foreign initial host without opening a connection', () {
      final adapter = _RecordingAdapter((_) => _ok());
      expect(
        getWithAllowlistedRedirects<String>(
          _dioWith(adapter),
          'https://evil.example/model.bin',
        ),
        throwsA(isA<DownloadUrlRejectedException>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('follows a redirect to an allowlisted CDN host', () async {
      final adapter = _RecordingAdapter((o) {
        if (o.uri.host == 'huggingface.co') {
          return _redirect('https://us.aws.cdn.hf.co/xet/file?sig=1');
        }
        return _ok();
      });
      final response = await getWithAllowlistedRedirects<String>(
        _dioWith(adapter),
        'https://huggingface.co/x/model.bin',
      );
      expect(response.statusCode, 200);
      expect(adapter.requests.map((r) => r.uri.host), [
        'huggingface.co',
        'us.aws.cdn.hf.co',
      ]);
    });

    test('blocks a redirect to a foreign host before requesting it', () async {
      final adapter = _RecordingAdapter(
        (_) => _redirect('https://evil.example/payload.bin'),
      );
      await expectLater(
        getWithAllowlistedRedirects<String>(
          _dioWith(adapter),
          'https://huggingface.co/x/model.bin',
        ),
        throwsA(
          isA<DownloadUrlRejectedException>().having(
            (e) => e.toString(),
            'message',
            contains('evil.example'),
          ),
        ),
      );
      expect(adapter.requests.map((r) => r.uri.host), [
        'huggingface.co',
      ], reason: 'the foreign target must never be contacted');
    });

    test('blocks a redirect that downgrades to plain http', () async {
      final adapter = _RecordingAdapter(
        (_) => _redirect('http://us.aws.cdn.hf.co/xet/file'),
      );
      await expectLater(
        getWithAllowlistedRedirects<String>(
          _dioWith(adapter),
          'https://huggingface.co/x/model.bin',
        ),
        throwsA(isA<DownloadUrlRejectedException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('resolves a relative Location against the current host', () async {
      final adapter = _RecordingAdapter((o) {
        if (o.uri.path == '/x/model.bin') return _redirect('/x/other.bin');
        return _ok();
      });
      await getWithAllowlistedRedirects<String>(
        _dioWith(adapter),
        'https://huggingface.co/x/model.bin',
      );
      expect(
        adapter.requests.last.uri.toString(),
        'https://huggingface.co/x/other.bin',
      );
    });

    test('keeps the Range header on every redirect hop (resume)', () async {
      final adapter = _RecordingAdapter((o) {
        if (o.uri.host == 'huggingface.co') {
          return _redirect('https://us.aws.cdn.hf.co/xet/file');
        }
        return _ok();
      });
      await getWithAllowlistedRedirects<String>(
        _dioWith(adapter),
        'https://huggingface.co/x/model.bin',
        options: Options(headers: {'Range': 'bytes=10-'}),
      );
      for (final r in adapter.requests) {
        expect(r.headers['Range'], 'bytes=10-', reason: r.uri.toString());
      }
    });

    test('fails closed after too many redirects', () {
      final adapter = _RecordingAdapter(
        (_) => _redirect('https://huggingface.co/loop'),
      );
      expect(
        getWithAllowlistedRedirects<String>(
          _dioWith(adapter),
          'https://huggingface.co/x',
        ),
        throwsA(isA<DownloadUrlRejectedException>()),
      );
    });

    test('non-redirect error statuses still surface as DioException', () {
      final adapter = _RecordingAdapter(
        (_) => ResponseBody.fromString('nope', 416),
      );
      expect(
        getWithAllowlistedRedirects<String>(
          _dioWith(adapter),
          'https://huggingface.co/x',
        ),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            416,
          ),
        ),
      );
    });
  });
}
