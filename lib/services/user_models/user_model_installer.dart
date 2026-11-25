/// Adds a model of the user's own (#1789): from a Hugging Face repo, direct
/// HTTPS addresses or files on the computer, up to a checked entry in
/// `user_models.json`.
///
/// The order the acceptance asks for:
/// 1. [UserModelDraft]: what will be downloaded, built from the source
///    ([draftFromHfSnapshot], [draftFromDirectUrls], [draftFromLocalFiles]).
///    Hugging Face files are pinned to one commit here.
/// 2. [preflightUserModel]: terms confirmed, every host outside the fixed
///    allowlist confirmed by the user, size against free space. Nothing is
///    downloaded before it passes.
/// 3. [UserModelInstaller.install]: download (or copy), SHA-256 against the
///    source's hash or, without one, remembered on first download, then the
///    check in its own process ([UserModelChecker]). Only a passed check
///    makes the model ready.
///
/// Pure parts are top-level functions for tests. Nothing here logs an
/// address or a path: ids only.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../download_allowlist.dart';
import '../file_verification_service.dart' show sha256HexOfFile;
import '../http_model_fetcher.dart';
import '../path_service.dart' show userModelIdPrefix, userWhisperModelFilename;
import 'hf_repo_resolver.dart';
import 'user_model.dart';
import 'user_model_address.dart';
import 'user_model_checker.dart';
import 'user_model_detection.dart';
import 'user_model_store.dart';

final _log = AppLogger('UserModelInstaller');

/// Everything known about a model before its files are fetched.
class UserModelDraft {
  const UserModelDraft({
    required this.name,
    required this.runtime,
    required this.sourceKind,
    required this.files,
    this.family,
    this.sourceAddress,
    this.revision,
    this.license,
    this.localPaths = const {},
  });

  final String name;
  final UserModelRuntime runtime;
  final SherpaFamily? family;
  final UserModelSourceKind sourceKind;

  /// The page linked next to the terms confirmation.
  final String? sourceAddress;
  final String? revision;
  final String? license;
  final List<UserModelFile> files;

  /// For [UserModelSourceKind.file]: target file name → picked path.
  final Map<String, String> localPaths;

  /// Sum of the known sizes; 0 when no source said.
  int get totalBytes => files.fold(0, (s, f) => s + f.sizeBytes);

  /// Whether every file has a known size, so free space can be checked.
  bool get sizeKnown => files.every((f) => f.sizeBytes > 0);

  /// Hosts the files are fetched from, lower case.
  Set<String> get hosts => {
    for (final f in files)
      if (f.url != null) Uri.parse(f.url!).host.toLowerCase(),
  };

  UserModelDraft withSizes(Map<String, int> sizeByName) => UserModelDraft(
    name: name,
    runtime: runtime,
    family: family,
    sourceKind: sourceKind,
    sourceAddress: sourceAddress,
    revision: revision,
    license: license,
    localPaths: localPaths,
    files: [
      for (final f in files)
        sizeByName[f.name] == null
            ? f
            : f.copyWith(sizeBytes: sizeByName[f.name]),
    ],
  );
}

/// The file name a model file gets inside its folder. whisper.cpp models
/// always get [userWhisperModelFilename] so the speech path finds them by id
/// alone (`sttModelPath`); a role the runtime looks up by name keeps that
/// name ([UserModelFileRole.fixedFileName]).
String targetFileName(
  UserModelRuntime runtime,
  UserModelFileRole role,
  String sourceName,
) {
  if (runtime == UserModelRuntime.whispercpp &&
      role == UserModelFileRole.model) {
    return userWhisperModelFilename;
  }
  final fixed = role.fixedFileName;
  if (fixed != null) return fixed;
  final base = sourceName.split(RegExp(r'[/\\]')).last;
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (safe.isEmpty || safe == '.' || safe == '..') return '${role.value}.bin';
  return safe;
}

