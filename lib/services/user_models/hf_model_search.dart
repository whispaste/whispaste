/// The Hugging-Face-Suche of the model library (#2047): finds models on
/// huggingface.co that WhisPaste can run locally, before the existing own-
/// model path (#1789) resolves, pins, checks and installs one of them.
///
/// Read-only and anonymous: `GET https://huggingface.co/api/models` without a
/// token or cookie, on the fixed download allowlist. Nothing leaves the app
/// before the user agreed once in the "+" dialog ([HfModelSearch.hasConsent]);
/// without that agreement [HfModelSearch.search] throws before any request.
/// Search terms and picked models are never logged or counted.
///
/// Verified against live answers on 2026-11-19: `expand[]=siblings` lists the
/// file names (without sizes), `expand[]=gguf` gives `architecture`, `total`
/// (parameter count) and `chat_template`, the next page comes as a
/// `Link: <…cursor=…>; rel="next"` header, and the anonymous quota is
/// announced as `RateLimit: "api";r=<left>;t=<seconds to reset>`.
library;

import 'package:dio/dio.dart';

import '../../core/config/whisper_languages.dart';
import '../download_allowlist.dart';
import 'hf_repo_resolver.dart';
import 'user_model_address.dart';
import 'user_model.dart';
import 'user_model_detection.dart';

/// Which local runtime a search stream looks for. A search runs every kind
/// of its purpose at once (speech: whisper.cpp and sherpa-onnx, Smart Mode:
/// llama.cpp) and merges them, so nobody has to know the runtimes (#2193).
enum HfSearchKind {
  whisperCpp(UserModelRuntime.whispercpp, 'ggml'),
  sherpaOnnx(UserModelRuntime.sherpaOnnx, 'onnx'),
  gguf(UserModelRuntime.llamaCpp, 'gguf');

  const HfSearchKind(this.runtime, this.formatTag);
  final UserModelRuntime runtime;

  /// The Hub tag that marks repos in this format (`filter=`).
  final String formatTag;

  UserModelPurpose get purpose => runtime.purpose;

  static List<HfSearchKind> forPurpose(UserModelPurpose purpose) => [
    for (final k in values)
      if (k.purpose == purpose) k,
  ];
}

enum HfSearchSort {
  downloads('downloads'),
  likes('likes'),
  lastModified('lastModified');

  const HfSearchSort(this.apiValue);
  final String apiValue;
}

/// The size filter of the list. [fitsDevice] compares with this computer's
/// memory ([deviceFitFor]); the others are fixed caps on the smallest
/// runnable file. Under any filter but [any], a hit whose size stays unknown
/// is left out: a cap is a promise the list cannot keep for it (#2193).
enum HfSizeFilter {
  fitsDevice(null),
  upTo500MB(500 * 1000 * 1000),
  upTo1GB(1000 * 1000 * 1000),
  upTo2GB(2000 * 1000 * 1000),
  upTo4GB(4000 * 1000 * 1000),
  upTo8GB(8000 * 1000 * 1000),
  any(null);

  const HfSizeFilter(this.maxBytes);
  final int? maxBytes;

  /// The choices the dialog offers: "fits this computer" only with a known
  /// memory size.
  static List<HfSizeFilter> choices({required int? ramMB}) => [
    for (final f in values)
      if (f != fitsDevice || (ramMB != null && ramMB > 0)) f,
  ];

  /// The filter a new search starts with.
  static HfSizeFilter initial({required int? ramMB}) =>
      ramMB != null && ramMB > 0 ? fitsDevice : any;
}

/// Whether a hit of [bytes] (null = unknown) passes [filter] on a computer
/// with [ramMB] of memory.
bool hfSizeAccepts(HfSizeFilter filter, int? bytes, {required int? ramMB}) {
  if (filter == HfSizeFilter.any) return true;
  if (bytes == null || bytes <= 0) return false;
  if (filter == HfSizeFilter.fitsDevice) {
    return deviceFitFor(bytes, ramMB) != DeviceFit.tooBig;
  }
  return bytes <= filter.maxBytes!;
}

/// The languages a speech search starts with: the user's dictation languages
/// ([dictationLanguagesProvider]), as two-letter codes, in their order.
/// Text models get no language filter: their language tags on the Hub are
/// too sparse to filter by (most multilingual chat models list only `en` or
/// nothing).
List<String> hfInitialLanguages(
  UserModelPurpose purpose,
  List<String> dictationLanguages,
) {
  if (purpose != UserModelPurpose.speech) return const [];
  return [
    for (final code in {
      for (final l in dictationLanguages)
        l.split(RegExp('[-_]')).first.toLowerCase(),
    })
      if (code.isNotEmpty && code != 'auto') code,
  ];
}

