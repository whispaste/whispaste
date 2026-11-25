/// Sampling settings per local text model (#2204): which values Smart Mode
/// generates with, where a vendor recommendation comes from, and the user's
/// choice per model id.
///
/// WhisPaste's own values (temperature 0.3, top_p 0.95, top_k 64) are the
/// default for every model: they were measured for faithful rewriting
/// (Smart-Mode-v2 spike). A vendor recommendation (GGUF `general.sampling.*`)
/// is offered as an explicit choice, never applied silently, because vendor
/// values are usually tuned for chat (temperature 1.0).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The values one generation runs with.
class SmartModeSampling {
  const SmartModeSampling({
    required this.temperature,
    required this.topK,
    required this.topP,
    this.minP = 0,
    this.repeatPenalty = 1,
  });

  /// "Freiheit beim Formulieren": 0 always takes the most likely word.
  final double temperature;

  /// How many candidate words are considered; 0 = no limit.
  final int topK;

  /// Share of probability the candidates cover; 1 = no limit.
  final double topP;

  /// Drops candidates below this share of the best one; 0 = off.
  final double minP;

  /// Penalty for repeating recent words; 1 = off.
  final double repeatPenalty;

  /// WhisPaste's measured rewrite values. Identical native sampler chain to
  /// the one every model ran with before #2204.
  static const whispaste = SmartModeSampling(
    temperature: 0.3,
    topK: 64,
    topP: 0.95,
  );

  /// Tokens the repeat penalty looks back over (llama.cpp's default).
  static const penaltyLastN = 64;

  SmartModeSampling copyWith({
    double? temperature,
    int? topK,
    double? topP,
    double? minP,
    double? repeatPenalty,
  }) => SmartModeSampling(
    temperature: temperature ?? this.temperature,
    topK: topK ?? this.topK,
    topP: topP ?? this.topP,
    minP: minP ?? this.minP,
    repeatPenalty: repeatPenalty ?? this.repeatPenalty,
  );

  /// Every value clamped into [SamplingRange]; non-finite values fall back
  /// to [whispaste].
  SmartModeSampling clamped() => SmartModeSampling(
    temperature: SamplingRange.temperature.clamp(
      temperature,
      whispaste.temperature,
    ),
    topK: SamplingRange.topK.clamp(topK.toDouble(), 64).round(),
    topP: SamplingRange.topP.clamp(topP, whispaste.topP),
    minP: SamplingRange.minP.clamp(minP, 0),
    repeatPenalty: SamplingRange.repeatPenalty.clamp(repeatPenalty, 1),
  );

  Map<String, Object?> toJson() => {
    'temperature': temperature,
    'top_k': topK,
    'top_p': topP,
    'min_p': minP,
    'repeat_penalty': repeatPenalty,
  };

  static SmartModeSampling? fromJson(Object? json) {
    if (json is! Map) return null;
    double? d(String k) => json[k] is num ? (json[k] as num).toDouble() : null;
    final t = d('temperature');
    final k = d('top_k');
    final p = d('top_p');
    if (t == null || k == null || p == null) return null;
    return SmartModeSampling(
      temperature: t,
      topK: k.round(),
      topP: p,
      minP: d('min_p') ?? 0,
      repeatPenalty: d('repeat_penalty') ?? 1,
    ).clamped();
  }

  @override
  bool operator ==(Object other) =>
      other is SmartModeSampling &&
      other.temperature == temperature &&
      other.topK == topK &&
      other.topP == topP &&
      other.minP == minP &&
      other.repeatPenalty == repeatPenalty;

  @override
  int get hashCode => Object.hash(temperature, topK, topP, minP, repeatPenalty);

  @override
  String toString() =>
      'SmartModeSampling(t=$temperature, k=$topK, p=$topP, '
      'minP=$minP, rep=$repeatPenalty)';
}

/// Allowed range of one value. Values outside are clamped, so a typo or an
/// odd vendor value can never break generation.
class SamplingRange {
  const SamplingRange(this.min, this.max);
  final double min;
  final double max;

  static const temperature = SamplingRange(0, 2);
  static const topK = SamplingRange(0, 200);
  static const topP = SamplingRange(0.05, 1);
  static const minP = SamplingRange(0, 0.5);
  static const repeatPenalty = SamplingRange(1, 1.5);

  bool contains(double v) => v.isFinite && v >= min && v <= max;

  double clamp(double v, double fallback) {
    if (!v.isFinite) return fallback;
    return v < min ? min : (v > max ? max : v);
  }
}

