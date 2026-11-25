/// Model identity and quality values for the model telemetry (#1791).
///
/// Pure functions: callers pass facts, these return short categorical
/// strings. The usage statistics learn which speech models run and how well
/// they work, also for own models outside the catalog: that is a distributed
/// field test, the basis for adding models to the catalog (maintainer
/// 2026-11-17).
///
/// Model key:
/// - catalog models: their catalog id (`small`, `medium`, `large-v3-turbo`,
///   `parakeet`, `system`, `cloud`), see `telemetry_model_buckets.dart`;
/// - own models from Hugging Face: `hf:<owner>/<repo>/<file>`;
/// - own models from another address: `url:<host>/<file>`;
/// - own models imported from a file: `local:<first 12 hex of the SHA-256>`.
///
/// Own models come from `user_models.json` (#1789) through
/// [ownModelFactsFrom]; their page address (`UserModel.sourceAddress`) is
/// never read, only the download address of the main file.
///
/// Never a query string, a fragment, credentials or a port of the address,
/// never a local path or a local file name (internal-notes §6.5): an address can
/// carry an access token, a path the user name. [isTelemetrySafeName] is the
/// last gate before a model value leaves the app.
library;

import 'user_models/user_model.dart';

/// An own (non-catalog) model, as far as the telemetry may know it.
/// [sourceUrl] is only read for its host and last path segment.
class OwnModelFacts {
  const OwnModelFacts({
    required this.runtime,
    required this.family,
    required this.sizeBytes,
    required this.sha256,
    this.sourceUrl,
  });

  /// Runtime that runs the file: `whispercpp`, `sherpa_onnx`, `llama_cpp`.
  final String runtime;

  /// Model family: the sherpa-onnx family (`transducer`, `whisper`, …),
  /// `whisper` for a whisper.cpp file, `gguf` for a Smart Mode file.
  final String family;
  final int sizeBytes;

  /// SHA-256 of the model file, 64 hex characters.
  final String sha256;

  /// Download address; `null` for a file the user imported.
  final String? sourceUrl;
}

/// The file that names an own model in the telemetry: the model file, or
/// the encoder of a multi-file sherpa-onnx model, else the first file.
UserModelFile? _mainFile(UserModel model) =>
    model.fileFor(UserModelFileRole.model) ??
    model.fileFor(UserModelFileRole.encoder) ??
    (model.files.isEmpty ? null : model.files.first);

/// What the telemetry may know about own model [model]: runtime, family,
/// total size, the SHA-256 and the download address of its main file. A
/// model the user imported from their computer has no address
/// ([UserModelSourceKind.file]), so its key is only `local:<hash>`.
OwnModelFacts ownModelFactsFrom(UserModel model) {
  final main = _mainFile(model);
  return OwnModelFacts(
    runtime: model.runtime.value,
    family:
        model.family?.value ??
        switch (model.runtime) {
          UserModelRuntime.whispercpp => 'whisper',
          UserModelRuntime.llamaCpp => 'gguf',
          UserModelRuntime.sherpaOnnx => 'other',
        },
    sizeBytes: model.totalBytes,
    sha256: main?.sha256 ?? '',
    sourceUrl: model.sourceKind == UserModelSourceKind.file ? null : main?.url,
  );
}

final _hfSegment = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');
final _fileName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$');
final _hostName = RegExp(r'^[a-z0-9]([a-z0-9-]{0,62}\.)*[a-z0-9-]{1,63}$');
final _token = RegExp(r'^[a-z0-9][a-z0-9._-]{0,31}$');
final _sha256 = RegExp(r'^[a-f0-9]{64}$');

const _hfHosts = {'huggingface.co', 'hf.co'};

/// A file name that may be sent: plain characters, no dot-only name.
String? _safeFileName(String segment) {
  if (!_fileName.hasMatch(segment) || segment.contains('..')) return null;
  return segment;
}

