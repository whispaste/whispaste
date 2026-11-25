/// A model the user added from a source they picked themselves (#1789):
/// a Hugging Face repo, direct HTTPS addresses or files on their computer.
///
/// These models are never checked by WhisPaste the way the catalog is, so
/// the UI always marks them "nicht geprüft". They live in their own list
/// (`user_models.json`, see `user_model_store.dart`), apart from the catalog
/// in `model_download_service.dart` and `smart_mode_model_download_service.dart`.
library;

/// What the model is for.
enum UserModelPurpose { speech, smartMode }

/// The runtime that loads the model. One per supported interface; anything
/// else is refused before the download.
enum UserModelRuntime {
  /// whisper.cpp, a single GGML file (speech).
  whispercpp('whispercpp', UserModelPurpose.speech),

  /// sherpa-onnx offline recognizer, one of [SherpaFamily] (speech).
  sherpaOnnx('sherpa_onnx', UserModelPurpose.speech),

  /// llama.cpp, a single GGUF file (Smart Mode).
  llamaCpp('llama_cpp', UserModelPurpose.smartMode);

  const UserModelRuntime(this.value, this.purpose);
  final String value;
  final UserModelPurpose purpose;

  static UserModelRuntime? fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// Role of one file of a model.
enum UserModelFileRole {
  model('model'),
  encoder('encoder'),
  decoder('decoder'),
  joiner('joiner'),
  tokens('tokens'),
  preprocessor('preprocessor'),
  uncachedDecoder('uncached_decoder'),
  cachedDecoder('cached_decoder'),

  /// Qwen3-ASR audio front end (`conv_frontend.onnx`).
  convFrontend('conv_frontend'),

  /// Qwen3-ASR tokenizer files. sherpa-onnx reads them from one folder under
  /// these exact names, so they keep them in the model folder
  /// ([fixedFileName]).
  tokenizerVocab('tokenizer_vocab', fixedFileName: 'vocab.json'),
  tokenizerMerges('tokenizer_merges', fixedFileName: 'merges.txt'),
  tokenizerConfig('tokenizer_config', fixedFileName: 'tokenizer_config.json');

  const UserModelFileRole(this.value, {this.fixedFileName});
  final String value;

  /// The name the runtime looks the file up by, or null when any name works.
  final String? fixedFileName;

  static UserModelFileRole? fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// sherpa-onnx offline model families WhisPaste can configure (allowlist).
/// Each lists the file roles it needs; `tokens` comes with it unless the
/// family brings its own tokenizer ([tokenRoles]).
enum SherpaFamily {
  transducer('transducer', [
    UserModelFileRole.encoder,
    UserModelFileRole.decoder,
    UserModelFileRole.joiner,
  ]),

  /// NeMo transducers (Parakeet TDT and relatives): the same files as
  /// [transducer], loaded with `modelType: nemo_transducer`.
  nemoTransducer('nemo_transducer', [
    UserModelFileRole.encoder,
    UserModelFileRole.decoder,
    UserModelFileRole.joiner,
  ]),
  whisper('whisper', [UserModelFileRole.encoder, UserModelFileRole.decoder]),
  paraformer('paraformer', [UserModelFileRole.model]),
  senseVoice('sense_voice', [UserModelFileRole.model]),
  nemoCtc('nemo_ctc', [UserModelFileRole.model]),
  zipformerCtc('zipformer_ctc', [UserModelFileRole.model]),
  moonshine('moonshine', [
    UserModelFileRole.preprocessor,
    UserModelFileRole.encoder,
    UserModelFileRole.uncachedDecoder,
    UserModelFileRole.cachedDecoder,
  ]),
  fireRedAsr('fire_red_asr', [
    UserModelFileRole.encoder,
    UserModelFileRole.decoder,
  ]),
  dolphin('dolphin', [UserModelFileRole.model]),

  /// Qwen3-ASR (#153): audio front end, encoder and a decoder with KV cache,
  /// plus a Hugging Face BPE tokenizer instead of `tokens.txt`. Only as the
  /// user's own model; it is no built-in engine (spike 2026-10-14: not more
  /// accurate than Parakeet on German, 7 to 10 times slower).
  qwen3Asr(
    'qwen3_asr',
    [
      UserModelFileRole.convFrontend,
      UserModelFileRole.encoder,
      UserModelFileRole.decoder,
    ],
    tokenRoles: [
      UserModelFileRole.tokenizerVocab,
      UserModelFileRole.tokenizerMerges,
      UserModelFileRole.tokenizerConfig,
    ],
  );

