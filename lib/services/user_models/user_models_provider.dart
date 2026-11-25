/// The user's own models (#1789) for the model library (#1514): the list in
/// `user_models.json`, one running addition with its progress, and the steps
/// from what the user typed or picked to a [UserModelDraft].
///
/// The page never touches [UserModelStore] or [UserModelInstaller] itself;
/// it reads [userModelsProvider] and calls its notifier. Nothing here logs an
/// address or a path.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../model_hardware_telemetry.dart'
    show ModelLifecycleTelemetry, modelLifecycleTelemetryProvider;
import '../model_telemetry_identity.dart' show ownModelFactsFrom, ownModelKey;
import '../stt/stt_benchmark.dart' show SttBenchmark;
import 'hf_repo_resolver.dart';
import 'user_model.dart';
import 'user_model_address.dart';
import 'user_model_checker.dart';
import 'user_model_detection.dart';
import 'user_model_installer.dart';
import 'user_model_store.dart';

final _log = AppLogger('UserModels');

/// Why what the user entered does not make a model. The page says each in
/// words (`userModelSourceErrorText`).
enum UserModelSourceError {
  /// Not an HTTPS address WhisPaste accepts (see [UserModelAddressError]).
  address,

  /// No such Hugging Face repo, or a private one.
  notFound,

  /// The repo needs a login; WhisPaste downloads anonymously only.
  gated,

  /// The source could not be reached.
  network,

  /// No file the app can run was found.
  noModel,

  /// The files are a model for the other section (a speech model offered
  /// for Smart Mode, or the other way round).
  wrongPurpose,

  /// A model of several files was given as one address; it needs the repo
  /// address or all its files.
  needsAllFiles,
}

/// The outcome of [prepareDraftFromAddress] and [prepareDraftFromFiles].
sealed class UserModelSourceResult {
  const UserModelSourceResult();
}

/// A draft, ready for the preflight.
final class UserModelSourceOk extends UserModelSourceResult {
  const UserModelSourceOk(this.draft);
  final UserModelDraft draft;
}

/// The reason no draft could be made.
final class UserModelSourceFailed extends UserModelSourceResult {
  const UserModelSourceFailed(this.error);
  final UserModelSourceError error;
}

/// Reads a Hugging Face repo; replaced in tests.
typedef HfRepoResolve = Future<HfRepoSnapshot> Function(HuggingFaceAddress);

/// Asks a server for a file's size; replaced in tests.
typedef RemoteSizeProbe =
    Future<int?> Function(String url, Set<String> confirmedHosts);

/// The first candidate of [candidates] that runs for [purpose], or why none.
({UserModelCandidate? candidate, UserModelSourceError? error}) _pick(
  List<UserModelCandidate> candidates,
  UserModelPurpose purpose,
) {
  if (candidates.isEmpty) {
    return (candidate: null, error: UserModelSourceError.noModel);
  }
  for (final c in candidates) {
    if (c.runtime.purpose == purpose) return (candidate: c, error: null);
  }
  return (candidate: null, error: UserModelSourceError.wrongPurpose);
}

