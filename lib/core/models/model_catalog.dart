/// The model catalog: what WhisPaste can download, in one versioned format
/// (#1513, part of #1512).
///
/// Every downloadable model (speech recognition and Smart Mode) is one
/// [CatalogModel] with its files. Each [ModelFile] is pinned: exact size,
/// SHA-256 and an ordered list of public HTTPS [ModelFile.sources] at a fixed
/// revision. WhisPaste hosts no model files itself; a second source is only
/// listed where another public host serves the identical bytes.
///
/// The catalog ships with the app ([bundledModelCatalog] in
/// `bundled_model_catalog.dart`). A signed catalog file can add models
/// without an app release (#1792, `active_model_catalog.dart` and
/// `remote_model_catalog.dart`); [ModelCatalog.fromJson] reads it. Pure Dart,
/// no Flutter imports, so the tools under `tool/` can read it too.
library;

import '../semver.dart';
import '../text/byte_size.dart';

/// Schema version of the catalog format. Raise it on any incompatible change;
/// [ModelCatalog.fromJson] refuses a catalog with another version.
const int kModelCatalogSchemaVersion = 1;

/// What a model does.
enum ModelKind {
  /// Speech recognition.
  stt,

  /// Text model for Smart Mode.
  llm,
}

/// The engine that loads a model's files.
enum ModelRuntime {
  whisperCpp('whisper.cpp'),
  sherpaOnnx('sherpa-onnx'),
  parakeetGgml('parakeet-ggml'),
  llamaCpp('llama.cpp');

  const ModelRuntime(this.wireName);

  /// Name in the JSON form.
  final String wireName;
}

/// A coarse step for speed or accuracy, relative to the other models of the
/// same [ModelKind].
enum ModelLevel { low, medium, high }

/// Desktop systems a model runs on.
enum ModelPlatform { macos, windows, linux }

/// The ISO 639-2 code for "multiple languages": the model has no fixed list.
const String kAnyLanguage = 'mul';

/// What a machine needs for a model. The memory values are guide values for
/// the resident model, not hard limits; null means not known.
class ModelRequirements {
  const ModelRequirements({
    this.platforms = ModelPlatform.values,
    this.ramMb,
    this.vramMb,
  });

  final List<ModelPlatform> platforms;
  final int? ramMb;
  final int? vramMb;

  Map<String, Object?> toJson() => {
    'platforms': [for (final p in platforms) p.name],
    if (ramMb != null) 'ramMb': ramMb,
    if (vramMb != null) 'vramMb': vramMb,
  };

  static ModelRequirements fromJson(Map<String, Object?> json) =>
      ModelRequirements(
        platforms: [
          for (final name in _list(json, 'platforms'))
            _enumByName(ModelPlatform.values, name, 'platform'),
        ],
        ramMb: _optInt(json, 'ramMb'),
        vramMb: _optInt(json, 'vramMb'),
      );
}

/// One file of a model, pinned by size and hash.
class ModelFile {
  const ModelFile({
    required this.filename,
    required this.sizeBytes,
    required this.sha256,
    required this.sources,
  });

  final String filename;
  final int sizeBytes;

  /// Lower-case hex SHA-256 of the whole file.
  final String sha256;

  /// Public HTTPS sources of the identical file, tried in this order
  /// (`HttpModelFetcher.fetchVerified`); each is checked against [sizeBytes]
  /// and [sha256].
  final List<String> sources;

  /// The first source.
  String get url => sources.first;

  /// The sources after [url].
  List<String> get mirrorUrls => sources.skip(1).toList();

  Map<String, Object?> toJson() => {
    'filename': filename,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
    'sources': sources,
  };

  static ModelFile fromJson(Map<String, Object?> json) => ModelFile(
    filename: _string(json, 'filename'),
    sizeBytes: _int(json, 'sizeBytes'),
    sha256: _string(json, 'sha256'),
    sources: _list(json, 'sources'),
  );
}