/// The source part of an own model's key: `hf:<owner>/<repo>/<file>`,
/// `url:<host>/<file>` (or `url:<host>` when the file name is unusual), or
/// `null` when [url] is no usable `http(s)` address. Only the host and the
/// last path segment are read; scheme, credentials, port, the rest of the
/// path, query and fragment are dropped.
String? ownModelSourceKey(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (!_hostName.hasMatch(host)) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  final file = segments.isEmpty ? null : _safeFileName(segments.last);
  // huggingface.co/<owner>/<repo>/(resolve|blob)/<revision>/<path…>/<file>
  if (_hfHosts.contains(host) &&
      segments.length >= 5 &&
      (segments[2] == 'resolve' || segments[2] == 'blob') &&
      file != null &&
      _hfSegment.hasMatch(segments[0]) &&
      _hfSegment.hasMatch(segments[1]) &&
      !segments[0].contains('..') &&
      !segments[1].contains('..')) {
    return 'hf:${segments[0]}/${segments[1]}/$file';
  }
  return file == null ? 'url:$host' : 'url:$host/$file';
}

/// Size class of a model file: `lt100m`, `100m_500m`, `500m_1g`, `1g_2g`,
/// `gt2g` (decimal units, like the catalog sizes), `unknown` for no size.
String modelSizeBucket(int sizeBytes) {
  if (sizeBytes <= 0) return 'unknown';
  const mb = 1000 * 1000;
  if (sizeBytes < 100 * mb) return 'lt100m';
  if (sizeBytes < 500 * mb) return '100m_500m';
  if (sizeBytes < 1000 * mb) return '500m_1g';
  if (sizeBytes < 2000 * mb) return '1g_2g';
  return 'gt2g';
}

String _normalizedSha(String sha256) {
  final sha = sha256.trim().toLowerCase();
  return _sha256.hasMatch(sha) ? sha : 'unknown';
}

String _tokenOrOther(String value) {
  final t = value.trim().toLowerCase();
  return _token.hasMatch(t) && !t.contains('..') ? t : 'other';
}

/// The key of an own model, used in every model event and counter: the
/// source key ([ownModelSourceKey]) or, for an imported file,
/// `local:<first 12 hex of the SHA-256>` (`local:unknown` without a hash).
String ownModelKey(OwnModelFacts facts) {
  final source = ownModelSourceKey(facts.sourceUrl);
  if (source != null) return source;
  final sha = _normalizedSha(facts.sha256);
  return 'local:${sha == 'unknown' ? sha : sha.substring(0, 12)}';
}

/// The details of an own model, sent with `installed` and `activated`:
/// `<runtime>|<family>|<size class>|<sha256>`. An unusual runtime or family
/// becomes `other`, a malformed hash `unknown`.
String ownModelDetails(OwnModelFacts facts) =>
    '${_tokenOrOther(facts.runtime)}|${_tokenOrOther(facts.family)}'
    '|${modelSizeBucket(facts.sizeBytes)}|${_normalizedSha(facts.sha256)}';

/// The event name for `installed` / `activated`: the key, and for an own
/// model its details (`<key>|<runtime>|<family>|<size>|<sha256>`).
String modelEventName(String key, {OwnModelFacts? own}) =>
    own == null ? key : '$key|${ownModelDetails(own)}';

/// Device class of a dictation: RAM class, whether the machine has a usable
/// GPU, and whether the model ran on it, e.g. `8_16-gpu-cpu`. [ramClass]
/// comes from `ramBucket`.
String deviceTier({
  required String ramClass,
  required bool hasGpu,
  required bool ranOnGpu,
}) => '$ramClass-${hasGpu ? 'gpu' : 'nogpu'}-${ranOnGpu ? 'gpu' : 'cpu'}';

/// Whether a compute backend (`telemetryBackend`, `optimalBackend`) runs on
/// a GPU or another accelerator (Core ML, DirectML).
bool backendIsGpu(String? backend) => switch (backend) {
  'cuda' || 'metal' || 'vulkan' || 'coreml' || 'directml' => true,
  _ => false,
};

