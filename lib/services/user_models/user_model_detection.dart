/// Recognises runtime, family and files of a model from file names alone
/// (#1789): the sherpa-onnx naming scheme, whisper.cpp GGML files and GGUF.
///
/// Pure: the caller hands over the file list of a Hugging Face repo, the
/// addresses or the picked files. What cannot be recognised yields no
/// candidate; the UI then says so and lets the user pick runtime and family
/// themselves ([assignSherpaRoles] checks that pick).
library;

import 'dart:math' as math;

import 'user_model.dart';

/// One file as a source lists it.
class SourceFile {
  const SourceFile({required this.path, this.sizeBytes = 0, this.sha256});

  /// Path inside the repo (with folders) or the plain file name.
  final String path;
  final int sizeBytes;
  final String? sha256;

  String get baseName {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  String get folder {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }
}

/// A file with the role it plays for the model.
class DetectedFile {
  const DetectedFile({required this.role, required this.source});
  final UserModelFileRole role;
  final SourceFile source;
}

/// One way to load (part of) the source.
class UserModelCandidate {
  const UserModelCandidate({
    required this.runtime,
    required this.files,
    this.family,
  });

  final UserModelRuntime runtime;
  final SherpaFamily? family;
  final List<DetectedFile> files;

  /// Short label for a choice list: the main file name.
  String get label {
    final main = files.firstWhere(
      (f) => f.role != UserModelFileRole.tokens,
      orElse: () => files.first,
    );
    return main.source.path;
  }
}

/// All candidates in [files], best first. [repoName] (e.g.
/// `csukuangfj/sherpa-onnx-sense-voice-…`) decides between sherpa families
/// that share the same file names.
List<UserModelCandidate> detectUserModelCandidates(
  List<SourceFile> files, {
  String repoName = '',
}) {
  final gguf = <UserModelCandidate>[];
  final ggml = <UserModelCandidate>[];
  for (final f in files) {
    final name = f.baseName.toLowerCase();
    if (isUsableGgufName(name)) {
      gguf.add(
        UserModelCandidate(
          runtime: UserModelRuntime.llamaCpp,
          files: [DetectedFile(role: UserModelFileRole.model, source: f)],
        ),
      );
    } else if (isWhisperGgmlName(name)) {
      ggml.add(
        UserModelCandidate(
          runtime: UserModelRuntime.whispercpp,
          files: [DetectedFile(role: UserModelFileRole.model, source: f)],
        ),
      );
    }
  }
  gguf.sort((a, b) => _ggufRank(a).compareTo(_ggufRank(b)));
  ggml.sort((a, b) => _ggmlRank(a).compareTo(_ggmlRank(b)));

  final sherpa = <UserModelCandidate>[];
  final byFolder = <String, List<SourceFile>>{};
  for (final f in files) {
    byFolder.putIfAbsent(f.folder, () => []).add(f);
  }
  for (final entry in byFolder.entries) {
    final where = '${repoName.toLowerCase()}/${entry.key.toLowerCase()}';
    if (_streamingExport.hasMatch(where)) continue;
    // A folder's own files, then the side files (tokens, tokenizer) of its
    // subfolders: some exports keep the tokenizer in `tokenizer/`. The model
    // files themselves only come from the folder ([assignSherpaRoles]).
    final group = [
      ...entry.value,
      for (final f in files)
        if (_isBelow(f.folder, entry.key) && !_isOnnx(f.baseName)) f,
    ];
    final family = guessSherpaFamily(
      group.map((f) => f.baseName).toList(),
      repoName: repoName,
    );
    if (family == null) continue;
    final roles = assignSherpaRoles(family, group);
    if (roles is SherpaRolesAssigned) {
      sherpa.add(
        UserModelCandidate(
          runtime: UserModelRuntime.sherpaOnnx,
          family: family,
          files: roles.files,
        ),
      );
    }
  }
  return [...sherpa, ...ggml, ...gguf];
}

/// A `.gguf` file llama.cpp can open on its own as a chat model: no split
/// shard, no vision projector, and none of the helper files repos ship next
/// to the model (importance matrix, LoRA adapter, speculative-decoding
/// heads and drafts, vocabulary-only files; #2193).
bool isUsableGgufName(String lowerName) =>
    lowerName.endsWith('.gguf') &&
    !lowerName.contains('mmproj') &&
    !RegExp(r'-\d{5}-of-\d{5}\.gguf$').hasMatch(lowerName) &&
    !_ggufHelperFile.hasMatch(lowerName);

final _ggufHelperFile = RegExp(
  r'(^|[-_.])(imatrix|lora|eagle\d*|dflash\d*|draft|vocab)([-_.]|$)',
);

/// A whisper.cpp model file (`ggml-<name>.bin`), not a Core ML or OpenVINO
/// side file, and not a ggml port of another speech architecture (Parakeet
/// for libparakeet and similar share the `ggml-*.bin` name and the `ggml`
/// magic, but `whisper_init` cannot load them; #2193).
bool isWhisperGgmlName(String lowerName) =>
    lowerName.startsWith('ggml-') &&
    lowerName.endsWith('.bin') &&
    !lowerName.contains('encoder') &&
    !lowerName.contains('silero') &&
    !lowerName.contains('vad') &&
    !_nonWhisperGgml.hasMatch(lowerName);

final _nonWhisperGgml = RegExp(
  r'parakeet|canary|fastconformer|moonshine|sensevoice|wav2vec|voxtral|'
  r'nemotron|(^|[-_.])(tdt|ctc|nemo|rnnt)([-_.]|\d|$)',
);

/// Exports for streaming (online) recognition: sherpa-onnx's offline
/// recognizer, the one own models run on, cannot load them. Their repos and
/// folders say so (`streaming`, `online`, chunk sizes like `1120ms`; #2193).
final _streamingExport = RegExp(
  r'streaming|(^|[-_/])online([-_/]|$)|(^|[-_/])(chunk-)?\d+ms([-_/]|$)',
);

/// Q4_K_M first (the usual size/quality balance), then the smaller quants.
int _ggufRank(UserModelCandidate c) {
  final n = c.files.first.source.baseName.toLowerCase();
  if (n.contains('q4_k_m')) return 0;
  if (n.contains('q4')) return 1;
  if (n.contains('q5')) return 2;
  if (n.contains('q8')) return 3;
  if (n.contains('q3') || n.contains('q2')) return 4;
  return 5;
}

/// Quantised q5 first, then q8, then the rest.
int _ggmlRank(UserModelCandidate c) {
  final n = c.files.first.source.baseName.toLowerCase();
  if (n.contains('q5')) return 0;
  if (n.contains('q8')) return 1;
  if (n.contains('q4')) return 2;
  return 3;
}

bool _isOnnx(String name) => name.toLowerCase().endsWith('.onnx');

/// Whether [folder] lies strictly inside [parent] (`''` is the repo root).
bool _isBelow(String folder, String parent) =>
    folder != parent &&
    (parent.isEmpty ? folder.isNotEmpty : folder.startsWith('$parent/'));

/// The tokenizer files of a Hugging Face BPE tokenizer, as sherpa-onnx's
/// Qwen3-ASR reads them.
const _bpeTokenizerNames = {
  'vocab.json',
  'merges.txt',
  'tokenizer_config.json',
};

/// Whether [name] is a side file a sherpa-onnx model needs next to its ONNX
/// files: `tokens.txt` or a BPE tokenizer file.
bool isSherpaSideFileName(String name) {
  final lower = name.toLowerCase();
  return _isTokens(lower) || _bpeTokenizerNames.contains(lower);
}

bool _isTokens(String lower) =>
    lower == 'tokens.txt' || lower.endsWith('-tokens.txt');

/// The sherpa-onnx family the file names (and the repo name) point to, or
/// null when they do not match the naming scheme.
SherpaFamily? guessSherpaFamily(List<String> names, {String repoName = ''}) {
  final lower = names.map((n) => n.toLowerCase()).toList();
  final onnx = lower.where((n) => n.endsWith('.onnx')).toList();
  if (onnx.isEmpty) return null;
  bool has(String prefix) => onnx.any((n) => n.startsWith(prefix));
  bool hasPart(String part) => onnx.any((n) => n.contains(part));

  // Families with their own tokenizer instead of `tokens.txt`.
  if (_bpeTokenizerNames.every(lower.contains) &&
      hasPart('conv_frontend') &&
      hasPart('encoder') &&
      hasPart('decoder')) {
    return SherpaFamily.qwen3Asr;
  }

  if (!lower.any(_isTokens)) return null;
  final repo = repoName.toLowerCase();

  if (has('preprocess') && hasPart('uncached_decode')) {
    return SherpaFamily.moonshine;
  }
  if (hasPart('encoder') && hasPart('decoder') && hasPart('joiner')) {
    return repo.contains('nemo') || repo.contains('parakeet')
        ? SherpaFamily.nemoTransducer
        : SherpaFamily.transducer;
  }
  if (hasPart('encoder') && hasPart('decoder')) {
    if (repo.contains('fire-red') || repo.contains('fire_red')) {
      return SherpaFamily.fireRedAsr;
    }
    if (repo.contains('whisper') || hasPart('whisper')) {
      return SherpaFamily.whisper;
    }
    return null;
  }
  if (onnx.any((n) => n.startsWith('model'))) {
    if (repo.contains('sense-voice') || repo.contains('sensevoice')) {
      return SherpaFamily.senseVoice;
    }
    if (repo.contains('paraformer')) return SherpaFamily.paraformer;
    if (repo.contains('dolphin')) return SherpaFamily.dolphin;
    if (repo.contains('ctc')) {
      if (repo.contains('nemo') || repo.contains('parakeet')) {
        return SherpaFamily.nemoCtc;
      }
      if (repo.contains('zipformer')) return SherpaFamily.zipformerCtc;
    }
  }
  return null;
}

/// Result of [assignSherpaRoles].
sealed class SherpaRoles {
  const SherpaRoles();
}

final class SherpaRolesAssigned extends SherpaRoles {
  const SherpaRolesAssigned(this.files);
  final List<DetectedFile> files;
}

/// The roles no file could be found for.
final class SherpaRolesMissing extends SherpaRoles {
  const SherpaRolesMissing(this.missing);
  final List<UserModelFileRole> missing;
}

/// Picks one file per role [family] needs. Where a role has several files
/// (an `int8` and a full-precision variant), the `int8` one wins: smaller,
/// and what sherpa-onnx recommends on CPU. Model files come from the
/// topmost folder of [files] only; side files (tokens, tokenizer) may also
/// come from below it, the nearest one winning.
SherpaRoles assignSherpaRoles(SherpaFamily family, List<SourceFile> files) {
  final picked = <DetectedFile>[];
  final missing = <UserModelFileRole>[];
  final depth = files.isEmpty
      ? 0
      : files.map((f) => _depth(f.folder)).reduce(math.min);
  for (final role in family.requiredRoles) {
    final matches =
        files
            .where((f) => _matchesRole(role, f.baseName))
            .where((f) => !_isOnnx(f.baseName) || _depth(f.folder) == depth)
            .toList()
          ..sort((a, b) {
            final byDepth = _depth(a.folder).compareTo(_depth(b.folder));
            return byDepth != 0
                ? byDepth
                : _variantRank(a).compareTo(_variantRank(b));
          });
    if (matches.isEmpty) {
      missing.add(role);
    } else {
      picked.add(DetectedFile(role: role, source: matches.first));
    }
  }
  return missing.isEmpty
      ? SherpaRolesAssigned(picked)
      : SherpaRolesMissing(missing);
}

bool _matchesRole(UserModelFileRole role, String name) {
  final n = name.toLowerCase();
  if (role == UserModelFileRole.tokens) return _isTokens(n);
  final fixed = role.fixedFileName;
  if (fixed != null) return n == fixed;
  if (!n.endsWith('.onnx')) return false;
  return switch (role) {
    UserModelFileRole.model => n.startsWith('model'),
    UserModelFileRole.encoder =>
      n.contains('encoder') || n.startsWith('encode'),
    UserModelFileRole.convFrontend => n.contains('conv_frontend'),
    UserModelFileRole.decoder =>
      n.contains('decoder') &&
          !n.contains('uncached') &&
          !n.contains('cached_'),
    UserModelFileRole.joiner => n.contains('joiner'),
    UserModelFileRole.preprocessor => n.startsWith('preprocess'),
    UserModelFileRole.uncachedDecoder => n.contains('uncached_decode'),
    UserModelFileRole.cachedDecoder =>
      n.contains('cached_decode') && !n.contains('uncached'),
    UserModelFileRole.tokens ||
    UserModelFileRole.tokenizerVocab ||
    UserModelFileRole.tokenizerMerges ||
    UserModelFileRole.tokenizerConfig => false,
  };
}

int _depth(String folder) =>
    folder.isEmpty ? 0 : '/'.allMatches(folder).length + 1;

int _variantRank(SourceFile f) {
  final n = f.baseName.toLowerCase();
  if (n.contains('int8')) return 0;
  if (n.contains('fp16') || n.contains('float16')) return 2;
  return 1;
}

/// The runtime a single file name suggests, for a direct address or a picked
/// file. Null when the name says nothing (the user then picks).
UserModelRuntime? runtimeForFileName(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.gguf')) return UserModelRuntime.llamaCpp;
  if (n.endsWith('.bin')) return UserModelRuntime.whispercpp;
  if (n.endsWith('.onnx') || _isTokens(n)) return UserModelRuntime.sherpaOnnx;
  return null;
}