/// Which values a model runs with.
enum SamplingPreset {
  /// WhisPaste's rewrite values ([SmartModeSampling.whispaste]).
  whispaste('whispaste'),

  /// The vendor's recommendation from the model file.
  vendor('vendor'),

  /// The user's own values.
  custom('custom');

  const SamplingPreset(this.value);
  final String value;

  static SamplingPreset fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return whispaste;
  }
}

/// A vendor recommendation and where it came from. Only the values the
/// vendor named are set; the rest stay at WhisPaste's values.
class SamplingRecommendation {
  const SamplingRecommendation({required this.values, required this.keys});

  final SmartModeSampling values;

  /// The fields the vendor named (`temperature`, `top_k`, `top_p`, `min_p`,
  /// `repeat_penalty`).
  final Set<String> keys;
}

/// The user's choice for one model.
class ModelSamplingChoice {
  const ModelSamplingChoice({
    this.preset = SamplingPreset.whispaste,
    this.custom,
  });

  final SamplingPreset preset;

  /// The user's own values, kept when switching to another preset.
  final SmartModeSampling? custom;

  Map<String, Object?> toJson() => {
    'preset': preset.value,
    'custom': ?custom?.toJson(),
  };

  static ModelSamplingChoice fromJson(Object? json) {
    if (json is! Map) return const ModelSamplingChoice();
    return ModelSamplingChoice(
      preset: SamplingPreset.fromValue(json['preset']),
      custom: SmartModeSampling.fromJson(json['custom']),
    );
  }
}

/// Model id the bundled catalog text model is stored under.
const kCatalogTextModelSamplingId = 'gemma';

/// Parses the stored map (`smart_mode_model_sampling`). Damaged JSON yields
/// an empty map: every model then runs with WhisPaste's values.
Map<String, ModelSamplingChoice> modelSamplingFromJson(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final e in decoded.entries)
        if (e.key is String)
          e.key as String: ModelSamplingChoice.fromJson(e.value),
    };
  } on FormatException {
    return const {};
  }
}

String modelSamplingToJson(Map<String, ModelSamplingChoice> map) => map.isEmpty
    ? ''
    : jsonEncode({for (final e in map.entries) e.key: e.value.toJson()});

/// The values a model runs with. Without a stored choice, or with "vendor"
/// but no recommendation, that is [SmartModeSampling.whispaste]: catalog
/// models keep their measured behaviour.
SmartModeSampling effectiveSampling(
  ModelSamplingChoice? choice,
  SamplingRecommendation? recommendation,
) {
  switch (choice?.preset ?? SamplingPreset.whispaste) {
    case SamplingPreset.whispaste:
      return SmartModeSampling.whispaste;
    case SamplingPreset.vendor:
      return recommendation?.values ?? SmartModeSampling.whispaste;
    case SamplingPreset.custom:
      return choice?.custom?.clamped() ??
          recommendation?.values ??
          SmartModeSampling.whispaste;
  }
}

// ---------------------------------------------------------------------------
// GGUF `general.sampling.*` (llama.cpp's convention, src/llama-arch.cpp of
// the pinned llama.cpp: general.sampling.temp, .top_k, .top_p, .min_p,
// .penalty_repeat, read by common.cpp the same way)
// ---------------------------------------------------------------------------

const _ggufSamplingKeys = {
  'general.sampling.temp': 'temperature',
  'general.sampling.top_k': 'top_k',
  'general.sampling.top_p': 'top_p',
  'general.sampling.min_p': 'min_p',
  'general.sampling.penalty_repeat': 'repeat_penalty',
};

/// Builds a recommendation from named vendor values. Values outside
/// [SamplingRange] are ignored (not clamped): a value we cannot trust is not
/// a recommendation. Null when nothing usable is left.
SamplingRecommendation? recommendationFrom(Map<String, double> named) {
  var v = SmartModeSampling.whispaste;
  final keys = <String>{};
  for (final e in named.entries) {
    final x = e.value;
    switch (e.key) {
      case 'temperature' when SamplingRange.temperature.contains(x):
        v = v.copyWith(temperature: x);
      case 'top_k'
          when SamplingRange.topK.contains(x) && x == x.roundToDouble():
        v = v.copyWith(topK: x.round());
      case 'top_p' when SamplingRange.topP.contains(x):
        v = v.copyWith(topP: x);
      case 'min_p' when SamplingRange.minP.contains(x):
        v = v.copyWith(minP: x);
      case 'repeat_penalty' when SamplingRange.repeatPenalty.contains(x):
        v = v.copyWith(repeatPenalty: x);
      default:
        continue;
    }
    keys.add(e.key);
  }
  if (keys.isEmpty) return null;
  return SamplingRecommendation(values: v, keys: keys);
}