/// One downloadable model.
class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.kind,
    required this.runtime,
    required this.label,
    required this.minAppVersion,
    required this.languages,
    required this.speed,
    required this.accuracy,
    required this.requirements,
    required this.license,
    required this.files,
    this.contextLength,
  });

  /// Stable ID, also stored in settings and history. Never renamed.
  final String id;
  final ModelKind kind;
  final ModelRuntime runtime;

  /// Technical name, for tooltips and details (never the display name).
  final String label;

  /// The oldest app version that can load this model.
  final String minAppVersion;

  /// ISO 639-1 codes the model transcribes or writes, or [kAnyLanguage].
  final List<String> languages;
  final ModelLevel speed;
  final ModelLevel accuracy;
  final ModelRequirements requirements;

  /// Context window in tokens WhisPaste runs an [ModelKind.llm] with.
  final int? contextLength;

  /// SPDX identifier of the weights' licence.
  final String license;
  final List<ModelFile> files;

  /// Sum of all file sizes.
  int get sizeBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);

  /// [sizeBytes] for the UI, the one shared formatter (`formatByteSize`).
  String get sizeLabel => formatByteSize(sizeBytes);

  /// The only file of a single-file model.
  ModelFile get file => files.single;

  /// Shortcuts for single-file models (whisper.cpp, llama.cpp).
  String get filename => file.filename;
  String get url => file.url;
  String get sha256 => file.sha256;
  List<String> get sources => file.sources;

  /// Whether [appVersion] is new enough for this model. An unparsable
  /// version counts as new enough (a development build).
  bool supportsAppVersion(String appVersion) =>
      _versionAtLeast(appVersion, minAppVersion);

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'runtime': runtime.wireName,
    'label': label,
    'minAppVersion': minAppVersion,
    'languages': languages,
    'speed': speed.name,
    'accuracy': accuracy.name,
    'requirements': requirements.toJson(),
    if (contextLength != null) 'contextLength': contextLength,
    'license': license,
    'files': [for (final f in files) f.toJson()],
  };

  static CatalogModel fromJson(Map<String, Object?> json) => CatalogModel(
    id: _string(json, 'id'),
    kind: _enumByName(ModelKind.values, _string(json, 'kind'), 'kind'),
    runtime: ModelRuntime.values.firstWhere(
      (r) => r.wireName == json['runtime'],
      orElse: () => throw ModelCatalogFormatException(
        'unknown runtime ${json['runtime']}',
      ),
    ),
    label: _string(json, 'label'),
    minAppVersion: _string(json, 'minAppVersion'),
    languages: _list(json, 'languages'),
    speed: _enumByName(ModelLevel.values, _string(json, 'speed'), 'speed'),
    accuracy: _enumByName(
      ModelLevel.values,
      _string(json, 'accuracy'),
      'accuracy',
    ),
    requirements: ModelRequirements.fromJson(_map(json, 'requirements')),
    contextLength: _optInt(json, 'contextLength'),
    license: _string(json, 'license'),
    files: [
      for (final f in _rawList(json, 'files'))
        ModelFile.fromJson(_asMap(f, 'files[]')),
    ],
  );
}

/// The whole catalog.
class ModelCatalog {
  const ModelCatalog({
    required this.schemaVersion,
    required this.models,
    this.revision = 0,
  });

  final int schemaVersion;
  final List<CatalogModel> models;

  /// Publication counter of a downloaded catalog file (#1792). Every
  /// published file raises it; the app never replaces a stored catalog with
  /// one of a lower revision, so an older signed file cannot be replayed.
  /// The bundled catalog has 0.
  final int revision;

  /// The model with [id]; throws if the catalog has none.
  CatalogModel byId(String id) => models.firstWhere(
    (m) => m.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'not in the catalog'),
  );

  /// The model with [id], or null.
  CatalogModel? tryById(String id) {
    for (final m in models) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Every file of every model, in catalog order.
  List<ModelFile> get allFiles => [for (final m in models) ...m.files];

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    if (revision != 0) 'revision': revision,
    'models': [for (final m in models) m.toJson()],
  };

  /// Reads a catalog. Throws [ModelCatalogFormatException] on another schema
  /// version, a missing field or any problem [validate] finds: a catalog
  /// that would download something unchecked is never used.
  ///
  /// With [appVersion], entries whose `minAppVersion` is above it are left
  /// out before they are read, so a newer catalog may name a runtime or a
  /// field this app does not know yet for models this app cannot load
  /// anyway (#1792).
  static ModelCatalog fromJson(
    Map<String, Object?> json, {
    String? appVersion,
  }) {
    final version = _int(json, 'schemaVersion');
    if (version != kModelCatalogSchemaVersion) {
      throw ModelCatalogFormatException(
        'schema version $version, this app reads $kModelCatalogSchemaVersion',
      );
    }
    final revision = _optInt(json, 'revision') ?? 0;
    if (revision < 0) {
      throw ModelCatalogFormatException('revision $revision is negative');
    }
    final catalog = ModelCatalog(
      schemaVersion: version,
      revision: revision,
      models: [
        for (final m in _rawList(json, 'models'))
          if (appVersion == null ||
              _rawSupportsAppVersion(_asMap(m, 'models[]'), appVersion))
            CatalogModel.fromJson(_asMap(m, 'models[]')),
      ],
    );
    final problems = catalog.validate();
    if (problems.isNotEmpty) {
      throw ModelCatalogFormatException(problems.join('; '));
    }
    return catalog;
  }

  /// Everything that makes this catalog unsafe to download from; empty when
  /// it is fine. Checks unique IDs and file names, positive sizes, hash
  /// format, the llm context length and that every source is a pinned HTTPS
  /// address (a Hugging Face `resolve/<commit>` or a fixed GitHub release
  /// tag, never a moving branch).
  List<String> validate() {
    final problems = <String>[];
    if (schemaVersion != kModelCatalogSchemaVersion) {
      problems.add('unsupported schema version $schemaVersion');
    }
    final ids = <String>{};
    final names = <String>{};
    for (final m in models) {
      if (m.id.isEmpty || !ids.add(m.id)) {
        problems.add('duplicate or empty id "${m.id}"');
      }
      if (parseSemver(m.minAppVersion) == null) {
        problems.add(
          '${m.id}: minAppVersion "${m.minAppVersion}" is no version',
        );
      }
      if (m.languages.isEmpty) problems.add('${m.id}: no languages');
      if (m.requirements.platforms.isEmpty) {
        problems.add('${m.id}: no platforms');
      }
      if (m.license.isEmpty) problems.add('${m.id}: no license');
      if (m.kind == ModelKind.llm && (m.contextLength ?? 0) <= 0) {
        problems.add('${m.id}: llm without contextLength');
      }
      if (m.files.isEmpty) problems.add('${m.id}: no files');
      for (final f in m.files) {
        final where = '${m.id}/${f.filename}';
        if (f.filename.isEmpty ||
            f.filename.contains('/') ||
            f.filename.contains(r'\') ||
            f.filename.startsWith('.')) {
          problems.add('$where: bad file name');
        }
        // One file name is one file on disk: two models with the same name
        // in the same folder would overwrite each other.
        if (!names.add('${m.runtime.name}/${f.filename}')) {
          problems.add('$where: file name used twice');
        }
        if (f.sizeBytes <= 0) problems.add('$where: size ${f.sizeBytes}');
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(f.sha256)) {
          problems.add('$where: sha256 is not 64 lower-case hex digits');
        }
        if (f.sources.isEmpty) problems.add('$where: no sources');
        for (final url in f.sources) {
          final problem = pinnedSourceProblem(url);
          if (problem != null) problems.add('$where: $problem');
        }
      }
    }
    return problems;
  }
}