/// The language codes a hit row names: those of [searched] it lists first
/// (they are why it is shown), then its others, each once.
List<String> hfDisplayLanguages(List<String> tags, List<String> searched) => [
  ...{
    for (final c in searched)
      if (tags.contains(c)) c,
    ...tags,
  },
];

/// One search as the dialog's field and filters describe it.
class HfSearchQuery {
  const HfSearchQuery({
    required this.purpose,
    this.text = '',
    this.languages = const [],
    this.sort = HfSearchSort.downloads,
    this.size = HfSizeFilter.any,
    this.ramMB,
  });

  final UserModelPurpose purpose;
  final String text;

  /// ISO codes; a hit must list at least one of them among its language
  /// tags. Empty = all languages.
  final List<String> languages;
  final HfSearchSort sort;
  final HfSizeFilter size;

  /// This computer's memory, for [HfSizeFilter.fitsDevice]. Never sent.
  final int? ramMB;

  List<HfSearchKind> get kinds => HfSearchKind.forPurpose(purpose);

  /// Results asked for per page. Larger than shown, because the client-side
  /// compatibility filter drops repos without a runnable file.
  static const pageSize = 50;

  /// One language goes to the Hub as a filter (`filter=de`, dense pages).
  /// Several are matched here on the language tags, because the Hub's
  /// filters only combine with "and".
  String? get _serverLanguage => languages.length == 1 ? languages.first : null;

  /// Whether [tags] (a repo's language tags) pass the language filter.
  bool acceptsLanguages(Iterable<String> tags) =>
      languages.isEmpty || tags.any(languages.contains);

  /// The first page's URL for one [kind]. Later pages follow the `Link`
  /// header verbatim.
  Uri toUri(HfSearchKind kind) {
    final text = this.text.trim();
    final params = <String, List<String>>{
      if (text.isNotEmpty) 'search': [text],
      'pipeline_tag': [
        kind.purpose == UserModelPurpose.speech
            ? 'automatic-speech-recognition'
            : 'text-generation',
      ],
      'filter': [kind.formatTag, ?_serverLanguage],
      'sort': [sort.apiValue],
      'direction': ['-1'],
      'limit': ['$pageSize'],
      'expand[]': [
        'siblings',
        'downloads',
        'likes',
        'lastModified',
        'gated',
        'cardData',
        'tags',
        if (kind == HfSearchKind.gguf) 'gguf',
      ],
    };
    return Uri(
      scheme: 'https',
      host: 'huggingface.co',
      path: '/api/models',
      queryParameters: params,
    );
  }

  HfSearchQuery copyWith({
    String? text,
    List<String>? languages,
    HfSearchSort? sort,
    HfSizeFilter? size,
  }) => HfSearchQuery(
    purpose: purpose,
    text: text ?? this.text,
    languages: languages ?? this.languages,
    sort: sort ?? this.sort,
    size: size ?? this.size,
    ramMB: ramMB,
  );
}

/// How freely a model may be used, as far as its card says. Only a label:
/// nothing is hidden for its license (maintainer decision on #2047).
enum HfLicenseKind { open, custom, nonCommercial, unknown }

const _openLicenses = {
  'mit',
  'apache-2.0',
  'bsd',
  'bsd-2-clause',
  'bsd-3-clause',
  'cc0-1.0',
  'cc-by-4.0',
  'cc-by-sa-4.0',
  'cc-by-3.0',
  'mpl-2.0',
  'gpl-3.0',
  'gpl-2.0',
  'lgpl-3.0',
  'agpl-3.0',
  'unlicense',
  'openrail',
  'artistic-2.0',
  'isc',
  'zlib',
  'wtfpl',
  'odc-by',
};

HfLicenseKind classifyLicense(String? license) {
  final l = license?.trim().toLowerCase() ?? '';
  if (l.isEmpty || l == 'unknown' || l == 'other') return HfLicenseKind.unknown;
  if (RegExp(r'(^|[-_ ])nc([-_ ]|$)').hasMatch(l) ||
      l.contains('non-commercial') ||
      l.contains('noncommercial') ||
      l.contains('research')) {
    return HfLicenseKind.nonCommercial;
  }
  return _openLicenses.contains(l) ? HfLicenseKind.open : HfLicenseKind.custom;
}