/// A draft for one [candidate] of a Hugging Face [snapshot]: every file is
/// pinned to the snapshot's commit, and the LFS hash comes along.
UserModelDraft draftFromHfSnapshot(
  HfRepoSnapshot snapshot,
  UserModelCandidate candidate,
) => UserModelDraft(
  name: snapshot.repoId,
  runtime: candidate.runtime,
  family: candidate.family,
  sourceKind: UserModelSourceKind.huggingFace,
  sourceAddress: 'https://huggingface.co/${snapshot.repoId}',
  revision: snapshot.commit,
  license: snapshot.license,
  files: [
    for (final f in candidate.files)
      UserModelFile(
        role: f.role,
        name: targetFileName(candidate.runtime, f.role, f.source.baseName),
        url: huggingFaceResolveUrl(
          repoId: snapshot.repoId,
          commit: snapshot.commit,
          path: f.source.path,
        ),
        sizeBytes: f.source.sizeBytes,
        sha256: f.source.sha256,
      ),
  ],
);

/// Why direct addresses or picked files do not make a model.
enum DraftError {
  /// The runtime/family needs other files than given.
  filesDoNotMatch,

  /// Two files would end up under the same name.
  duplicateName,
}

/// Result of [draftFromDirectUrls] and [draftFromLocalFiles].
sealed class DraftResult {
  const DraftResult();
}

final class DraftOk extends DraftResult {
  const DraftOk(this.draft);
  final UserModelDraft draft;
}

final class DraftFailed extends DraftResult {
  const DraftFailed(this.error, {this.missing = const []});

  /// Why the preflight failed: a duplicate name asks for another name,
  /// unmatched files for other files.
  // loam-ignore: unused-public-exports – the failure reason of the result type; the import UI (#1789) tells the two cases apart
  final DraftError error;

  /// The roles no file was found for.
  final List<UserModelFileRole> missing;
}

/// A draft from direct HTTPS file addresses. The user picked [runtime] and,
/// for sherpa-onnx, [family]; the file names decide the roles.
DraftResult draftFromDirectUrls(
  List<DirectFileAddress> addresses, {
  required UserModelRuntime runtime,
  SherpaFamily? family,
}) {
  final byPath = {for (final a in addresses) a.fileName: a};
  final sources = [for (final a in addresses) SourceFile(path: a.fileName)];
  final assigned = _assignFiles(sources, runtime, family);
  if (assigned is! _Assigned) return assigned as DraftFailed;
  final first = addresses.first;
  return DraftOk(
    UserModelDraft(
      name: _displayName(assigned.files, runtime),
      runtime: runtime,
      family: runtime == UserModelRuntime.sherpaOnnx ? family : null,
      sourceKind: UserModelSourceKind.url,
      sourceAddress: first.uri.toString(),
      files: [
        for (final d in assigned.files)
          UserModelFile(
            role: d.role,
            name: targetFileName(runtime, d.role, d.source.baseName),
            url: byPath[d.source.path]!.uri.toString(),
          ),
      ],
    ),
  );
}

/// A draft from files the user picked or dropped. [paths] are local paths;
/// they stay on this computer and are only read when the model is added.
DraftResult draftFromLocalFiles(
  List<String> paths, {
  required UserModelRuntime runtime,
  SherpaFamily? family,
  Map<String, int> sizes = const {},
}) {
  final byName = {for (final path in paths) p.basename(path): path};
  final sources = [
    for (final path in paths)
      SourceFile(path: p.basename(path), sizeBytes: sizes[path] ?? 0),
  ];
  final assigned = _assignFiles(sources, runtime, family);
  if (assigned is! _Assigned) return assigned as DraftFailed;
  final localPaths = <String, String>{};
  final files = <UserModelFile>[];
  for (final d in assigned.files) {
    final name = targetFileName(runtime, d.role, d.source.baseName);
    localPaths[name] = byName[d.source.path]!;
    files.add(
      UserModelFile(role: d.role, name: name, sizeBytes: d.source.sizeBytes),
    );
  }
  return DraftOk(
    UserModelDraft(
      name: _displayName(assigned.files, runtime),
      runtime: runtime,
      family: runtime == UserModelRuntime.sherpaOnnx ? family : null,
      sourceKind: UserModelSourceKind.file,
      files: files,
      localPaths: localPaths,
    ),
  );
}

/// Files given by name, matched to the roles [runtime] (and [family]) need.
final class _Assigned extends DraftResult {
  const _Assigned(this.files);
  final List<DetectedFile> files;
}