  const SherpaFamily(
    this.value,
    this.modelRoles, {
    this.tokenRoles = const [UserModelFileRole.tokens],
  });
  final String value;

  /// The model files besides the tokens.
  final List<UserModelFileRole> modelRoles;

  /// The files that map ids to text: `tokens.txt` for most families.
  final List<UserModelFileRole> tokenRoles;

  /// Every role the family needs, the tokens last.
  List<UserModelFileRole> get requiredRoles => [...modelRoles, ...tokenRoles];

  static SherpaFamily? fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// Where the model came from.
enum UserModelSourceKind {
  huggingFace('hugging_face'),
  url('url'),
  file('file');

  const UserModelSourceKind(this.value);
  final String value;

  static UserModelSourceKind? fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// Where a model stands.
enum UserModelStatus {
  /// Download, format check or short test still running (or interrupted:
  /// the app treats a `checking` model found at start as not ready).
  checking('checking'),

  /// Passed the format check and the short test; can be used.
  ready('ready'),

  /// Failed the check or the short test, or failed later in use. Never active.
  failed('failed');

  const UserModelStatus(this.value);
  final String value;

  static UserModelStatus fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return failed;
  }
}

/// Why a model is not usable. The UI maps each to a sentence that says why.
enum UserModelFailure {
  download('download'),
  diskSpace('disk_space'),
  fileChanged('file_changed'),
  missingFiles('missing_files'),
  badFormat('bad_format'),
  unsupportedArchitecture('unsupported_architecture'),
  noChatTemplate('no_chat_template'),
  shortTestFailed('short_test_failed'),
  shortTestEmpty('short_test_empty'),
  crashed('crashed'),
  checkUnavailable('check_unavailable'),
  failedInUse('failed_in_use');

  const UserModelFailure(this.value);
  final String value;

  static UserModelFailure? fromValue(Object? v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// One file of a model.
class UserModelFile {
  const UserModelFile({
    required this.role,
    required this.name,
    this.url,
    this.sizeBytes = 0,
    this.sha256,
  });

  final UserModelFileRole role;

  /// File name inside the model folder. Only a base name, never a path.
  final String name;

  /// HTTPS source, pinned to one commit for Hugging Face. Null for a file the
  /// user picked on their computer.
  final String? url;

  /// Expected size; 0 when the source did not say.
  final int sizeBytes;

  /// SHA-256 the source names (Hugging Face LFS) or the one WhisPaste saw on
  /// the first download (trust on first use). A later download that differs
  /// is reported as [UserModelFailure.fileChanged].
  final String? sha256;

  UserModelFile copyWith({int? sizeBytes, String? sha256}) => UserModelFile(
    role: role,
    name: name,
    url: url,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
  );

  Map<String, Object?> toJson() => {
    'role': role.value,
    'name': name,
    'url': ?url,
    'size': sizeBytes,
    'sha256': ?sha256,
  };

  static UserModelFile? fromJson(Object? json) {
    if (json is! Map) return null;
    final role = UserModelFileRole.fromValue(json['role']);
    final name = json['name'];
    if (role == null || name is! String || !isSafeFileName(name)) return null;
    final url = json['url'];
    final size = json['size'];
    final sha = json['sha256'];
    return UserModelFile(
      role: role,
      name: name,
      url: url is String ? url : null,
      sizeBytes: size is int ? size : 0,
      sha256: sha is String ? sha : null,
    );
  }
}

/// Whether [name] is a plain file name that stays inside the model folder.
bool isSafeFileName(String name) =>
    name.isNotEmpty &&
    name != '.' &&
    name != '..' &&
    !name.contains('/') &&
    !name.contains('\\') &&
    !name.contains('\u0000');

/// The whole entry in `user_models.json`.
class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.runtime,
    required this.sourceKind,
    required this.files,
    required this.addedAt,
    this.family,
    this.sourceAddress,
    this.revision,
    this.license,
    this.status = UserModelStatus.checking,
    this.failure,
  });