/// Architectures the pinned llama.cpp (`scripts/llama-cpp.pin`, v0.8.0)
/// loads as text models, from its `LLM_ARCH_NAMES`. Embedding, vision,
/// speech and helper architectures are left out. Update with the pin.
const Set<String> kLlamaCppTextArchitectures = {
  'afmoe', 'apertus', 'arcee', 'arctic', 'baichuan', 'bailingmoe', //
  'bailingmoe2', 'bailingmoe3', 'bitnet', 'bloom', 'chatglm', 'codeshell',
  'cohere2', 'cohere2moe', 'command-r', 'dbrx', 'deci', 'deepseek',
  'deepseek2', 'deepseek32', 'deepseek4', 'deepseek41', 'dots1', 'dots3note',
  'ernie4_5', 'ernie4_5-moe', 'exaone', 'exaone-moe', 'exaone4', 'falcon',
  'falcon-h1', 'flint', 'gemma', 'gemma2', 'gemma3', 'gemma3n', 'gemma4',
  'glm-dsa', 'glm4', 'glm4moe', 'glm5-next', 'gpt-oss', 'gpt2', 'gptj',
  'gptneox', 'granite', 'granite_swa', 'granitehybrid', 'granitemoe',
  'graniteswitch', 'grok', 'grovemoe', 'hunyuan-dense', 'hunyuan-moe',
  'hy_v3', 'hy_v4', 'internlm2', 'jais', 'jais2', 'jamba', 'k2-horizon',
  'kimi-k3', 'kimi-linear', 'kolibri1', 'laguna', 'lfm2', 'lfm2moe', 'lfm3',
  'llama', 'llama4', 'maincoder', 'maion-coder', 'mamba', 'mamba2', 'maple',
  'mellum', 'mimo2', 'minicpm', 'minicpm3', 'minimax-01', 'minimax-m2',
  'minimax-m3', 'mistral3', 'mistral4', 'mpt', 'muse-spark', 'nanbeige',
  'nemotron', 'nemotron_h', 'nemotron_h_moe', 'olmo', 'olmo2', 'olmoe',
  'openelm', 'orion', 'phi2', 'phi3', 'phimoe', 'plamo', 'plamo2', 'plamo3',
  'plm', 'qwen', 'qwen2', 'qwen2moe', 'qwen3', 'qwen35', 'qwen35moe',
  'qwen3moe', 'qwen3next', 'qwen4exp', 'refact', 'rwkv6', 'rwkv6qwen2',
  'rwkv7', 'arwkv7', 'seed_oss', 'smallthinker', 'smollm3', 'spark2_5',
  'stablelm', 'starcoder', 'starcoder2', 'step35', 'xverse',
};

/// One repo in the result list.
class HfModelHit {
  const HfModelHit({
    required this.repoId,
    required this.kinds,
    this.downloads = 0,
    this.likes = 0,
    this.lastModified,
    this.license,
    this.estimatedBytes,
    this.sizeExact = false,
    this.architecture,
    this.languages = const [],
    this.multilingual = false,
    this.gated = false,
  });

  final String repoId;

  /// The runtimes of the dialog's purpose this repo has a runnable file for.
  final Set<HfSearchKind> kinds;
  final int downloads;
  final int likes;
  final DateTime? lastModified;
  final String? license;

  /// Size of the smallest runnable file, or null when unknown. An estimate
  /// from names and parameter counts unless [sizeExact] (then it was read
  /// from the repo's file list).
  final int? estimatedBytes;
  final bool sizeExact;
  final String? architecture;

  /// The repo's language tags that are languages WhisPaste knows, in the
  /// repo's order.
  final List<String> languages;

  /// Tagged `multilingual` (often instead of a list).
  final bool multilingual;

  /// Needs a login on the site; shown, but not installable.
  final bool gated;

  String get author => repoId.split('/').first;
  String get name => repoId.split('/').skip(1).join('/');
  HfLicenseKind get licenseKind => classifyLicense(license);
  String get pageUrl => 'https://huggingface.co/$repoId';

  /// The value [sort] orders by, larger first.
  num sortKey(HfSearchSort sort) => switch (sort) {
    HfSearchSort.downloads => downloads,
    HfSearchSort.likes => likes,
    HfSearchSort.lastModified => lastModified?.millisecondsSinceEpoch ?? 0,
  };

  HfModelHit withSize(int? bytes, {required bool exact}) => HfModelHit(
    repoId: repoId,
    kinds: kinds,
    downloads: downloads,
    likes: likes,
    lastModified: lastModified,
    license: license,
    estimatedBytes: bytes,
    sizeExact: exact,
    architecture: architecture,
    languages: languages,
    multilingual: multilingual,
    gated: gated,
  );
}

/// One page of hits and where the next one is.
class HfSearchPage {
  const HfSearchPage({required this.hits, this.next});
  final List<HfModelHit> hits;

