/// Optional NVIDIA CUDA pack for on-device Whisper (Windows/Linux x64).
///
/// The bundled libwhisper runs on NVIDIA cards through Vulkan. A separately
/// downloaded pack adds ggml's CUDA backend (`ggml-cuda` plus the CUDA
/// runtime and cuBLAS libraries it imports), which measured 30–60 % faster
/// than Vulkan on mid-range cards (RTX 2060/3060, see
/// `tool/vast_cuda_bench.sh`). It is too large to bundle (~0.5–1 GB), so it
/// is offered as a download in Settings → Speech recognition, next to the
/// GPU-acceleration row, and only to NVIDIA users.
///
/// Layout: each pack is extracted to `<appData>/cuda/<packId>/` and is
/// considered installed only once every file matched its pinned SHA-256 and
/// the [kCudaPackInstalledMarker] was written as the very last step. The
/// pack must match the bundled ggml exactly (backend modules are not ABI
/// stable across ggml versions), hence the ggml version in the pack id: a
/// whisper.cpp bump ships a new pack id, and stale pack folders are swept.
///
/// Not offered in the Microsoft Store build: Store policy 10.2.2 forbids
/// extending an app's functionality with code downloaded after install.
library;

import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart' show extractFileToDisk;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../deploy_channel_service.dart';
import '../../file_verification_service.dart';
import '../../hardware_info_service.dart';
import '../../http_model_fetcher.dart';
import '../../path_service.dart';

final _log = AppLogger('CudaPack');

/// One file inside a pack, pinned by size and SHA-256.
@immutable
class CudaPackFile {
  const CudaPackFile(this.name, this.sizeBytes, this.sha256);
  final String name;
  final int sizeBytes;
  final String sha256;
}

/// A downloadable CUDA pack for one platform.
@immutable
class CudaPackInfo {
  const CudaPackInfo({
    required this.id,
    required this.url,
    required this.archiveSizeBytes,
    required this.archiveSha256,
    required this.files,
  });

  /// Folder name below [cudaPackRootDir], e.g. `ggml-v1.9.5-cu12.8-r1`.
  final String id;
  final String url;
  final int archiveSizeBytes;
  final String archiveSha256;

  /// Every file that must exist after extraction. Extra files are ignored.
  final List<CudaPackFile> files;

  /// Archive name as published (`.zip` on Windows, `.tar.gz` on Linux);
  /// the extension tells the extractor which format to read.
  String get archiveFileName => p.url.basename(Uri.parse(url).path);
}

/// Pack id: bundled ggml version, CUDA toolkit, pack revision.
const kCudaPackId = 'ggml-v1.9.5-cu12.8-r1';

/// Where the packs are published: a dedicated prerelease tagged
/// `cuda-<pack id>`, never marked latest. App releases are immutable once
/// published, so the packs cannot be attached to them afterwards; a pack
/// release is immutable too, which suits a pinned, checksummed download. A
/// new pack id gets a new tag.
const _kCudaPackBaseUrl =
    'https://github.com/whispaste/whispaste/releases/download/cuda-$kCudaPackId';

// Filled from the `manifest.json` that `tool/cuda_pack_build.sh` writes next
// to each built archive.
const _windowsPack = CudaPackInfo(
  id: kCudaPackId,
  url: '$_kCudaPackBaseUrl/WhisPaste-CUDA-$kCudaPackId-windows-x64.zip',
  archiveSizeBytes: 660507255,
  archiveSha256:
      '7f6c760ad90ff1c8dce181b2d8191232b29c484c847d8cdf7718658361a2fbd2',
  files: [
    CudaPackFile(
      'NOTICE.txt',
      2551,
      'b13494038094500c04516ad5a2591de28c7b5d3081a11b2d3acea4c0fc1be389',
    ),
    CudaPackFile(
      'SHA256SUMS',
      405,
      'e1e2fc37df49abe31c6893806c88c4947fd6d6cf32e2691e885ec84de77bf2ed',
    ),
    CudaPackFile(
      'cublas64_12.dll',
      113716224,
      '9513540e4ec4c51ee9e7304138c2cc255c29a8c181f9e80c38efa25738becd99',
    ),
    CudaPackFile(
      'cublasLt64_12.dll',
      674667520,
      'b199d1ff892a81b7fd3d57ba1781549609b41500b36008fef326038393ad46c7',
    ),
    CudaPackFile(
      'cudart64_12.dll',
      573952,
      'c2c9a9c22a9bcba90e261825968836787b331038047a26770cffb7a583c28344',
    ),
    CudaPackFile(
      'ggml-cuda.dll',
      106399744,
      'fe2c7c4d21e03bc127b77f270ee8e65523a7e6b78b8f0d4cd9dd7af32bb45800',
    ),
  ],
);

