/// Hugging-Face-Suche (#2047, #2193): query building, language and size
/// filters, compatibility filter (no Parakeet GGML, streaming ONNX or GGUF
/// helper files), the merged endless list, consent gating, license labels,
/// rate limit and offline handling, and that a picked file keeps its pinned
/// commit and LFS hash so a different download is rejected.
///
/// No real network: every request goes through a fake [HttpClientAdapter].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/user_models/hf_model_search.dart';
import 'package:whispaste/services/user_models/hf_repo_resolver.dart';
import 'package:whispaste/services/user_models/user_model.dart';
import 'package:whispaste/services/user_models/user_model_detection.dart';
import 'package:whispaste/services/user_models/user_model_installer.dart';
import 'package:whispaste/services/user_models/user_model_store.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {Map<String, List<String>>? headers}) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        ...?headers,
      },
    );

Map<String, Object?> _repo(
  String id,
  List<String> files, {
  Map<String, Object?>? gguf,
  String? license,
  Object gated = false,
  int downloads = 10,
  List<String> tags = const [],
}) => {
  'id': id,
  'downloads': downloads,
  'tags': tags,
  'likes': 1,
  'lastModified': '2026-10-01T00:00:00.000Z',
  'gated': gated,
  'cardData': {'license': ?license},
  'siblings': [
    for (final f in files) {'rfilename': f},
  ],
  'gguf': ?gguf,
};

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  const speech = UserModelPurpose.speech;
  const text = UserModelPurpose.smartMode;
  List<HfModelHit> parse(List<Object?> repos, {UserModelPurpose p = speech}) =>
      parseHfSearchResults(repos, purpose: p);

  group('query', () {
    test('speech runs one stream per runtime, one language on the Hub', () {
      const query = HfSearchQuery(
        purpose: speech,
        text: ' whisper ',
        languages: ['de'],
        sort: HfSearchSort.likes,
      );
      expect(query.kinds, [HfSearchKind.whisperCpp, HfSearchKind.sherpaOnnx]);
      final uri = query.toUri(HfSearchKind.whisperCpp);
      expect(uri.host, 'huggingface.co');
      expect(uri.path, '/api/models');
      final q = uri.queryParametersAll;
      expect(q['search'], ['whisper']);
      expect(q['pipeline_tag'], ['automatic-speech-recognition']);
      expect(q['filter'], ['ggml', 'de']);
      expect(q['sort'], ['likes']);
      expect(q['expand[]'], contains('siblings'));
      expect(q['expand[]'], contains('tags'));
      expect(q['expand[]'], isNot(contains('gguf')));
      expect(
        query.toUri(HfSearchKind.sherpaOnnx).queryParametersAll['filter'],
        ['onnx', 'de'],
      );
    });

    test('several languages stay on this side (the Hub only ands filters); '
        'size and memory are never sent', () {
      const query = HfSearchQuery(
        purpose: speech,
        languages: ['de', 'fr'],
        size: HfSizeFilter.fitsDevice,
        ramMB: 16384,
      );
      final uri = query.toUri(HfSearchKind.whisperCpp);
      expect(uri.queryParametersAll['filter'], ['ggml']);
      expect(uri.toString(), isNot(contains('16384')));
      expect(query.acceptsLanguages(['en', 'fr']), isTrue);
      expect(query.acceptsLanguages(['en']), isFalse);
      expect(query.acceptsLanguages([]), isFalse);
      expect(const HfSearchQuery(purpose: speech).acceptsLanguages([]), isTrue);
    });

    test('Smart Mode asks text-generation GGUF with gguf metadata', () {
      const query = HfSearchQuery(purpose: text);
      expect(query.kinds, [HfSearchKind.gguf]);
      final q = query.toUri(HfSearchKind.gguf).queryParametersAll;
      expect(q.containsKey('search'), isFalse);
      expect(q['pipeline_tag'], ['text-generation']);
      expect(q['filter'], ['gguf']);
      expect(q['expand[]'], contains('gguf'));
    });

    test('languages start as the dictation languages, speech only', () {
      expect(hfInitialLanguages(speech, ['de', 'en-US', 'de_AT', 'auto']), [
        'de',
        'en',
      ]);
      expect(hfInitialLanguages(text, ['de']), isEmpty);
    });

    test('a row names the searched languages first', () {
      expect(hfDisplayLanguages(['en', 'fr', 'de'], ['de', 'it']), [
        'de',
        'en',
        'fr',
      ]);
    });
  });

  group('size filter', () {
    test('starts at "fits this computer" when the memory is known', () {
      expect(HfSizeFilter.initial(ramMB: 8192), HfSizeFilter.fitsDevice);
      expect(HfSizeFilter.initial(ramMB: null), HfSizeFilter.any);
      expect(
        HfSizeFilter.choices(ramMB: null),
        isNot(contains(HfSizeFilter.fitsDevice)),
      );
      expect(HfSizeFilter.choices(ramMB: 8192).first, HfSizeFilter.fitsDevice);
    });

    test('caps and fit; an unknown size only passes "any size"', () {
      const gb = 1000 * 1000 * 1000;
      expect(hfSizeAccepts(HfSizeFilter.upTo1GB, gb, ramMB: null), isTrue);
      expect(hfSizeAccepts(HfSizeFilter.upTo1GB, gb + 1, ramMB: null), isFalse);
      expect(hfSizeAccepts(HfSizeFilter.upTo1GB, null, ramMB: null), isFalse);
      expect(hfSizeAccepts(HfSizeFilter.any, null, ramMB: null), isTrue);
      // 8 GB of memory: 3 GB fits (tight at most), 7 GB does not.
      expect(
        hfSizeAccepts(HfSizeFilter.fitsDevice, 3 * gb, ramMB: 8192),
        isTrue,
      );
      expect(
        hfSizeAccepts(HfSizeFilter.fitsDevice, 7 * gb, ramMB: 8192),
        isFalse,
      );
      expect(
        hfSizeAccepts(HfSizeFilter.fitsDevice, null, ramMB: 8192),
        isFalse,
      );
    });

    test('Whisper sizes from the names, turbo and quantisation included', () {
      final hits = parse([
        _repo('a/turbo', ['ggml-large-v3-turbo-q5_0.bin']),
        _repo('a/large', ['ggml-large-v3.bin', 'ggml-large-v3-q8_0.bin']),
        _repo('a/whisper-small-de', ['ggml-model.bin']),
        _repo('a/unnamed', ['ggml-model.bin']),
      ]);
      final bytes = {for (final h in hits) h.repoId: h.estimatedBytes};
      expect(bytes['a/turbo'], closeTo(574e6, 30e6));
      expect(bytes['a/large'], closeTo(1.67e9, 0.1e9));
      expect(bytes['a/whisper-small-de'], 488 * 1000 * 1000);
      expect(bytes['a/unnamed'], isNull);
    });

    test('GGUF size from the parameters and the smallest quantisation', () {
      const tpl = {'chat_template': 't', 'architecture': 'llama'};
      final hit = parse([
        _repo(
          'g/m',
          ['m-Q8_0.gguf', 'm-Q4_K_M.gguf'],
          gguf: {...tpl, 'total': 1000000000},
        ),
      ], p: text).single;
      expect(hit.estimatedBytes, 600000000);
    });
  });

  group('compatibility filter', () {
    test('whisper.cpp: only repos with a ggml-*.bin', () {
      final hits = parse([
        _repo('a/ggml', ['ggml-small-q5_0.bin', 'README.md']),
        _repo('b/safetensors', ['model.safetensors', 'config.json']),
        _repo('c/coreml', ['ggml-base-encoder.mlmodelc/x']),
      ]);
      expect(hits.map((h) => h.repoId), ['a/ggml']);
      expect(hits.single.kinds, {HfSearchKind.whisperCpp});
    });

    test('Parakeet and other ggml ports are not Whisper (live repos, '
        '2026-11-24)', () {
      final hits = parse([
        _repo(
          'adebimpe1/parakeet-ultra-ggml',
          ['ggml-parakeet-ultra-0.6b-q8_0.bin'],
          tags: ['parakeet', 'tdt', 'ggml', 'whisper.cpp', 'libparakeet'],
        ),
        _repo(
          'JoaoZaokk/orukeet-ggml',
          ['ggml-orukeet-f16.bin', 'ggml-orukeet-q5_0.bin'],
          tags: ['whisper.cpp', 'ggml', 'parakeet'],
        ),
        _repo('x/canary-1b-ggml', ['ggml-canary-1b.bin']),
        // A pack with both keeps only its Whisper file.
        _repo(
          'x/voice-pack',
          ['ggml-parakeet-tdt-q8_0.bin', 'ggml-large-v3-turbo-q5_0.bin'],
          tags: ['parakeet', 'whisper'],
        ),
        _repo('x/whisper-de', ['ggml-model-q5_0.bin'], tags: ['whisper']),
      ]);
      expect(hits.map((h) => h.repoId), ['x/voice-pack', 'x/whisper-de']);
      expect(isWhisperGgmlName('ggml-parakeet-tdt-0.6b-v3-q8_0.bin'), isFalse);
      expect(isWhisperGgmlName('ggml-large-v3-turbo.bin'), isTrue);
    });

    test('sherpa-onnx: onnx with tokens.txt, loose onnx dropped', () {
      final hits = parse([
        _repo('x/sherpa-onnx-paraformer-en', ['model.int8.onnx', 'tokens.txt']),
        _repo('x/loose-onnx', ['model.onnx']),
      ]);
      expect(hits.map((h) => h.repoId), ['x/sherpa-onnx-paraformer-en']);
      expect(hits.single.kinds, {HfSearchKind.sherpaOnnx});
      expect(hits.single.estimatedBytes, isNull);
    });

    test('streaming exports are left out: own models run offline', () {
      const transducer = [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      ];
      final hits = parse([
        _repo('k/sherpa-onnx-streaming-zipformer-de', transducer),
        _repo('v/asr-streaming-0.6b', transducer),
        _repo('a/scribe', [for (final f in transducer) 'asr/1120ms/int8/$f']),
        _repo('g/x-asr', [for (final f in transducer) 'chunk-160ms-model/$f']),
        _repo('m/turkish-stt-66m', transducer),
      ]);
      expect(hits.map((h) => h.repoId), ['m/turkish-stt-66m']);
    });

    test('GGUF: chat template, known architecture, no shards or helpers', () {
      const tpl = {'chat_template': '{{x}}', 'architecture': 'qwen3'};
      final hits = parse([
        _repo('ok/m', ['m-Q4_K_M.gguf'], gguf: {...tpl, 'total': 600000000}),
        _repo('base/m', ['m.gguf'], gguf: {'architecture': 'qwen3'}),
        _repo('new/m', ['m.gguf'], gguf: {...tpl, 'architecture': 'future9'}),
        _repo('split/m', [
          'm-00001-of-00002.gguf',
          'm-00002-of-00002.gguf',
          'mmproj-f16.gguf',
        ], gguf: tpl),
        _repo('helpers/m', [
          'm.imatrix.gguf',
          'lora/m-LoRA.gguf',
          'eagle3-m-Q8_0.gguf',
          'm-DFlash2-BF16.gguf',
          'm-draft-Q4_0.gguf',
          'ggml-vocab-m.gguf',
          'm-00001-of-00002.gguf',
        ], gguf: tpl),
      ], p: text);
      expect(hits.map((h) => h.repoId), ['ok/m']);
      expect(hits.single.architecture, 'qwen3');
    });

    test('a speech search never lists text models and the other way round', () {
      const tpl = {'chat_template': 't', 'architecture': 'llama'};
      final repos = [
        _repo('t/m', ['m-Q4_K_M.gguf'], gguf: tpl),
        _repo('s/m', ['ggml-tiny.bin']),
      ];
      expect(parse(repos).map((h) => h.repoId), ['s/m']);
      expect(parse(repos, p: text).map((h) => h.repoId), ['t/m']);
    });

    test('language tags are read, unknown codes and words dropped', () {
      final hit = parse([
        _repo(
          'l/m',
          ['ggml-tiny.bin'],
          tags: ['de', 'en', 'moe', 'gsq', 'multilingual', 'ggml'],
        ),
      ]).single;
      expect(hit.languages, ['de', 'en']);
      expect(hit.multilingual, isTrue);
    });

    test('gated repos stay visible but are marked', () {
      final hits = parse([
        _repo('g/m', ['ggml-tiny.bin'], gated: 'manual'),
      ]);
      expect(hits.single.gated, isTrue);
    });
  });

  group('license', () {
    test('only labelled, never filtered', () {
      final hits = parse([
        _repo('a/1', ['ggml-tiny.bin'], license: 'mit'),
        _repo('a/2', ['ggml-tiny.bin'], license: 'cc-by-nc-4.0'),
        _repo('a/3', ['ggml-tiny.bin']),
        _repo('a/4', ['ggml-tiny.bin'], license: 'llama3.1'),
      ]);
      expect(hits.map((h) => h.licenseKind), [
        HfLicenseKind.open,
        HfLicenseKind.nonCommercial,
        HfLicenseKind.unknown,
        HfLicenseKind.custom,
      ]);
    });

    test('named "other" license and license tag', () {
      expect(classifyLicense('other'), HfLicenseKind.unknown);
      expect(classifyLicense('apache-2.0'), HfLicenseKind.open);
      expect(classifyLicense('Research-only'), HfLicenseKind.nonCommercial);
      final hit = parse([
        {
          ..._repo('t/m', ['ggml-tiny.bin']),
          'cardData': null,
          'tags': ['license:apache-2.0'],
        },
      ]).single;
      expect(hit.license, 'apache-2.0');
    });
  });

  group('headers', () {
    test('next link only on the same endpoint', () {
      expect(
        parseNextLink(
          '<https://huggingface.co/api/models?search=a&cursor=xyz>; rel="next"',
        )?.queryParameters['cursor'],
        'xyz',
      );
      expect(
        parseNextLink('<https://evil.example/api/models>; rel="next"'),
        isNull,
      );
      expect(parseNextLink(null), isNull);
    });

    test('rate limit reset seconds', () {
      expect(
        parseRateLimitReset('"api";r=0;t=148'),
        const Duration(seconds: 148),
      );
    });
  });

  group('HfModelSearch', () {
    test('no request at all before consent', () async {
      final adapter = _Adapter((_) => _json([]));
      final dio = Dio()..httpClientAdapter = adapter;
      final search = HfModelSearch(hasConsent: () => false, dio: dio);
      await expectLater(
        search.search(const HfSearchQuery(purpose: speech)),
        throwsA(
          isA<HfSearchException>().having(
            (e) => e.error,
            'error',
            HfSearchError.noConsent,
          ),
        ),
      );
      expect(adapter.requests, isEmpty);
    });

    test('follows the next link until enough hits, then pages on', () async {
      var call = 0;
      final adapter = _Adapter((o) {
        call++;
        final runnable = [
          for (var i = 0; i < 5; i++)
            _repo(
              'p$call/m$i',
              ['m-Q4_K_M.gguf'],
              gguf: {'chat_template': 't', 'architecture': 'llama'},
            ),
        ];
        return _json(
          runnable,
          headers: {
            'link': [
              '<https://huggingface.co/api/models?cursor=c$call>; rel="next"',
            ],
          },
        );
      });
      final dio = Dio()..httpClientAdapter = adapter;
      final search = HfModelSearch(hasConsent: () => true, dio: dio);
      const query = HfSearchQuery(purpose: text);
      final first = await search.search(query);
      // 5 hits per page, 12 wanted: three pages in one load.
      expect(adapter.requests, hasLength(3));
      expect(first.hits, hasLength(15));
      expect(first.next, isNotNull);
      final second = await search.search(query, next: first.next);
      expect(adapter.requests[3].queryParameters['cursor'], 'c3');
      expect(second.hits.first.repoId, 'p4/m0');
      // The same page again comes from the session cache.
      await search.search(query);
      expect(adapter.requests, hasLength(6));
    });

    test('whisper.cpp and sherpa-onnx merge in sort order, each repo once, '
        'and no later load reorders the list', () async {
      // Two streams by downloads; "both/m" has files for both runtimes.
      final ggml = [
        _repo('w/a', ['ggml-tiny.bin'], downloads: 900),
        _repo('both/m', [
          'ggml-base.bin',
          'encoder.int8.onnx',
          'decoder.int8.onnx',
          'joiner.int8.onnx',
          'tokens.txt',
        ], downloads: 500),
        _repo('w/c', ['ggml-small.bin'], downloads: 100),
      ];
      final onnx = [
        _repo('sherpa-onnx-paraformer-x/a', [
          'model.int8.onnx',
          'tokens.txt',
        ], downloads: 700),
        _repo('both/m', [
          'ggml-base.bin',
          'encoder.int8.onnx',
          'decoder.int8.onnx',
          'joiner.int8.onnx',
          'tokens.txt',
        ], downloads: 500),
        _repo('sherpa-onnx-paraformer-x/b', [
          'model.int8.onnx',
          'tokens.txt',
        ], downloads: 50),
      ];
      final adapter = _Adapter(
        (o) => _json(
          o.uri.queryParametersAll['filter']!.contains('ggml') ? ggml : onnx,
        ),
      );
      final search = HfModelSearch(
        hasConsent: () => true,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final page = await search.search(const HfSearchQuery(purpose: speech));
      expect(page.hits.map((h) => h.repoId), [
        'w/a',
        'sherpa-onnx-paraformer-x/a',
        'both/m',
        'w/c',
        'sherpa-onnx-paraformer-x/b',
      ]);
      expect(page.hits[2].kinds, {
        HfSearchKind.whisperCpp,
        HfSearchKind.sherpaOnnx,
      });
      expect(page.next, isNull);
    });

    test('a hit waits until the other stream cannot outrank it', () async {
      // ggml page 1 ends at 600 and links on; onnx has a 650 hit on its
      // first page. Nothing below 650 may come out before onnx was read.
      final adapter = _Adapter((o) {
        final q = o.uri.queryParameters;
        if (q['filter'] == 'onnx' ||
            o.uri.queryParametersAll['filter']!.contains('onnx')) {
          return _json([
            _repo('sherpa-onnx-paraformer-x/o', [
              'model.int8.onnx',
              'tokens.txt',
            ], downloads: 650),
          ]);
        }
        if (q['cursor'] == 'g2') {
          return _json([
            _repo('w/late', ['ggml-tiny.bin'], downloads: 10),
          ]);
        }
        return _json(
          [
            _repo('w/top', ['ggml-tiny.bin'], downloads: 1000),
            _repo('w/mid', ['ggml-tiny.bin'], downloads: 600),
          ],
          headers: {
            'link': [
              '<https://huggingface.co/api/models?filter=ggml&sort=downloads'
                  '&cursor=g2>; rel="next"',
            ],
          },
        );
      });
      final search = HfModelSearch(
        hasConsent: () => true,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final page = await search.search(const HfSearchQuery(purpose: speech));
      expect(page.hits.map((h) => h.repoId), [
        'w/top',
        'sherpa-onnx-paraformer-x/o',
        'w/mid',
        'w/late',
      ]);
    });

    test('several languages are matched on the tags of each page', () async {
      final adapter = _Adapter(
        (o) => _json(
          o.uri.queryParametersAll['filter']!.contains('ggml')
              ? [
                  _repo('w/de', ['ggml-tiny.bin'], tags: ['de']),
                  _repo('w/fr', ['ggml-tiny.bin'], tags: ['fr']),
                  _repo('w/ja', ['ggml-tiny.bin'], tags: ['ja']),
                  _repo('w/none', ['ggml-tiny.bin']),
                ]
              : const [],
        ),
      );
      final search = HfModelSearch(
        hasConsent: () => true,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final page = await search.search(
        const HfSearchQuery(purpose: speech, languages: ['de', 'fr']),
      );
      expect(page.hits.map((h) => h.repoId), ['w/de', 'w/fr']);
    });

    test('under a size filter an unknown size is read from the repo, and a '
        'repo whose size stays unknown is left out', () async {
      const transducer = [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'joiner.int8.onnx',
        'tokens.txt',
      ];
      final adapter = _Adapter((o) {
        final path = o.uri.path;
        if (path.startsWith('/api/models/s/small/')) {
          return _json({
            'id': 's/small',
            'sha': '0123456789abcdef0123456789abcdef01234567',
            'siblings': [
              for (final f in transducer) {'rfilename': f, 'size': 50000000},
            ],
          });
        }
        if (path.startsWith('/api/models/s/big/')) {
          return _json({
            'id': 's/big',
            'sha': '0123456789abcdef0123456789abcdef01234567',
            'siblings': [
              for (final f in transducer) {'rfilename': f, 'size': 900000000},
            ],
          });
        }
        if (path.startsWith('/api/models/s/')) {
          return ResponseBody.fromString('{}', 500);
        }
        return _json(
          o.uri.queryParametersAll['filter']!.contains('onnx')
              ? [
                  _repo('s/small', transducer),
                  _repo('s/big', transducer),
                  _repo('s/broken', transducer),
                ]
              : const [],
        );
      });
      final search = HfModelSearch(
        hasConsent: () => true,
        dio: Dio()..httpClientAdapter = adapter,
      );
      final capped = await search.search(
        const HfSearchQuery(purpose: speech, size: HfSizeFilter.upTo1GB),
      );
      expect(capped.hits.map((h) => h.repoId), ['s/small']);
      expect(capped.hits.single.sizeExact, isTrue);
      expect(capped.hits.single.estimatedBytes, 200000000);
      final lookups = adapter.requests
          .where((u) => u.path.startsWith('/api/models/s/'))
          .toList();
      expect(lookups, hasLength(3));
      expect(lookups.first.queryParameters['blobs'], 'true');
      // Without a size filter nothing is looked up.
      adapter.requests.clear();
      final open = await HfModelSearch(
        hasConsent: () => true,
        dio: Dio()..httpClientAdapter = adapter,
      ).search(const HfSearchQuery(purpose: speech));
      expect(open.hits, hasLength(3));
      expect(
        adapter.requests.where((u) => u.path.startsWith('/api/models/s/')),
        isEmpty,
      );
    });

    test('429 is quiet: rate limited with the reset time', () async {
      final adapter = _Adapter(
        (_) => ResponseBody.fromString(
          '{}',
          429,
          headers: {
            'ratelimit': ['"api";r=0;t=120'],
          },
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final search = HfModelSearch(hasConsent: () => true, dio: dio);
      await expectLater(
        search.search(const HfSearchQuery(purpose: text)),
        throwsA(
          isA<HfSearchException>()
              .having((e) => e.error, 'error', HfSearchError.rateLimited)
              .having(
                (e) => e.retryAfter,
                'retryAfter',
                const Duration(seconds: 120),
              ),
        ),
      );
    });

    test('no connection is offline', () async {
      final adapter = _Adapter(
        (o) => throw DioException.connectionError(
          requestOptions: o,
          reason: 'offline',
        ),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final search = HfModelSearch(hasConsent: () => true, dio: dio);
      await expectLater(
        search.search(const HfSearchQuery(purpose: text)),
        throwsA(
          isA<HfSearchException>().having(
            (e) => e.error,
            'error',
            HfSearchError.offline,
          ),
        ),
      );
    });
  });

  group('detail and install', () {
    const files = [
      SourceFile(path: 'm-Q8_0.gguf', sizeBytes: 8000000000, sha256: _sha),
      SourceFile(path: 'm-Q4_K_M.gguf', sizeBytes: 4000000000, sha256: _sha),
      SourceFile(path: 'm-Q2_K.gguf', sizeBytes: 2000000000, sha256: _sha),
      SourceFile(path: 'mmproj-F16.gguf', sizeBytes: 500000000),
    ];

    test('options per quantisation, preselect the largest that fits', () {
      final options = installOptionsFor(
        files,
        repoId: 'o/m',
        kinds: const {HfSearchKind.gguf},
        ramMB: 16 * 1024,
      );
      expect(options.map((o) => o.label), ['Q2_K', 'Q4_K_M', 'Q8_0']);
      expect(options.map((o) => o.fit), [
        DeviceFit.comfortable,
        DeviceFit.comfortable,
        DeviceFit.tight,
      ]);
      expect(deviceFitFor(16000000000, 16 * 1024), DeviceFit.tooBig);
      expect(preferredOption(options)?.label, 'Q4_K_M');
      final noRam = installOptionsFor(
        files,
        repoId: 'o/m',
        kinds: const {HfSearchKind.gguf},
        ramMB: null,
      );
      expect(preferredOption(noRam)?.label, 'Q4_K_M');
    });

    test('a speech search never offers a GGUF of the repo', () {
      expect(
        installOptionsFor(
          files,
          repoId: 'o/m',
          kinds: const {HfSearchKind.whisperCpp, HfSearchKind.sherpaOnnx},
          ramMB: 8192,
        ),
        isEmpty,
      );
    });

    test('the draft is pinned and carries the LFS hash; another file is '
        'rejected', () {
      const commit = '0123456789abcdef0123456789abcdef01234567';
      const snapshot = HfRepoSnapshot(
        repoId: 'o/m',
        commit: commit,
        files: files,
      );
      final option = preferredOption(
        installOptionsFor(
          files,
          repoId: 'o/m',
          kinds: const {HfSearchKind.gguf},
          ramMB: 16 * 1024,
        ),
      )!;
      final draft = draftFromHfSnapshot(snapshot, option.candidate);
      final file = draft.files.single;
      expect(file.url, contains('/resolve/$commit/'));
      expect(file.sha256, _sha);
      expect(
        compareFileHash(expected: file.sha256, actual: 'b' * 64),
        HashCheck.changed,
      );
      expect(
        compareFileHash(expected: file.sha256, actual: _sha),
        HashCheck.matches,
      );
    });
  });

  test('consent is stored in user_models.json and off by default', () {
    expect(const UserModelsData().hfSearchConsent, isFalse);
    final data = UserModelsData.fromJson(
      jsonDecode(
        jsonEncode(const UserModelsData(hfSearchConsent: true).toJson()),
      ),
    );
    expect(data.hfSearchConsent, isTrue);
    expect(
      const UserModelsData().toJson().containsKey('hf_search_consent'),
      isFalse,
    );
  });
}