  /// Where the following load continues; null at the end of the list.
  final HfSearchCursor? next;
}

/// Reads one API page found through [kind], keeping only repos with a file
/// a runtime of [purpose] can open. Neither language nor size are applied
/// here (see [HfModelSearch]). Pure, for tests.
List<HfModelHit> parseHfSearchResults(
  Object? json, {
  required UserModelPurpose purpose,
}) {
  if (json is! List) throw const HfSearchException(HfSearchError.badResponse);
  final hits = <HfModelHit>[];
  for (final m in json) {
    if (m is! Map) continue;
    final id = m['id'];
    if (id is! String || !id.contains('/')) continue;
    final siblings = [
      for (final s in (m['siblings'] is List ? m['siblings'] as List : []))
        if (s is Map && s['rfilename'] is String)
          SourceFile(path: s['rfilename'] as String),
    ];
    final gguf = m['gguf'] is Map ? m['gguf'] as Map : const {};
    final architecture = gguf['architecture'] is String
        ? gguf['architecture'] as String
        : null;
    final tags = [
      for (final t in (m['tags'] is List ? m['tags'] as List : []))
        if (t is String) t.toLowerCase(),
    ];
    final kinds = {
      for (final k in HfSearchKind.forPurpose(purpose))
        if (_runnable(k, id, siblings, tags, gguf, architecture)) k,
    };
    if (kinds.isEmpty) continue;
    int? estimate;
    for (final k in kinds) {
      final e = _estimateBytes(k, id, siblings, tags, gguf);
      if (e != null && (estimate == null || e < estimate)) estimate = e;
    }
    final gated = m['gated'];
    hits.add(
      HfModelHit(
        repoId: id,
        kinds: kinds,
        downloads: m['downloads'] is int ? m['downloads'] as int : 0,
        likes: m['likes'] is int ? m['likes'] as int : 0,
        lastModified: m['lastModified'] is String
            ? DateTime.tryParse(m['lastModified'] as String)
            : null,
        license: _license(m),
        estimatedBytes: estimate,
        architecture: architecture,
        languages: [
          for (final t in tags)
            if (whisperLanguages.containsKey(t)) t,
        ],
        multilingual: tags.contains('multilingual'),
        gated: gated == true || gated == 'auto' || gated == 'manual',
      ),
    );
  }
  return hits;
}

/// The sort value of the last repo on a raw page (runnable or not): every
/// repo still to come on this stream sorts at or below it.
num? lastSortKey(Object? json, HfSearchSort sort) {
  if (json is! List || json.isEmpty) return null;
  final m = json.last;
  if (m is! Map) return null;
  return switch (sort) {
    HfSearchSort.downloads => m['downloads'] is int ? m['downloads'] as int : 0,
    HfSearchSort.likes => m['likes'] is int ? m['likes'] as int : 0,
    HfSearchSort.lastModified =>
      (m['lastModified'] is String
                  ? DateTime.tryParse(m['lastModified'] as String)
                  : null)
              ?.millisecondsSinceEpoch ??
          0,
  };
}

/// Speech architectures that also ship as `ggml-*.bin` (Parakeet/NeMo for
/// libparakeet and other ggml ports) but that whisper.cpp's
/// `whisper_init` cannot load. Repo tags or names with one of these mark the
/// repo; a file in it then needs a Whisper name of its own (#2193).
final _otherSpeechArchitecture = RegExp(
  r'parakeet|canary|fastconformer|moonshine|sensevoice|sense-voice|'
  r'wav2vec|voxtral|nemotron|(^|[-_/ ])(tdt|ctc|nemo|rnnt)([-_/ .]|\d|$)',
);

/// A Whisper size or the word "whisper" in a name: the file is a Whisper
/// model even in a repo that also holds other architectures.
final _whisperEvidence = RegExp(r'whisper|tiny|base|small|medium|large|turbo');

bool _runnable(
  HfSearchKind kind,
  String repoId,
  List<SourceFile> files,
  List<String> tags,
  Map<dynamic, dynamic> gguf,
  String? architecture,
) {
  switch (kind) {
    case HfSearchKind.whisperCpp:
      return _whisperFiles(repoId, files, tags).isNotEmpty;
    case HfSearchKind.sherpaOnnx:
      return detectUserModelCandidates(
        files,
        repoName: repoId,
      ).any((c) => c.runtime == UserModelRuntime.sherpaOnnx);
    case HfSearchKind.gguf:
      final template = gguf['chat_template'];
      return template is String &&
          template.trim().isNotEmpty &&
          architecture != null &&
          kLlamaCppTextArchitectures.contains(architecture) &&
          files.any((f) => isUsableGgufName(f.baseName.toLowerCase()));
  }
}