const _linuxPack = CudaPackInfo(
  id: kCudaPackId,
  url: '$_kCudaPackBaseUrl/WhisPaste-CUDA-$kCudaPackId-linux-x64.tar.gz',
  archiveSizeBytes: 686791429,
  archiveSha256:
      '60a9f5cf375729cf348af1f2969fa3b2f90bd816563ecd6116fc82580fdeb880',
  files: [
    CudaPackFile(
      'NOTICE.txt',
      2551,
      'b13494038094500c04516ad5a2591de28c7b5d3081a11b2d3acea4c0fc1be389',
    ),
    CudaPackFile(
      'SHA256SUMS',
      407,
      '10a2e84ab373167427430a07f95e074222690bf04ab75a52b5aee7db47262890',
    ),
    CudaPackFile(
      'libcublas.so.12',
      116388640,
      '031ce6c2cbfbb9468f040527cab5c599069ce5609e73e28f87503881063eac21',
    ),
    CudaPackFile(
      'libcublasLt.so.12',
      751771728,
      '10b5e6631cf8115c661eb895ed1533826308b58f7956466f53d236a40c9b622c',
    ),
    CudaPackFile(
      'libcudart.so.12',
      728800,
      'c3a75b33af334a3486d197dbd1584a2985183ba4688d237a2be5f2f679329920',
    ),
    CudaPackFile(
      'libggml-cuda.so',
      113861401,
      'cc6542715ac4b321a9bc35345fb86998f226646ae73b585f7a3102085791bfe9',
    ),
  ],
);

/// The pack for this machine, or `null` where none exists (macOS, ARM).
CudaPackInfo? cudaPackForThisPlatform() {
  final CudaPackInfo pack;
  switch (Abi.current()) {
    case Abi.windowsX64:
      pack = _windowsPack;
    case Abi.linuxX64:
      pack = _linuxPack;
    default:
      return null;
  }
  return pack.files.isEmpty ? null : pack;
}

/// Written last into a pack folder, after every file was verified.
const kCudaPackInstalledMarker = '.installed';

/// Root folder holding all pack versions.
String cudaPackRootDir() => p.join(appDataDir(), 'cuda');

/// Whether [pack] is fully installed below [rootDir].
///
/// Also compares every file's size with its pin: loading a truncated library
/// (disk error, antivirus, a user tidying up) crashes the process with SIGBUS
/// on Linux instead of failing, so such a pack counts as not installed and
/// the row offers the download again. A hash check per start would read
/// ~1 GB; the hashes were verified at install time.
bool isCudaPackInstalled(CudaPackInfo pack, {required String rootDir}) {
  if (File(p.join(rootDir, '.remove-${pack.id}')).existsSync()) return false;
  final dir = p.join(rootDir, pack.id);
  if (!File(p.join(dir, kCudaPackInstalledMarker)).existsSync()) return false;
  for (final file in pack.files) {
    final f = File(p.join(dir, file.name));
    if (!f.existsSync() || f.lengthSync() != file.sizeBytes) return false;
  }
  return true;
}

/// Whether the CUDA row is shown at all. Pure, so the rules are testable.
///
/// Turing (RTX 20xx, GTX 16xx) or newer only: the pack carries kernels for
/// sm_75 and up, and an older card would fail at the first kernel launch.
/// Store builds see the row too, disabled with the reason (spec §6, AR-19):
/// the download itself is blocked there, see [activeCudaPackDirProvider].
bool isCudaPackOffered({
  required bool packAvailable,
  required bool turingOrNewerNvidia,
}) => packAvailable && turingOrNewerNvidia;

/// NVIDIA's CUDA End User License Agreement. The pack ships NVIDIA
/// components under it, so the download waits for explicit consent (see
/// [isCudaEulaAcceptedFor]). The consent dialog shows the bundled full text
/// (see [kCudaEulaAssetPath]) before the download, and links to NVIDIA's
/// current version here.
const kCudaNvidiaEulaUrl = 'https://docs.nvidia.com/cuda/eula/index.html';