DraftResult _assignFiles(
  List<SourceFile> files,
  UserModelRuntime runtime,
  SherpaFamily? family,
) {
  if (files.isEmpty) return const DraftFailed(DraftError.filesDoNotMatch);
  final List<DetectedFile> detected;
  if (runtime == UserModelRuntime.sherpaOnnx) {
    if (family == null) return const DraftFailed(DraftError.filesDoNotMatch);
    switch (assignSherpaRoles(family, files)) {
      case SherpaRolesMissing(:final missing):
        return DraftFailed(DraftError.filesDoNotMatch, missing: missing);
      case SherpaRolesAssigned(files: final assigned):
        detected = assigned;
    }
  } else {
    if (files.length != 1) return const DraftFailed(DraftError.filesDoNotMatch);
    detected = [
      DetectedFile(role: UserModelFileRole.model, source: files.first),
    ];
  }
  final names = <String>{};
  for (final d in detected) {
    if (!names.add(targetFileName(runtime, d.role, d.source.baseName))) {
      return const DraftFailed(DraftError.duplicateName);
    }
  }
  return _Assigned(detected);
}

String _displayName(List<DetectedFile> files, UserModelRuntime runtime) {
  final main = files.firstWhere(
    (f) => f.role != UserModelFileRole.tokens,
    orElse: () => files.first,
  );
  return main.source.baseName;
}

/// What stops a draft before the download.
sealed class PreflightIssue {
  const PreflightIssue();
}

/// The terms confirmation is not ticked.
final class TermsNotConfirmed extends PreflightIssue {
  const TermsNotConfirmed();
}

/// [hosts] are outside the fixed allowlist and not yet confirmed.
final class HostsNotConfirmed extends PreflightIssue {
  const HostsNotConfirmed(this.hosts);
  final Set<String> hosts;
}

/// The disk cannot hold the files.
final class NotEnoughSpace extends PreflightIssue {
  const NotEnoughSpace({required this.neededBytes, required this.freeBytes});
  final int neededBytes;
  final int freeBytes;
}

/// Head room kept free next to the model, so the disk is not filled to the
/// last byte (temp files, the history database).
const int kUserModelSpaceReserveBytes = 200 * 1024 * 1024;

/// The hosts of [draft] the user still has to confirm.
Set<String> hostsToConfirm(UserModelDraft draft, Set<String> confirmed) => {
  for (final host in draft.hosts)
    if (!isOnDownloadAllowlist(host) && !confirmed.contains(host)) host,
};

/// The first reason [draft] may not be downloaded yet, or null. [freeBytes]
/// null (unknown) never blocks, as for catalog downloads.
PreflightIssue? preflightUserModel(
  UserModelDraft draft, {
  required bool termsConfirmed,
  required Set<String> confirmedHosts,
  required int? freeBytes,
}) {
  if (!termsConfirmed) return const TermsNotConfirmed();
  final hosts = hostsToConfirm(draft, confirmedHosts);
  if (hosts.isNotEmpty) return HostsNotConfirmed(hosts);
  final needed = draft.totalBytes + kUserModelSpaceReserveBytes;
  if (freeBytes != null && draft.totalBytes > 0 && freeBytes < needed) {
    return NotEnoughSpace(neededBytes: needed, freeBytes: freeBytes);
  }
  return null;
}

/// Outcome of comparing a fetched file's hash with what is known.
enum HashCheck {
  /// Matches the hash the source named or the one seen before.
  matches,

  /// No hash known yet: this one is remembered (trust on first use).
  remembered,

  /// Differs: the file changed since it was first seen.
  changed,
}

/// Compares [actual] with [expected] (lower-case hex).
HashCheck compareFileHash({required String? expected, required String actual}) {
  if (expected == null || expected.isEmpty) return HashCheck.remembered;
  return expected.toLowerCase() == actual.toLowerCase()
      ? HashCheck.matches
      : HashCheck.changed;
}