/// The `ggml-*.bin` files of a repo that whisper.cpp can load: a Whisper
/// file name ([isWhisperGgmlName]), and in a repo whose tags or name point
/// to another speech architecture only files that name Whisper themselves.
List<SourceFile> _whisperFiles(
  String repoId,
  List<SourceFile> files,
  List<String> tags,
) {
  final otherArchitecture =
      _otherSpeechArchitecture.hasMatch(repoId.toLowerCase()) ||
      tags.any(_otherSpeechArchitecture.hasMatch) ||
      tags.contains('libparakeet');
  return [
    for (final f in files)
      if (isWhisperGgmlName(f.baseName.toLowerCase()) &&
          (!otherArchitecture ||
              _whisperEvidence.hasMatch(f.baseName.toLowerCase())))
        f,
  ];
}

/// whisper.cpp model sizes at full precision (f16), by the size in the name.
/// More specific names first.
const _whisperSizes = <(String, int)>[
  ('turbo', 1620 * 1000 * 1000),
  ('distil-large', 1520 * 1000 * 1000),
  ('large', 3100 * 1000 * 1000),
  ('medium', 1530 * 1000 * 1000),
  ('small', 488 * 1000 * 1000),
  ('base', 148 * 1000 * 1000),
  ('tiny', 78 * 1000 * 1000),
];

/// Bytes per f16 byte for a quantisation (whisper.cpp files) and bytes per
/// parameter (GGUF), measured on published files.
double _whisperQuantFactor(String? quant) => switch (quant?.toLowerCase()) {
  null || 'f16' || 'fp16' || 'bf16' => 1,
  'f32' => 2,
  final q when q.startsWith('q8') || q == 'int8' => 0.54,
  final q when q.startsWith('q6') => 0.43,
  final q when q.startsWith('q5') => 0.36,
  final q when q.startsWith('q4') || q.startsWith('iq4') => 0.31,
  final q when q.startsWith('q3') || q.startsWith('iq3') => 0.26,
  _ => 0.22,
};

double _ggufBytesPerParam(String? quant) => switch (quant?.toLowerCase()) {
  null => 0.6,
  'f32' => 4,
  'f16' || 'fp16' || 'bf16' => 2,
  final q when q.startsWith('q8') => 1.06,
  final q when q.startsWith('q6') => 0.82,
  final q when q.startsWith('q5') => 0.7,
  final q when q.startsWith('q4') || q.startsWith('iq4') => 0.6,
  final q when q.startsWith('q3') || q.startsWith('iq3') => 0.45,
  final q when q.startsWith('q2') || q.startsWith('iq2') => 0.35,
  _ => 0.25,
};

/// Rough size of the smallest runnable file of [kind] from the file names
/// (whisper.cpp) or the parameter count (GGUF); null when the list does not
/// say (sherpa-onnx, unnamed Whisper files). [HfModelSearch] then reads the
/// real size when a size filter needs it.
int? _estimateBytes(
  HfSearchKind kind,
  String repoId,
  List<SourceFile> files,
  List<String> tags,
  Map<dynamic, dynamic> gguf,
) {
  switch (kind) {
    case HfSearchKind.whisperCpp:
      int? best;
      final repo = repoId.toLowerCase();
      for (final f in _whisperFiles(repoId, files, tags)) {
        final n = f.baseName.toLowerCase();
        final tier =
            _tierOf(n) ?? _tierOf(repo.substring(repo.indexOf('/') + 1));
        if (tier == null) continue;
        final bytes = (tier * _whisperQuantFactor(quantisationOf(n))).round();
        if (best == null || bytes < best) best = bytes;
      }
      return best;
    case HfSearchKind.sherpaOnnx:
      return null;
    case HfSearchKind.gguf:
      final params = gguf['total'];
      if (params is! int || params <= 0) return null;
      int? best;
      for (final f in files) {
        final n = f.baseName.toLowerCase();
        if (!isUsableGgufName(n)) continue;
        final bytes = (params * _ggufBytesPerParam(quantisationOf(n))).round();
        if (best == null || bytes < best) best = bytes;
      }
      return best;
  }
}

int? _tierOf(String name) {
  for (final (word, bytes) in _whisperSizes) {
    if (name.contains(word)) return bytes;
  }
  return null;
}