/// Version label of the NVIDIA CUDA EULA the pack ships. The bundled copy is
/// dated 26 Jan 2026; [kCudaNvidiaEulaUrl] opens NVIDIA's current version.
const kCudaEulaVersion = '2026-01-26';

/// SHA-256 of the licence text: `scripts/LICENSE-NVIDIA.txt`, bundled as the
/// app asset [kCudaEulaAssetPath] and shipped in every pack. A test binds the
/// bundled copy to this value.
const kCudaEulaSha256 =
    '95815d3a862cf6bb5b3b58b661c3a3172a58b9ca6fcfa36b0e3d19a8e63a18e3';

/// The licence text as an app asset, shown in the consent dialog.
const kCudaEulaAssetPath = 'assets/licenses/nvidia-cuda-eula-2026-01-26.txt';

/// The consent base for [packId]: pack id, licence label and the SHA-256
/// prefix of the licence text. Changing any of them invalidates a consent.
String _cudaEulaConsentBase(String packId) =>
    '$packId+eula-$kCudaEulaVersion+${kCudaEulaSha256.substring(0, 12)}';

/// The consent value stored once the user accepts [packId]: the consent base
/// plus the time of acceptance (UTC, ISO 8601), e.g.
/// `ggml-v1.9.5-cu12.8-r1+eula-2026-01-26+95815d3a862c@2026-10-18T09:00:00.000Z`.
String cudaEulaConsentValue(String packId, {DateTime? at}) {
  final stamp = (at ?? DateTime.now()).toUtc().toIso8601String();
  return '${_cudaEulaConsentBase(packId)}@$stamp';
}

/// Whether the stored consent [accepted] covers the pack [packId] as it is
/// now.
///
/// Consent is bound to the pack id, the licence label and the licence text
/// hash: a new pack id or a new licence text asks again. A value stored before
/// the text binding has no match and is asked once more with the current text.
/// An empty string (never accepted) never matches. Pure, so the rule is
/// testable.
bool isCudaEulaAcceptedFor({
  required String accepted,
  required String packId,
}) => accepted.startsWith('${_cudaEulaConsentBase(packId)}@');

/// Whether a CUDA pack may be downloaded or loaded in this build. Store
/// builds never do (Store policy 10.2.2, AR-19); the row shows the reason
/// instead. Checked hard in [CudaPackNotifier.install] and in
/// [activeCudaPackDirProvider], so no UI path can bypass it.
bool isCudaPackDownloadAllowed({required DeployChannel channel}) =>
    channel != DeployChannel.store;

// ---------------------------------------------------------------------------
// Install / remove
// ---------------------------------------------------------------------------

/// Thrown when a downloaded or extracted file fails verification.
class CudaPackVerificationException implements Exception {
  const CudaPackVerificationException(this.message);
  final String message;
  @override
  String toString() => 'CudaPackVerificationException: $message';
}

/// File-system side of the pack: install from a downloaded archive, remove,
/// and sweep leftovers. No Riverpod, so tests drive it with a temp folder.
class CudaPackStore {
  CudaPackStore({
    required this.rootDir,
    this._verifier = const FileVerificationService(),
    Future<void> Function(String archive, String outDir)? extract,
  }) : _extract = extract ?? _extractInIsolate;

  final String rootDir;
  final FileVerificationService _verifier;
  final Future<void> Function(String archive, String outDir) _extract;

  String packDir(CudaPackInfo pack) => p.join(rootDir, pack.id);

  /// Download target for [pack]'s archive (kept on failure so the fetcher
  /// can resume it).
  String downloadPath(CudaPackInfo pack) =>
      p.join(rootDir, '${pack.id}.download', pack.archiveFileName);