/// A new model id: `user-` and 12 hex digits.
String newUserModelId([Random? random]) {
  final r = random ?? Random.secure();
  final hex = List.generate(
    6,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return '$userModelIdPrefix$hex';
}

/// Asks [url] for its size without downloading it: a one-byte range request,
/// read from `Content-Range` (or `Content-Length` when ranges are not
/// served). Null when the server does not say. Throws
/// [DownloadHostNotConfirmedException] on a redirect to an unconfirmed host.
Future<int?> probeRemoteSize(
  Dio dio,
  String url, {
  required Set<String> confirmedHosts,
}) async {
  final token = CancelToken();
  try {
    final response = await getWithAllowlistedRedirects<ResponseBody>(
      dio,
      url,
      cancelToken: token,
      confirmedHosts: confirmedHosts,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-0'},
      ),
    );
    final size = sizeFromHeaders(
      status: response.statusCode ?? 0,
      contentRange: response.headers.value('content-range'),
      contentLength: response.headers.value('content-length'),
    );
    token.cancel();
    return size;
  } on DioException {
    return null;
  }
}

/// Reads the full size from the headers of a `Range: bytes=0-0` answer.
int? sizeFromHeaders({
  required int status,
  String? contentRange,
  String? contentLength,
}) {
  if (status == 206 && contentRange != null) {
    final slash = contentRange.lastIndexOf('/');
    if (slash >= 0) {
      final total = int.tryParse(contentRange.substring(slash + 1).trim());
      if (total != null && total > 0) return total;
    }
    return null;
  }
  if (status == 200 && contentLength != null) {
    final n = int.tryParse(contentLength.trim());
    if (n != null && n > 0) return n;
  }
  return null;
}

/// Progress of [UserModelInstaller.install].
class UserModelInstallProgress {
  const UserModelInstallProgress({
    required this.bytesDone,
    required this.totalBytes,
    this.checking = false,
  });

  final int bytesDone;
  final int totalBytes;

  /// Files are in place, the check runs.
  final bool checking;
}

/// Fetches, verifies and checks a draft; keeps `user_models.json` current.
class UserModelInstaller {
  UserModelInstaller({
    required this.store,
    required this.checker,
    HttpModelFetcher Function(Set<String> confirmedHosts)? fetcherFor,
  }) : _fetcherFor =
           fetcherFor ?? ((hosts) => HttpModelFetcher(confirmedHosts: hosts));

  final UserModelStore store;
  final UserModelChecker checker;
  final HttpModelFetcher Function(Set<String>) _fetcherFor;
  HttpModelFetcher? _running;

  /// Remembers [hosts] as confirmed by the user.
  void confirmHosts(Set<String> hosts) {
    final data = store.readSync();
    store.writeSync(
      data.copyWith(
        confirmedHosts: {
          ...data.confirmedHosts,
          for (final h in hosts) h.toLowerCase(),
        },
      ),
    );
  }

  /// Stores whether the Hugging-Face-Suche may ask huggingface.co (#2047).
  void setHfSearchConsent(bool value) {
    store.writeSync(store.readSync().copyWith(hfSearchConsent: value));
  }

  /// Adds [draft] as a new model and returns its final entry (ready or
  /// failed with the reason). Call [preflightUserModel] first. [onSaved]
  /// runs once the entry is in `user_models.json`, before the download, so
  /// the list can show it with its progress.
  Future<UserModel> install(
    UserModelDraft draft, {
    void Function(UserModelInstallProgress)? onProgress,
    void Function()? onSaved,
    String? id,
    DateTime? now,
  }) async {
    final model = UserModel(
      id: id ?? newUserModelId(),
      name: draft.name,
      runtime: draft.runtime,
      family: draft.family,
      sourceKind: draft.sourceKind,
      sourceAddress: draft.sourceAddress,
      revision: draft.revision,
      license: draft.license,
      files: draft.files,
      addedAt: now ?? DateTime.now().toUtc(),
    );
    _save(model);
    onSaved?.call();
    return _fetchAndCheck(model, draft.localPaths, onProgress);
  }

  /// Fetches the files of [id] again (after "file changed" or a failed
  /// download) and checks it once more. Remembered hashes stay: a file that
  /// differs from the first download is still reported as changed.
  Future<UserModel?> retry(
    String id, {
    void Function(UserModelInstallProgress)? onProgress,
  }) async {
    final model = store.readSync().byId(id);
    if (model == null || model.sourceKind == UserModelSourceKind.file) {
      return model;
    }
    final again = model.copyWith(
      status: UserModelStatus.checking,
      clearFailure: true,
    );
    _save(again);
    return _fetchAndCheck(again, const {}, onProgress);
  }