  /// `user-<hex>`, also the folder name and, for whisper.cpp, the model id in
  /// the speech settings.
  final String id;

  /// Display name: the repo or file name, never a full address.
  final String name;
  final UserModelRuntime runtime;

  /// Only for [UserModelRuntime.sherpaOnnx].
  final SherpaFamily? family;
  final UserModelSourceKind sourceKind;

  /// The page the user took the model from (repo page or first file
  /// address), linked from the terms confirmation. Null for local files.
  /// Stays on this computer: never sent anywhere, never in telemetry.
  final String? sourceAddress;

  /// Hugging Face commit the files are pinned to.
  final String? revision;

  /// The license the source names (Hugging Face model card), shown as is.
  final String? license;
  final List<UserModelFile> files;
  final DateTime addedAt;
  final UserModelStatus status;
  final UserModelFailure? failure;

  UserModelPurpose get purpose => runtime.purpose;

  bool get isReady => status == UserModelStatus.ready;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.sizeBytes);

  /// The file with [role], or null.
  UserModelFile? fileFor(UserModelFileRole role) {
    for (final f in files) {
      if (f.role == role) return f;
    }
    return null;
  }

  UserModel copyWith({
    String? name,
    List<UserModelFile>? files,
    UserModelStatus? status,
    UserModelFailure? failure,
    bool clearFailure = false,
  }) => UserModel(
    id: id,
    name: name ?? this.name,
    runtime: runtime,
    family: family,
    sourceKind: sourceKind,
    sourceAddress: sourceAddress,
    revision: revision,
    license: license,
    files: files ?? this.files,
    addedAt: addedAt,
    status: status ?? this.status,
    failure: clearFailure ? null : (failure ?? this.failure),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'runtime': runtime.value,
    'family': ?family?.value,
    'source': sourceKind.value,
    'address': ?sourceAddress,
    'revision': ?revision,
    'license': ?license,
    'files': [for (final f in files) f.toJson()],
    'added_at': addedAt.toUtc().toIso8601String(),
    'status': status.value,
    'failure': ?failure?.value,
  };

  /// Null for an entry that is damaged or from a newer app version, so one
  /// bad entry never takes the whole list down.
  static UserModel? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    final runtime = UserModelRuntime.fromValue(json['runtime']);
    final source = UserModelSourceKind.fromValue(json['source']);
    final rawFiles = json['files'];
    if (id is! String ||
        !id.startsWith('user-') ||
        !isSafeFileName(id) ||
        name is! String ||
        runtime == null ||
        source == null ||
        rawFiles is! List) {
      return null;
    }
    final files = <UserModelFile>[];
    for (final raw in rawFiles) {
      final file = UserModelFile.fromJson(raw);
      if (file == null) return null;
      files.add(file);
    }
    final family = SherpaFamily.fromValue(json['family']);
    if (runtime == UserModelRuntime.sherpaOnnx && family == null) return null;
    final address = json['address'];
    final revision = json['revision'];
    final license = json['license'];
    final added = DateTime.tryParse('${json['added_at']}');
    return UserModel(
      id: id,
      name: name,
      runtime: runtime,
      family: runtime == UserModelRuntime.sherpaOnnx ? family : null,
      sourceKind: source,
      sourceAddress: address is String ? address : null,
      revision: revision is String ? revision : null,
      license: license is String ? license : null,
      files: files,
      addedAt: added ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      status: UserModelStatus.fromValue(json['status']),
      failure: UserModelFailure.fromValue(json['failure']),
    );
  }
}

/// The speech selection to return to when a user model fails (#1789): the
/// last catalog model the user had in use before switching to their own.
class SpeechFallbackChoice {
  const SpeechFallbackChoice({required this.engine, required this.modelId});

  /// Persisted engine value (`whisper`, `parakeet`, `system`, `user_model`).
  final String engine;

  /// The Whisper model id; ignored by the other engines.
  final String modelId;

  Map<String, Object?> toJson() => {'engine': engine, 'model': modelId};

  static SpeechFallbackChoice? fromJson(Object? json) {
    if (json is! Map) return null;
    final engine = json['engine'];
    final model = json['model'];
    if (engine is! String || model is! String) return null;
    return SpeechFallbackChoice(engine: engine, modelId: model);
  }
}