String? _license(Map<dynamic, dynamic> m) {
  final card = m['cardData'];
  if (card is Map) {
    final l = card['license'];
    final name = card['license_name'];
    if (l == 'other' && name is String && name.trim().isNotEmpty) {
      return name.trim();
    }
    if (l is String && l.trim().isNotEmpty) return l.trim();
    if (l is List && l.isNotEmpty) return l.whereType<String>().join(', ');
  }
  final tags = m['tags'];
  if (tags is List) {
    for (final t in tags) {
      if (t is String && t.startsWith('license:')) return t.substring(8);
    }
  }
  return null;
}

/// The `rel="next"` URL of a `Link` header, only when it stays on the same
/// API endpoint.
Uri? parseNextLink(String? header) {
  if (header == null) return null;
  final match = RegExp(r'<([^>]+)>\s*;\s*rel="?next"?').firstMatch(header);
  if (match == null) return null;
  final uri = Uri.tryParse(match.group(1)!);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'huggingface.co' ||
      uri.path != '/api/models') {
    return null;
  }
  return uri;
}

/// Seconds until the anonymous quota resets, from `RateLimit: …;t=<s>`.
Duration? parseRateLimitReset(String? header) {
  if (header == null) return null;
  final t = RegExp(r't=(\d+)').firstMatch(header);
  if (t == null) return null;
  return Duration(seconds: int.parse(t.group(1)!));
}

enum HfSearchError {
  /// The user has not agreed to searching Hugging Face; nothing was sent.
  noConsent,

  /// No connection; the address/file path still works.
  offline,

  /// Too many anonymous requests; [HfSearchException.retryAfter] says when.
  rateLimited,
  badResponse,
}

class HfSearchException implements Exception {
  const HfSearchException(this.error, {this.retryAfter});
  final HfSearchError error;
  final Duration? retryAfter;

  @override
  String toString() => 'HfSearchException(${error.name})';
}

/// Where one stream (one [HfSearchKind]) of a search stands.
class _StreamState {
  _StreamState(this.kind, this.next);

  final HfSearchKind kind;

  /// The next page to read; null once the stream is at its end.
  Uri? next;
  bool started = false;

  /// Sort value of the last repo read: nothing later on this stream sorts
  /// above it.
  num frontier = double.infinity;

  /// Hits read but not handed out yet (sorted, larger first).
  final List<HfModelHit> buffer = [];

  bool get done => started && next == null;

  _StreamState copy() => _StreamState(kind, next)
    ..started = started
    ..frontier = frontier
    ..buffer.addAll(buffer);
}

/// Opaque position in a merged search, from [HfSearchPage.next].
class HfSearchCursor {
  HfSearchCursor._(this._streams, this._seen);
  final List<_StreamState> _streams;
  final Set<String> _seen;

  HfSearchCursor _copy() =>
      HfSearchCursor._([for (final s in _streams) s.copy()], {..._seen});

  bool get _finished => _streams.every((s) => s.done && s.buffer.isEmpty);
}

/// A raw page as read from the Hub, before language and size.
class _RawPage {
  const _RawPage(this.hits, this.next, this.lastKey);
  final List<HfModelHit> hits;
  final Uri? next;
  final num? lastKey;
}