final Map<String, (int, SamplingRecommendation?)> _ggufCache = {};

/// [readGgufSampling], remembered per path and file size (a replaced file
/// is read again).
SamplingRecommendation? cachedGgufSampling(String path) {
  final int size;
  try {
    size = File(path).lengthSync();
  } on FileSystemException {
    return null;
  }
  final hit = _ggufCache[path];
  if (hit != null && hit.$1 == size) return hit.$2;
  final rec = readGgufSampling(path);
  _ggufCache[path] = (size, rec);
  return rec;
}

/// Puts an already read result into the cache (the settings page reads the
/// header off the UI isolate).
void rememberGgufSampling(String path, SamplingRecommendation? rec) {
  try {
    _ggufCache[path] = (File(path).lengthSync(), rec);
  } on FileSystemException {
    return;
  }
}

/// Reads the vendor recommendation from the GGUF header at [path], or null
/// when the file has none (or is not a readable GGUF). Header only; the
/// tensor data is never read.
SamplingRecommendation? readGgufSampling(String path) {
  final RandomAccessFile raf;
  try {
    raf = File(path).openSync();
  } on FileSystemException {
    return null;
  }
  try {
    return recommendationFrom(_readGgufSamplingValues(_GgufReader(raf)));
  } on Object {
    return null;
  } finally {
    raf.closeSync();
  }
}

Map<String, double> _readGgufSamplingValues(_GgufReader r) {
  if (r.u32() != 0x46554747) return const {}; // "GGUF"
  final version = r.u32();
  if (version < 2 || version > 3) return const {};
  r.u64(); // tensor count
  final kvCount = r.u64();
  if (kvCount <= 0 || kvCount > 100000) return const {};
  final out = <String, double>{};
  for (var i = 0; i < kvCount; i++) {
    final key = r.string();
    final type = r.u32();
    final field = _ggufSamplingKeys[key];
    final number = field == null ? null : r.number(type);
    if (field == null || number == null) {
      if (field == null) r.skip(type);
    } else {
      out[field] = number;
    }
  }
  return out;
}

class _GgufReader {
  _GgufReader(this._raf);
  final RandomAccessFile _raf;

  ByteData _take(int n) {
    final bytes = _raf.readSync(n);
    if (bytes.length < n) throw const FormatException('short read');
    return ByteData.sublistView(bytes);
  }

  int u32() => _take(4).getUint32(0, Endian.little);
  int u64() => _take(8).getUint64(0, Endian.little);

  String string() {
    final len = u64();
    if (len < 0 || len > 16 << 20) throw const FormatException('string');
    return utf8.decode(_raf.readSync(len), allowMalformed: true);
  }

  static const _fixed = {
    0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8, //
  };

  /// Reads a numeric value of [type], or skips it and returns null.
  double? number(int type) {
    final d = switch (type) {
      0 => _take(1).getUint8(0).toDouble(),
      1 => _take(1).getInt8(0).toDouble(),
      2 => _take(2).getUint16(0, Endian.little).toDouble(),
      3 => _take(2).getInt16(0, Endian.little).toDouble(),
      4 => _take(4).getUint32(0, Endian.little).toDouble(),
      5 => _take(4).getInt32(0, Endian.little).toDouble(),
      6 => _take(4).getFloat32(0, Endian.little),
      10 => _take(8).getUint64(0, Endian.little).toDouble(),
      11 => _take(8).getInt64(0, Endian.little).toDouble(),
      12 => _take(8).getFloat64(0, Endian.little),
      _ => null,
    };
    if (d == null) skip(type);
    return d;
  }

  void _skipBytes(int n) {
    if (n < 0) throw const FormatException('skip');
    final target = _raf.positionSync() + n;
    if (target > _raf.lengthSync()) throw const FormatException('skip');
    _raf.setPositionSync(target);
  }

  void skip(int type) {
    final fixed = _fixed[type];
    if (fixed != null) return _skipBytes(fixed);
    if (type == 8) return _skipBytes(u64());
    if (type == 9) {
      final itemType = u32();
      final count = u64();
      final itemFixed = _fixed[itemType];
      if (itemFixed != null) return _skipBytes(itemFixed * count);
      for (var i = 0; i < count; i++) {
        skip(itemType);
      }
      return;
    }
    throw const FormatException('unknown GGUF value type');
  }
}