  /// Verifies the downloaded archive, extracts it to a staging folder,
  /// verifies every file, writes the marker and only then moves the folder
  /// into place — an interrupted install never looks installed.
  Future<void> installFromArchive(CudaPackInfo pack) async {
    final archive = File(downloadPath(pack));
    final archiveCheck = await _verifier.verify(archive, pack.archiveSha256);
    if (archiveCheck is! VerificationOk) {
      await _deleteQuietly(archive.parent);
      throw const CudaPackVerificationException('archive checksum mismatch');
    }

    final staging = Directory(p.join(rootDir, '${pack.id}.partial'));
    await _deleteQuietly(staging);
    await staging.create(recursive: true);
    await _extract(archive.path, staging.path);

    for (final file in pack.files) {
      final f = File(p.join(staging.path, file.name));
      // Size first: a missing or truncated file fails without hashing it.
      final ok =
          f.existsSync() &&
          f.lengthSync() == file.sizeBytes &&
          await _verifier.verify(f, file.sha256) is VerificationOk;
      if (!ok) {
        await _deleteQuietly(staging);
        throw CudaPackVerificationException('${file.name} failed verification');
      }
    }
    await File(
      p.join(staging.path, kCudaPackInstalledMarker),
    ).writeAsString(DateTime.now().toUtc().toIso8601String());

    final target = Directory(packDir(pack));
    await _deleteQuietly(target);
    await staging.rename(target.path);
    // A reinstall after "remove" (still pending until restart) supersedes it.
    await _deleteQuietly(File(p.join(rootDir, '.remove-${pack.id}')));
    await _deleteQuietly(archive.parent);
    _log.info('CUDA pack ${pack.id} installed');
  }

  /// Removes [pack]. On Windows the DLLs stay locked while the engine has
  /// them loaded, so a failed delete leaves a removal marker that
  /// [sweep] honours on the next launch; the pack counts as removed either
  /// way.
  Future<void> remove(CudaPackInfo pack) async {
    final dir = Directory(packDir(pack));
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on FileSystemException catch (e) {
      _log.info('CUDA pack in use, removing on next launch: $e');
      await Directory(rootDir).create(recursive: true);
      await File(p.join(rootDir, '.remove-${pack.id}')).writeAsString('');
    }
  }

  /// Undoes a [remove] that is still pending (the files were locked): the
  /// verified files are still there, so a reinstall needs no download.
  bool cancelPendingRemoval(CudaPackInfo pack) {
    final pending = File(p.join(rootDir, '.remove-${pack.id}'));
    final marker = File(p.join(packDir(pack), kCudaPackInstalledMarker));
    if (!pending.existsSync() || !marker.existsSync()) return false;
    try {
      pending.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Startup cleanup: pending removals, staging folders, and packs of other
  /// ids (an older ggml version the current app can no longer load). Keeps
  /// [current]'s folder and its resumable download.
  void sweep(CudaPackInfo? current) {
    final root = Directory(rootDir);
    if (!root.existsSync()) return;
    try {
      for (final entity in root.listSync()) {
        final name = p.basename(entity.path);
        if (name.startsWith('.remove-')) {
          final id = name.substring('.remove-'.length);
          final dir = Directory(p.join(rootDir, id));
          try {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
            entity.deleteSync();
          } on FileSystemException catch (e) {
            _log.warning('Pending CUDA pack removal failed: $e');
          }
          continue;
        }
        final keep =
            current != null &&
            (name == current.id || name == '${current.id}.download');
        if (keep || entity is! Directory) continue;
        try {
          entity.deleteSync(recursive: true);
          _log.info('Removed stale CUDA pack folder $name');
        } on FileSystemException catch (e) {
          _log.warning('Could not remove stale CUDA pack folder $name: $e');
        }
      }
    } on FileSystemException catch (e) {
      _log.warning('CUDA pack sweep failed: $e');
    }
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } on FileSystemException catch (e) {
      _log.warning('Could not delete ${entity.path}: $e');
    }
  }
}

/// Extraction of a ~1 GB archive is CPU-bound for seconds; keep it off the
/// UI isolate.
Future<void> _extractInIsolate(String archive, String outDir) =>
    Isolate.run(() => extractFileToDisk(archive, outDir));

// ---------------------------------------------------------------------------
// Riverpod state
// ---------------------------------------------------------------------------

enum CudaPackPhase { idle, downloading, installing, error }

/// Why the last install failed, localized by the UI.
enum CudaPackError { network, verification, storage }

@immutable
class CudaPackState {
  const CudaPackState({
    this.pack,
    this.installed = false,
    this.phase = CudaPackPhase.idle,
    this.bytesReceived = 0,
    this.error,
  });

  /// The pack for this platform; `null` where none exists.
  final CudaPackInfo? pack;
  final bool installed;
  final CudaPackPhase phase;
  final int bytesReceived;
  final CudaPackError? error;