/// Runs searches against the Hub. One instance per dialog: it keeps the
/// pages and repo sizes of this session, so going back to a query asks
/// nothing again.
///
/// A search reads one stream per runtime of its purpose and merges them in
/// sort order: a hit is handed out only when no stream can still bring a
/// hit that sorts above it, so the endless list never reorders (#2193).
class HfModelSearch {
  HfModelSearch({required this.hasConsent, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'User-Agent': 'WhisPaste'},
            ),
          ),
      _ownsDio = dio == null;

  /// Read before every request; false means nothing is sent.
  final bool Function() hasConsent;
  final Dio _dio;
  final bool _ownsDio;
  final Map<String, _RawPage> _cache = {};
  final Map<String, Future<HfRepoSnapshot?>> _snapshots = {};

  /// A load hands back at least this many hits unless [maxRequestsPerLoad]
  /// list requests are used up or every stream is at its end.
  static const minHitsPerLoad = 12;
  static const maxRequestsPerLoad = 4;

  /// Unknown sizes read per list page at most (one small request each).
  static const maxSizeLookupsPerPage = 8;

  /// The first hits of [query], or the next ones after [next] (from the
  /// previous [HfSearchPage.next]).
  Future<HfSearchPage> search(
    HfSearchQuery query, {
    HfSearchCursor? next,
  }) async {
    if (!hasConsent()) throw const HfSearchException(HfSearchError.noConsent);
    final cursor =
        next?._copy() ??
        HfSearchCursor._([
          for (final k in query.kinds) _StreamState(k, query.toUri(k)),
        ], {});
    final out = <HfModelHit>[];
    var requests = 0;
    while (true) {
      _emitSafe(cursor, query.sort, out);
      if (out.length >= minHitsPerLoad) break;
      final open = cursor._streams.where((s) => !s.done).toList();
      if (open.isEmpty) break;
      if (requests >= maxRequestsPerLoad) break;
      // The stream that holds the others back: the one whose next repo may
      // still sort highest.
      open.sort((a, b) => b.frontier.compareTo(a.frontier));
      await _read(open.first, query);
      requests++;
    }
    return HfSearchPage(hits: out, next: cursor._finished ? null : cursor);
  }

  /// Moves every buffered hit that nothing unread can outrank into [out],
  /// best first, each repo once.
  static void _emitSafe(
    HfSearchCursor cursor,
    HfSearchSort sort,
    List<HfModelHit> out,
  ) {
    while (true) {
      _StreamState? best;
      for (final s in cursor._streams) {
        if (s.buffer.isEmpty) continue;
        if (best == null ||
            s.buffer.first.sortKey(sort) > best.buffer.first.sortKey(sort)) {
          best = s;
        }
      }
      if (best == null) return;
      final key = best.buffer.first.sortKey(sort);
      final blocked = cursor._streams.any(
        (s) => !s.done && s.buffer.isEmpty && s.frontier > key,
      );
      if (blocked) return;
      final hit = best.buffer.removeAt(0);
      if (cursor._seen.add(hit.repoId)) out.add(hit);
    }
  }

  Future<void> _read(_StreamState stream, HfSearchQuery query) async {
    final page = await _page(stream.next!, query.purpose);
    stream.started = true;
    stream.next = page.next;
    stream.frontier = page.lastKey ?? 0;
    final wanted = [
      for (final h in page.hits)
        if (query.acceptsLanguages(h.languages)) h,
    ];
    final sized = await _withSizes(wanted, query);
    stream.buffer.addAll([
      for (final h in sized)
        if (hfSizeAccepts(query.size, h.estimatedBytes, ramMB: query.ramMB)) h,
    ]);
  }

  /// Reads the real size of hits the list could not estimate, but only
  /// while a size filter needs it (the detail reads it anyway). The request
  /// is the one the detail makes for the repo, and its answer is kept for it.
  Future<List<HfModelHit>> _withSizes(
    List<HfModelHit> hits,
    HfSearchQuery query,
  ) async {
    if (query.size == HfSizeFilter.any) return hits;
    var lookups = 0;
    return Future.wait([
      for (final h in hits)
        if (h.estimatedBytes != null || h.gated)
          Future.value(h)
        else if (lookups++ < maxSizeLookupsPerPage)
          _exactSize(h)
        else
          Future.value(h),
    ]);
  }

  Future<HfModelHit> _exactSize(HfModelHit hit) async {
    final repo = await snapshot(hit);
    if (repo == null) return hit;
    final options = installOptionsFor(
      repo.files,
      repoId: repo.repoId,
      kinds: hit.kinds,
      ramMB: null,
    ).where((o) => o.sizeBytes > 0);
    if (options.isEmpty) return hit;
    return hit.withSize(options.first.sizeBytes, exact: true);
  }

  /// The repo's file list (pinned commit, sizes, hashes) for [hit], read
  /// once per dialog; null when it cannot be read. The detail view uses the
  /// same answer.
  Future<HfRepoSnapshot?> snapshot(HfModelHit hit) {
    if (!hasConsent()) return Future.value();
    return _snapshots.putIfAbsent(hit.repoId, () async {
      try {
        return await resolveHfRepo(
          HuggingFaceAddress(owner: hit.author, repo: hit.name),
          dio: _dio,
        );
      } on Object {
        // Unreadable now (offline, gated, odd answer): the size stays
        // unknown and the detail asks again with its own error message.
        _snapshots.remove(hit.repoId);
        return null;
      }
    });
  }

  Future<_RawPage> _page(Uri url, UserModelPurpose purpose) async {
    final key = url.toString();
    final cached = _cache[key];
    if (cached != null) return cached;
    if (!hasConsent()) throw const HfSearchException(HfSearchError.noConsent);
    try {
      final response = await getWithAllowlistedRedirects<Object?>(
        _dio,
        key,
        options: Options(responseType: ResponseType.json),
      );
      final next = parseNextLink(response.headers.value('link'));
      final data = response.data;
      final page = _RawPage(
        parseHfSearchResults(data, purpose: purpose),
        // An empty page ends the stream even if the Hub links on.
        data is List && data.isEmpty ? null : next,
        lastSortKey(data, _sortOf(url)),
      );
      _cache[key] = page;
      return page;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 429) {
        throw HfSearchException(
          HfSearchError.rateLimited,
          retryAfter:
              parseRateLimitReset(e.response?.headers.value('ratelimit')) ??
              _retryAfter(e.response?.headers.value('retry-after')),
        );
      }
      if (status != null) {
        throw const HfSearchException(HfSearchError.badResponse);
      }
      throw const HfSearchException(HfSearchError.offline);
    } on DownloadUrlRejectedException {
      throw const HfSearchException(HfSearchError.badResponse);
    }
  }

  /// The sort of a page URL (also of `Link` pages, which keep it).
  static HfSearchSort _sortOf(Uri url) {
    final v = url.queryParameters['sort'];
    return HfSearchSort.values.firstWhere(
      (s) => s.apiValue == v,
      orElse: () => HfSearchSort.downloads,
    );
  }

  void close() {
    if (_ownsDio) _dio.close();
  }
}