/// A draft from an address the user typed: a Hugging Face repo (any of its
/// usual forms) or one direct HTTPS file. [purpose] is the section the user
/// adds to; a model for the other section is refused with
/// [UserModelSourceError.wrongPurpose].
Future<UserModelSourceResult> prepareDraftFromAddress(
  String input, {
  required UserModelPurpose purpose,
  required Set<String> confirmedHosts,
  HfRepoResolve? resolve,
  RemoteSizeProbe? probeSize,
}) async {
  final address = UserModelAddress.parse(input);
  switch (address) {
    case RejectedAddress():
      return const UserModelSourceFailed(UserModelSourceError.address);
    case HuggingFaceAddress():
      final HfRepoSnapshot snapshot;
      try {
        snapshot = await (resolve ?? resolveHfRepo)(address);
      } on HfResolveException catch (e) {
        return UserModelSourceFailed(switch (e.error) {
          HfResolveError.notFound ||
          HfResolveError.pathMissing => UserModelSourceError.notFound,
          HfResolveError.gated => UserModelSourceError.gated,
          HfResolveError.network ||
          HfResolveError.badResponse => UserModelSourceError.network,
        });
      }
      final picked = _pick(
        detectUserModelCandidates(snapshot.files, repoName: snapshot.repoId),
        purpose,
      );
      if (picked.candidate == null) return UserModelSourceFailed(picked.error!);
      return UserModelSourceOk(
        draftFromHfSnapshot(snapshot, picked.candidate!),
      );
    case DirectFileAddress():
      final runtime = runtimeForFileName(address.fileName);
      if (runtime == null) {
        return const UserModelSourceFailed(UserModelSourceError.noModel);
      }
      if (runtime.purpose != purpose) {
        return const UserModelSourceFailed(UserModelSourceError.wrongPurpose);
      }
      // sherpa-onnx models are several files: one address is never enough.
      if (runtime == UserModelRuntime.sherpaOnnx) {
        return const UserModelSourceFailed(UserModelSourceError.needsAllFiles);
      }
      final result = draftFromDirectUrls([address], runtime: runtime);
      if (result is! DraftOk) {
        return const UserModelSourceFailed(UserModelSourceError.noModel);
      }
      final draft = result.draft;
      int? size;
      try {
        size = await (probeSize ?? _probeSize)(
          address.uri.toString(),
          confirmedHosts,
        );
      } on Object {
        // An unconfirmed redirect or no answer: the size stays unknown, which
        // never blocks (preflight), and the download checks the host again.
        size = null;
      }
      if (size == null || size <= 0) return UserModelSourceOk(draft);
      return UserModelSourceOk(
        draft.withSizes({draft.files.single.name: size}),
      );
  }
}

Future<int?> _probeSize(String url, Set<String> confirmedHosts) async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'User-Agent': 'WhisPaste'},
    ),
  );
  try {
    return await probeRemoteSize(dio, url, confirmedHosts: confirmedHosts);
  } finally {
    dio.close();
  }
}

/// A draft from files the user picked or dropped. [sizes] maps each path to
/// its size; [prepareDraftFromFiles] reads them from disk when omitted.
UserModelSourceResult prepareDraftFromFiles(
  List<String> paths, {
  required UserModelPurpose purpose,
  Map<String, int>? sizes,
}) {
  if (paths.isEmpty) {
    return const UserModelSourceFailed(UserModelSourceError.noModel);
  }
  final sideFiles = sizes == null
      ? sherpaSideFilesNear(paths)
      : const <String, String>{};
  final sizeOf =
      sizes ??
      {
        for (final path in [...paths, ...sideFiles.values]) path: _sizeOf(path),
      };
  // Picked files by their name, side files found next to them by their path
  // relative to the picked files' folder (`tokenizer/vocab.json`).
  final byPath = {
    for (final path in paths) p.basename(path): path,
    ...sideFiles,
  };
  final sources = [
    for (final e in byPath.entries)
      SourceFile(path: e.key, sizeBytes: sizeOf[e.value] ?? 0),
  ];
  // The folder name says what a sherpa-onnx model is, as the repo name does.
  final folder = p.basename(p.dirname(paths.first));
  final picked = _pick(
    detectUserModelCandidates(sources, repoName: folder),
    purpose,
  );
  UserModelRuntime? runtime = picked.candidate?.runtime;
  final family = picked.candidate?.family;
  if (picked.candidate == null && paths.length == 1) {
    // One file whose name follows no known scheme: its ending decides.
    runtime = runtimeForFileName(paths.single);
    if (runtime == null || runtime == UserModelRuntime.sherpaOnnx) {
      return UserModelSourceFailed(
        runtime == null
            ? UserModelSourceError.noModel
            : UserModelSourceError.needsAllFiles,
      );
    }
    if (runtime.purpose != purpose) {
      return const UserModelSourceFailed(UserModelSourceError.wrongPurpose);
    }
  }
  if (runtime == null) return UserModelSourceFailed(picked.error!);
  final chosen = picked.candidate;
  final usedPaths = chosen == null
      ? paths
      : [for (final f in chosen.files) byPath[f.source.path]!];
  final result = draftFromLocalFiles(
    usedPaths,
    runtime: runtime,
    family: family,
    sizes: sizeOf,
  );
  return switch (result) {
    DraftOk(:final draft) => UserModelSourceOk(draft),
    _ => const UserModelSourceFailed(UserModelSourceError.needsAllFiles),
  };
}