  bool get isBusy =>
      phase == CudaPackPhase.downloading || phase == CudaPackPhase.installing;

  double get progress {
    final total = pack?.archiveSizeBytes ?? 0;
    return total > 0 ? (bytesReceived / total).clamp(0.0, 1.0) : 0;
  }

  CudaPackState copyWith({
    bool? installed,
    CudaPackPhase? phase,
    int? bytesReceived,
    CudaPackError? error,
    bool clearError = false,
  }) => CudaPackState(
    pack: pack,
    installed: installed ?? this.installed,
    phase: phase ?? this.phase,
    bytesReceived: bytesReceived ?? this.bytesReceived,
    error: clearError ? null : (error ?? this.error),
  );
}

class CudaPackNotifier extends Notifier<CudaPackState> {
  @visibleForTesting
  CudaPackInfo? packOverride;

  @visibleForTesting
  CudaPackStore? storeOverride;

  @visibleForTesting
  HttpModelFetcher? fetcherOverride;

  late final HttpModelFetcher _fetcher = fetcherOverride ?? HttpModelFetcher();

  CudaPackStore get _store =>
      storeOverride ?? CudaPackStore(rootDir: cudaPackRootDir());

  @override
  CudaPackState build() {
    final pack = packOverride ?? cudaPackForThisPlatform();
    ref.onDispose(() => _fetcher.cancel('disposed'));
    if (pack == null) return const CudaPackState();
    final store = _store;
    // Synchronous on purpose: whisperEngineProvider reads the result while
    // the app starts, and an async scan would load the model on Vulkan first
    // and then a second time on CUDA.
    store.sweep(pack);
    return CudaPackState(
      pack: pack,
      installed: isCudaPackInstalled(pack, rootDir: store.rootDir),
    );
  }

  /// Downloads, verifies and installs the pack. Refuses unless the NVIDIA
  /// EULA was accepted for this pack id (the consent dialog runs first, see
  /// [acceptEulaAndInstall]).
  Future<void> install() async {
    final pack = state.pack;
    if (pack == null) return;
    final settings = await ref.read(settingsProvider.future);
    if (!isCudaEulaAcceptedFor(
      accepted: settings.behavior.cudaEulaAccepted,
      packId: pack.id,
    )) {
      return;
    }
    await _install(pack);
  }

  /// Records the user's acceptance of the NVIDIA EULA for this pack version
  /// (per installation, never exported), then downloads and installs.
  Future<void> acceptEulaAndInstall() async {
    final pack = state.pack;
    if (pack == null) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            behavior: s.behavior.copyWith(
              cudaEulaAccepted: cudaEulaConsentValue(pack.id),
            ),
          ),
        );
    await _install(pack);
  }

  /// Records consent for an already installed pack, after the user has read
  /// the licence in the dialog. No download happens.
  Future<void> recordEulaConsent() async {
    final pack = state.pack;
    if (pack == null) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            behavior: s.behavior.copyWith(
              cudaEulaAccepted: cudaEulaConsentValue(pack.id),
            ),
          ),
        );
  }

  Future<void> _install(CudaPackInfo pack) async {
    if (state.isBusy || state.installed) return;
    if (!isCudaPackDownloadAllowed(channel: ref.read(deployChannelProvider))) {
      return;
    }
    final store = _store;
    if (store.cancelPendingRemoval(pack)) {
      state = state.copyWith(installed: true, clearError: true);
      return;
    }
    state = state.copyWith(
      phase: CudaPackPhase.downloading,
      bytesReceived: 0,
      clearError: true,
    );
    try {
      final dest = store.downloadPath(pack);
      await Directory(p.dirname(dest)).create(recursive: true);
      await _fetcher.fetch(
        url: pack.url,
        destPath: dest,
        expectedSize: pack.archiveSizeBytes,
        onProgress: (progress) =>
            state = state.copyWith(bytesReceived: progress.bytesReceived),
      );
      state = state.copyWith(phase: CudaPackPhase.installing);
      await store.installFromArchive(pack);
      state = state.copyWith(installed: true, phase: CudaPackPhase.idle);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        state = state.copyWith(phase: CudaPackPhase.idle, bytesReceived: 0);
        return;
      }
      _log.warning('CUDA pack download failed: ${describeDioError(e)}');
      state = state.copyWith(
        phase: CudaPackPhase.error,
        error: CudaPackError.network,
      );
    } on CudaPackVerificationException catch (e) {
      _log.warning('$e');
      state = state.copyWith(
        phase: CudaPackPhase.error,
        error: CudaPackError.verification,
      );
    } on FileSystemException catch (e) {
      _log.warning('CUDA pack install failed: $e');
      state = state.copyWith(
        phase: CudaPackPhase.error,
        error: CudaPackError.storage,
      );
    }
  }

  void cancel() => _fetcher.cancel('user cancelled');

  Future<void> remove() async {
    final pack = state.pack;
    if (pack == null || state.isBusy) return;
    await _store.remove(pack);
    state = state.copyWith(installed: false, phase: CudaPackPhase.idle);
  }
}