Duration? _retryAfter(String? header) {
  final s = int.tryParse(header ?? '');
  return s == null ? null : Duration(seconds: s);
}

/// How well a file fits this computer's memory.
enum DeviceFit { comfortable, tight, tooBig, unknown }

/// [fileBytes] against [ramMB] (total RAM; on Apple Silicon that is also the
/// GPU memory). A model needs about its file size plus a working margin.
DeviceFit deviceFitFor(int fileBytes, int? ramMB) {
  if (ramMB == null || ramMB <= 0 || fileBytes <= 0) return DeviceFit.unknown;
  final ram = ramMB * 1024 * 1024;
  final need = fileBytes * 1.2 + 512 * 1024 * 1024;
  if (need <= ram * 0.5) return DeviceFit.comfortable;
  if (need <= ram * 0.8) return DeviceFit.tight;
  return DeviceFit.tooBig;
}

/// One installable choice in the detail view: a quantisation (GGML/GGUF) or
/// a sherpa-onnx file set.
class HfInstallOption {
  const HfInstallOption({
    required this.candidate,
    required this.label,
    required this.sizeBytes,
    required this.fit,
  });

  final UserModelCandidate candidate;

  /// The quantisation (`Q4_K_M`, `q5_0`, …) or the main file name.
  final String label;
  final int sizeBytes;
  final DeviceFit fit;
}

final _quantPattern = RegExp(
  r'(iq\d_[a-z]+|q\d_k_[sml]|q\d_k|q\d_\d|q\d|f16|f32|bf16|fp16|int8)',
  caseSensitive: false,
);

/// The quantisation in a file name, upper-cased for GGUF, or null.
String? quantisationOf(String fileName) {
  final m = _quantPattern.allMatches(fileName.toLowerCase());
  if (m.isEmpty) return null;
  return m.last.group(0)!.toUpperCase();
}

/// The runnable choices in [files] for the runtimes [kinds], sorted small to
/// large.
List<HfInstallOption> installOptionsFor(
  List<SourceFile> files, {
  required String repoId,
  required Set<HfSearchKind> kinds,
  required int? ramMB,
}) {
  final runtimes = {for (final k in kinds) k.runtime};
  final options = <HfInstallOption>[
    for (final c in detectUserModelCandidates(files, repoName: repoId))
      if (runtimes.contains(c.runtime))
        HfInstallOption(
          candidate: c,
          label: c.runtime == UserModelRuntime.sherpaOnnx
              ? c.label
              : quantisationOf(c.files.first.source.baseName) ?? c.label,
          sizeBytes: c.files.fold(0, (s, f) => s + f.source.sizeBytes),
          fit: deviceFitFor(
            c.files.fold(0, (s, f) => s + f.source.sizeBytes),
            ramMB,
          ),
        ),
  ]..sort((a, b) => a.sizeBytes.compareTo(b.sizeBytes));
  return options;
}

/// The option to pre-select: the largest that fits comfortably, else the
/// largest that fits at all, else the smallest. Null for an empty list.
HfInstallOption? preferredOption(List<HfInstallOption> options) {
  if (options.isEmpty) return null;
  for (final want in [DeviceFit.comfortable, DeviceFit.tight]) {
    final fitting = options.where((o) => o.fit == want).toList();
    if (fitting.isNotEmpty) return fitting.last;
  }
  if (options.every((o) => o.fit == DeviceFit.unknown)) {
    // No RAM figure: the usual balance the detection ranks first.
    return options.firstWhere(
      (o) => o.label == 'Q4_K_M',
      orElse: () => options.first,
    );
  }
  return options.first;
}