/// The tokens and tokenizer files (`isSherpaSideFileName`) next to [paths]
/// or in a folder directly below them, keyed by their path relative to that
/// folder. A user who picks only the ONNX files of a sherpa-onnx model thus
/// still gets a whole model, whatever family it is. Empty when the files
/// come from different folders.
Map<String, String> sherpaSideFilesNear(List<String> paths) {
  final folders = {for (final path in paths) p.dirname(path)};
  if (folders.length != 1 ||
      !paths.any((x) => x.toLowerCase().endsWith('.onnx'))) {
    return const {};
  }
  final folder = folders.single;
  final picked = {for (final path in paths) p.basename(path)};
  final found = <String, String>{};
  void scan(Directory dir, String prefix) {
    for (final entity in dir.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is File && isSherpaSideFileName(name)) {
        final key = prefix.isEmpty ? name : '$prefix/$name';
        if (prefix.isNotEmpty || !picked.contains(name)) {
          found[key] = entity.path;
        }
      } else if (entity is Directory && prefix.isEmpty) {
        scan(entity, name);
      }
    }
  }

  try {
    scan(Directory(folder), '');
  } on FileSystemException {
    return const {};
  }
  return found;
}

int _sizeOf(String path) {
  try {
    return File(path).lengthSync();
  } on FileSystemException {
    return 0;
  }
}

/// What the library knows about the user's own models right now.
class UserModelsState {
  const UserModelsState({
    this.models = const [],
    this.confirmedHosts = const {},
    this.installingId,
    this.progress,
    this.hfSearchConsent = false,
  });

  final List<UserModel> models;
  final Set<String> confirmedHosts;

  /// Whether the Hugging-Face-Suche may ask huggingface.co (#2047).
  final bool hfSearchConsent;

  /// The model being fetched or checked, or null.
  final String? installingId;

  /// Progress of [installingId].
  final UserModelInstallProgress? progress;

  bool get busy => installingId != null;

  /// Percent of [progress], 0 while the size is unknown.
  int get percent {
    final pr = progress;
    if (pr == null || pr.totalBytes <= 0) return 0;
    return (pr.bytesDone * 100 ~/ pr.totalBytes).clamp(0, 100);
  }

  /// The models for one section.
  List<UserModel> forPurpose(UserModelPurpose purpose) => [
    for (final m in models)
      if (m.purpose == purpose) m,
  ];

  UserModelsState copyWith({
    List<UserModel>? models,
    Set<String>? confirmedHosts,
    String? installingId,
    UserModelInstallProgress? progress,
    bool clearInstalling = false,
    bool? hfSearchConsent,
  }) => UserModelsState(
    models: models ?? this.models,
    confirmedHosts: confirmedHosts ?? this.confirmedHosts,
    hfSearchConsent: hfSearchConsent ?? this.hfSearchConsent,
    installingId: clearInstalling ? null : installingId ?? this.installingId,
    progress: clearInstalling ? null : progress ?? this.progress,
  );
}

/// The store; replaced in tests with one under a temp folder.
final userModelStoreProvider = Provider<UserModelStore>(
  (_) => UserModelStore(),
);

/// The installer; replaced in tests with one that has a fake checker.
final userModelInstallerProvider = Provider<UserModelInstaller>((ref) {
  final store = ref.watch(userModelStoreProvider);
  return UserModelInstaller(
    store: store,
    checker: defaultUserModelChecker(
      store: store,
      clip: SttBenchmark.referenceWav,
    ),
  );
});

/// Lists, adds, retries and removes the user's own models.
class UserModelsNotifier extends Notifier<UserModelsState> {
  bool _cancelled = false;

  @override
  UserModelsState build() {
    final installer = ref.watch(userModelInstallerProvider);
    try {
      // A check a previous run never finished cannot be trusted.
      installer.recoverAtStart();
    } on Object catch (e) {
      _log.warning('Recovering own models failed: ${e.runtimeType}');
    }
    return _read();
  }

  UserModelsState _read() {
    try {
      final data = ref.read(userModelStoreProvider).readSync();
      return UserModelsState(
        models: data.models,
        confirmedHosts: data.confirmedHosts,
        hfSearchConsent: data.hfSearchConsent,
      );
    } on Object catch (e) {
      _log.warning('Reading own models failed: ${e.runtimeType}');
      return const UserModelsState();
    }
  }