/// A new dictation that starts within this time after the previous one was
/// inserted counts as a quick repeat: the user probably dictated again
/// because the first result was wrong.
const Duration kQuickRedictationWindow = Duration(seconds: 15);

/// Whether a dictation started at [startedAt] repeats the one inserted at
/// [lastInsertedAt] quickly. `false` without an earlier insertion, and for a
/// clock that went backwards.
bool isQuickRedictation({
  required DateTime? lastInsertedAt,
  required DateTime startedAt,
}) {
  if (lastInsertedAt == null) return false;
  final gap = startedAt.difference(lastInsertedAt);
  return !gap.isNegative && gap <= kQuickRedictationWindow;
}

/// An undo right after a paste counts for the pasted dictation's model only
/// within this time; a later one is matched to the model in use now.
const Duration kUndoAfterPasteWindow = Duration(seconds: 60);

/// How long after an auto-paste the native watch looks for the user's own
/// undo shortcut in the target app (#2078). Short on purpose: input is only
/// observed this long, and a later undo rarely means the dictation was wrong.
const Duration kUndoShortcutWindow = Duration(seconds: 15);

/// Which WhisPaste undo took back a dictation right after it was pasted.
enum UndoAfterPasteSource {
  /// "Rückgängig" in the notice after a Smart Mode dictation.
  smartMode('smart_mode'),

  /// The undo of a selection edit that changed names (DEV-165).
  selectionEdit('selection_edit'),

  /// The system undo shortcut (Ctrl+Z, Cmd+Z) pressed by the user in the
  /// target app within [kUndoShortcutWindow] after an auto-paste, seen by
  /// the native watch (#2078).
  shortcut('shortcut');

  const UndoAfterPasteSource(this.id);
  final String id;
}

/// Whether a paste at [pastedAt] is still the one an undo at [now] takes
/// back ([kUndoAfterPasteWindow]).
bool isUndoRightAfterPaste({
  required DateTime? pastedAt,
  required DateTime now,
}) {
  if (pastedAt == null) return false;
  final gap = now.difference(pastedAt);
  return !gap.isNegative && gap <= kUndoAfterPasteWindow;
}

final _allowedChars = RegExp(r'^[A-Za-z0-9._:|>/+-]{1,240}$');
final _driveLetter = RegExp(r'(^|[|>:])[A-Za-z]:[/\\]');
final _slashPart = RegExp(r'^(hf:[^/:]+/[^/:]+/[^/:]+|url:[^/:]+(/[^/:]+)?)$');

/// Whether [value] may leave the app as a model event name. The negative
/// list (internal-notes §6.5): nothing that could carry a full address, a query,
/// credentials, a local path, a user name or free text. Rejects `://`, `@`,
/// `?`, `#`, `=`, `&`, `%`, `~`, `\`, whitespace, `..`, `//`, a leading `/`,
/// a drive letter, any other character outside `A-Z a-z 0-9 . _ : | > / + -`
/// and values over 240 characters. A `/` is only allowed inside an `hf:` or
/// `url:` key.
bool isTelemetrySafeName(String value) {
  if (!_allowedChars.hasMatch(value)) return false;
  if (value.contains('://') ||
      value.contains('..') ||
      value.contains('//') ||
      value.startsWith('/')) {
    return false;
  }
  if (_driveLetter.hasMatch(value)) return false;
  for (final part in value.split(RegExp(r'[|>]'))) {
    if (part.contains('/') && !_slashPart.hasMatch(part)) return false;
  }
  return true;
}

/// `model/dictation` name: `<model>|<device>|<ok|fail>|<rtf class|na>`.
/// [rtf] comes from `rtfBucket`; a failed run or a missing time gives `na`.
String dictationQualityName({
  required String modelKey,
  required String device,
  required bool ok,
  required String? rtf,
}) => '$modelKey|$device|${ok ? 'ok' : 'fail'}|${rtf ?? 'na'}';