final cudaPackProvider = NotifierProvider<CudaPackNotifier, CudaPackState>(
  CudaPackNotifier.new,
);

/// Whether this build/machine gets the CUDA row in Settings at all.
final cudaPackOfferedProvider = Provider<bool>((ref) {
  final gpu = ref.watch(gpuInfoProvider).value;
  return isCudaPackOffered(
    packAvailable: ref.watch(cudaPackProvider.select((s) => s.pack != null)),
    // supportsFlashAttn is the existing Turing-or-newer name check
    // (RTX branding, GTX 16xx, Turing+ workstation cards).
    turingOrNewerNvidia:
        gpu != null && gpu.vendor == GpuVendor.nvidia && gpu.supportsFlashAttn,
  );
});

/// Pure load rule behind [activeCudaPackDirProvider]: the pack folder to load,
/// or `null`. Nothing loads without the NVIDIA EULA consent for this pack id,
/// label and text hash (Maintainer decision 3a, 2026-10-18), so the engine
/// falls back to Vulkan or CPU.
String? activeCudaPackDirFor({
  required bool offered,
  required bool downloadAllowed,
  required bool enabled,
  required CudaPackState state,
  required String accepted,
  required String rootDir,
}) {
  if (!offered || !downloadAllowed || !enabled) return null;
  final pack = state.pack;
  if (pack == null || !state.installed) return null;
  if (!isCudaEulaAcceptedFor(accepted: accepted, packId: pack.id)) return null;
  return p.join(rootDir, pack.id);
}

/// Folder of the installed CUDA pack the Whisper engine should load, or
/// `null` (not offered, not installed, no current NVIDIA consent, or switched
/// off by the user or by the GPU-load crash recovery).
final activeCudaPackDirProvider = Provider<String?>((ref) {
  final offered = ref.watch(cudaPackOfferedProvider);
  // Store builds never load a driver pack: the download is not allowed there.
  final downloadAllowed = isCudaPackDownloadAllowed(
    channel: ref.watch(deployChannelProvider),
  );
  final enabled = ref.watch(
    settingsProvider.select((s) => s.value?.behavior.cudaAcceleration ?? true),
  );
  final accepted = ref.watch(
    settingsProvider.select((s) => s.value?.behavior.cudaEulaAccepted ?? ''),
  );
  // While settings are still loading the consent reads as empty; the engine
  // provider watches this one and rebuilds once they arrive, so stay quiet.
  final settingsLoaded = ref.watch(
    settingsProvider.select((s) => s.value != null),
  );
  final state = ref.watch(cudaPackProvider);
  final dir = activeCudaPackDirFor(
    offered: offered,
    downloadAllowed: downloadAllowed,
    enabled: enabled,
    state: state,
    accepted: accepted,
    rootDir: cudaPackRootDir(),
  );
  final pack = state.pack;
  if (dir == null &&
      settingsLoaded &&
      offered &&
      downloadAllowed &&
      enabled &&
      pack != null &&
      state.installed) {
    _log.warning(
      'CUDA pack ${pack.id} not loaded: NVIDIA EULA consent is missing or out '
      'of date; using Vulkan or CPU',
    );
  }
  return dir;
});

/// Settings key of the NVIDIA EULA consent (see `AppSettings.toStorageMap`).
const kCudaEulaSettingsKey = 'cuda_eula_accepted';

/// Storage entry that records consent for [packId] in the same format the
/// dialog writes, for the headless download.
Map<String, String> cudaEulaConsentStorageMap(String packId) => {
  kCudaEulaSettingsKey: cudaEulaConsentValue(packId),
};