  /// Reads `user_models.json` again, e.g. after a model failed in use.
  void reload() {
    final fresh = _read();
    state = state.copyWith(
      models: fresh.models,
      confirmedHosts: fresh.confirmedHosts,
      hfSearchConsent: fresh.hfSearchConsent,
    );
  }

  /// Agrees to or revokes the Hugging-Face-Suche (#2047).
  void setHfSearchConsent(bool value) {
    try {
      ref.read(userModelInstallerProvider).setHfSearchConsent(value);
    } on Object catch (e) {
      _log.warning('Storing the search consent failed: ${e.runtimeType}');
    }
    reload();
  }

  /// Remembers [hosts] as confirmed by the user.
  void confirmHosts(Set<String> hosts) {
    if (hosts.isEmpty) return;
    ref.read(userModelInstallerProvider).confirmHosts(hosts);
    reload();
  }

  /// Adds [draft] (after its preflight passed) and returns the final entry,
  /// ready or failed with its reason. One addition at a time.
  Future<UserModel?> install(UserModelDraft draft) async {
    if (state.busy) return null;
    _cancelled = false;
    final id = newUserModelId();
    state = state.copyWith(
      installingId: id,
      progress: UserModelInstallProgress(
        bytesDone: 0,
        totalBytes: draft.totalBytes,
      ),
    );
    try {
      final result = await ref
          .read(userModelInstallerProvider)
          .install(
            draft,
            id: id,
            onProgress: (pr) => state = state.copyWith(progress: pr),
            // Listed from the start, so its progress shows in the section.
            onSaved: reload,
          );
      // A stopped addition leaves nothing behind: no failed entry, no files.
      if (_cancelled) {
        ref.read(userModelInstallerProvider).remove(id);
        return null;
      }
      _reportAdded(result);
      return result;
    } on Object catch (e) {
      _log.warning('Adding $id failed: ${e.runtimeType}');
      return null;
    } finally {
      state = state.copyWith(clearInstalling: true);
      reload();
    }
  }

  /// Fetches a failed model again and checks it once more.
  Future<void> retry(String id) async {
    if (state.busy) return;
    _cancelled = false;
    state = state.copyWith(installingId: id);
    try {
      final result = await ref
          .read(userModelInstallerProvider)
          .retry(id, onProgress: (pr) => state = state.copyWith(progress: pr));
      // A file from this computer is not fetched again: nothing happened.
      if (result != null &&
          !_cancelled &&
          result.sourceKind != UserModelSourceKind.file) {
        _reportAdded(result);
      }
    } on Object catch (e) {
      _log.warning('Retrying $id failed: ${e.runtimeType}');
    } finally {
      state = state.copyWith(clearInstalling: true);
      reload();
    }
  }

  /// Stops the running download; the addition then ends as failed.
  /// A new addition that is stopped leaves nothing behind.
  void cancel() {
    _cancelled = state.busy;
    ref.read(userModelInstallerProvider).cancel();
  }

  /// Removes model [id] and its files.
  void remove(String id) {
    UserModel? removed;
    for (final m in state.models) {
      if (m.id == id) removed = m;
    }
    try {
      ref.read(userModelInstallerProvider).remove(id);
      if (removed != null) {
        _telemetry((t) => t.removed(ownModelKey(ownModelFactsFrom(removed!))));
      }
    } on Object catch (e) {
      _log.warning('Removing $id failed: ${e.runtimeType}');
    }
    reload();
  }

  /// Usage statistics for the end of an addition or retry (#1791).
  void _reportAdded(UserModel model) =>
      _telemetry((t) => t.ownModelAdded(model));

  /// Telemetry never breaks adding or removing a model.
  void _telemetry(void Function(ModelLifecycleTelemetry t) send) {
    try {
      send(ref.read(modelLifecycleTelemetryProvider));
    } on Object catch (e) {
      _log.debug('model telemetry skipped: ${e.runtimeType}');
    }
  }
}

final userModelsProvider =
    NotifierProvider<UserModelsNotifier, UserModelsState>(
      UserModelsNotifier.new,
    );