/// Whether the raw entry [json] can run on [appVersion]. An entry without a
/// readable `minAppVersion` is kept, so [CatalogModel.fromJson] and
/// [ModelCatalog.validate] report it instead of it vanishing silently.
bool _rawSupportsAppVersion(Map<String, Object?> json, String appVersion) {
  final min = json['minAppVersion'];
  if (min is! String || parseSemver(min) == null) return true;
  return _versionAtLeast(appVersion, min);
}

/// Whether [appVersion] is at least [minAppVersion], release parts only (a
/// pre-release of the minimum is enough). An unparsable version counts as
/// new enough (a development build).
bool _versionAtLeast(String appVersion, String minAppVersion) {
  final app = parseSemver(appVersion);
  final min = parseSemver(minAppVersion);
  if (app == null || min == null) return true;
  return compareParsedSemver(
        ParsedSemver(app.core, null),
        ParsedSemver(min.core, null),
      ) >=
      0;
}

/// Why [url] is no pinned public source, or null when it is one.
String? pinnedSourceProblem(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return '$url is not an https address';
  }
  if (uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.host != 'huggingface.co' && uri.host != 'github.com')) {
    return '$url is not a public catalog host without credentials';
  }
  if (uri.host == 'huggingface.co' && uri.path.contains('/resolve/')) {
    if (!RegExp(r'/resolve/[0-9a-f]{40}/').hasMatch(uri.path)) {
      return '$url is not pinned to a commit';
    }
    return null;
  }
  if (uri.host == 'github.com' && uri.path.contains('/releases/download/')) {
    if (uri.path.contains('/latest/')) return '$url follows "latest"';
    return null;
  }
  return '$url has no fixed revision';
}

/// A catalog that cannot be used (format, schema version or content).
class ModelCatalogFormatException implements FormatException {
  const ModelCatalogFormatException(this.message);

  @override
  final String message;

  @override
  int? get offset => null;

  @override
  Object? get source => null;

  @override
  String toString() => 'ModelCatalogFormatException: $message';
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

String _string(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw ModelCatalogFormatException('"$key" must be a string');
}

int _int(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is int) return v;
  throw ModelCatalogFormatException('"$key" must be an integer');
}

int? _optInt(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null || v is int) return v as int?;
  throw ModelCatalogFormatException('"$key" must be an integer');
}

List<Object?> _rawList(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is List) return v;
  throw ModelCatalogFormatException('"$key" must be a list');
}

List<String> _list(Map<String, Object?> json, String key) => [
  for (final v in _rawList(json, key))
    if (v is String)
      v
    else
      throw ModelCatalogFormatException('"$key" must hold strings'),
];

Map<String, Object?> _map(Map<String, Object?> json, String key) =>
    _asMap(json[key], key);

Map<String, Object?> _asMap(Object? v, String what) {
  if (v is Map) return v.cast<String, Object?>();
  throw ModelCatalogFormatException('"$what" must be an object');
}

T _enumByName<T extends Enum>(List<T> values, String name, String what) =>
    values.firstWhere(
      (v) => v.name == name,
      orElse: () => throw ModelCatalogFormatException('unknown $what "$name"'),
    );