  /// Stops a running download; [install] then ends as failed (download).
  void cancel() => _running?.cancel();

  /// Removes model [id] and its files. Allowed at any time.
  void remove(String id) {
    store.deleteModelFiles(id);
    store.writeSync(store.readSync().remove(id));
  }

  /// At start: a model a previous run died in (crash marker of the Mac App
  /// Store check) and any check that never finished are marked failed.
  /// Returns the ids that were marked.
  List<String> recoverAtStart() {
    final crashed = store.takeCrashedModelId();
    var data = store.readSync();
    final marked = <String>[];
    for (final m in data.models) {
      if (m.id == crashed) {
        data = data.upsert(
          m.copyWith(
            status: UserModelStatus.failed,
            failure: UserModelFailure.crashed,
          ),
        );
        marked.add(m.id);
      } else if (m.status == UserModelStatus.checking) {
        data = data.upsert(
          m.copyWith(
            status: UserModelStatus.failed,
            failure: UserModelFailure.checkUnavailable,
          ),
        );
        marked.add(m.id);
      }
    }
    if (marked.isNotEmpty) store.writeSync(data);
    return marked;
  }

  /// Takes model [id] out of use after it failed in use (#1789 fallback).
  void markFailedInUse(String id) {
    final model = store.readSync().byId(id);
    if (model == null) return;
    _save(
      model.copyWith(
        status: UserModelStatus.failed,
        failure: UserModelFailure.failedInUse,
      ),
    );
  }

  Future<UserModel> _fetchAndCheck(
    UserModel model,
    Map<String, String> localPaths,
    void Function(UserModelInstallProgress)? onProgress,
  ) async {
    final dir = store.modelDir(model.id);
    Directory(dir).createSync(recursive: true);
    final total = model.totalBytes;
    var done = 0;
    final files = <UserModelFile>[];
    for (final file in model.files) {
      final dest = p.join(dir, file.name);
      try {
        if (model.sourceKind == UserModelSourceKind.file) {
          final from = localPaths[file.name];
          if (from == null) throw const FileSystemException('missing');
          await File(from).copy(dest);
        } else {
          final fetcher = _fetcherFor(store.readSync().confirmedHosts);
          _running = fetcher;
          final base = done;
          await fetcher.fetch(
            url: file.url!,
            destPath: dest,
            expectedSize: file.sizeBytes,
            onProgress: (f) => onProgress?.call(
              UserModelInstallProgress(
                bytesDone: base + f.bytesReceived,
                totalBytes: total,
              ),
            ),
          );
        }
      } on Object catch (e) {
        _log.warning('Fetching a file of ${model.id} failed: ${e.runtimeType}');
        return _fail(model, UserModelFailure.download);
      } finally {
        _running = null;
      }
      final size = File(dest).lengthSync();
      done += size;
      final actual = await sha256HexOfFile(dest);
      switch (compareFileHash(expected: file.sha256, actual: actual)) {
        case HashCheck.changed:
          _log.warning('A file of ${model.id} differs from the first download');
          return _fail(model, UserModelFailure.fileChanged);
        case HashCheck.matches || HashCheck.remembered:
          files.add(file.copyWith(sizeBytes: size, sha256: actual));
      }
    }
    final fetched = model.copyWith(files: files);
    _save(fetched);
    onProgress?.call(
      UserModelInstallProgress(
        bytesDone: done,
        totalBytes: done,
        checking: true,
      ),
    );
    final report = await checker.check(fetched);
    final failure = report.failure;
    final result = failure == null
        ? fetched.copyWith(status: UserModelStatus.ready, clearFailure: true)
        : fetched.copyWith(status: UserModelStatus.failed, failure: failure);
    _save(result);
    return result;
  }

  UserModel _fail(UserModel model, UserModelFailure failure) {
    final failed = model.copyWith(
      status: UserModelStatus.failed,
      failure: failure,
    );
    _save(failed);
    return failed;
  }

  void _save(UserModel model) =>
      store.writeSync(store.readSync().upsert(model));
}
