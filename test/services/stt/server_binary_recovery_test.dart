/// Unit tests for [ServerBinaryRecovery] — the self-healing orchestrator
/// that swaps in the next-most-conservative whisper-server variant when
/// the installed one crashes with a binary or model/ABI fault.
///
/// Test surface:
/// - [nextVariant] pure-function table per PRD-Modul-1.
/// - Recovery happy paths (dllMissing + abiMismatch) on NVIDIA / AMD / CPU.
/// - Exhausted-recovery path with PRD-spec German user message.
/// - Generation-counter guard: a second `recover()` for the same variant
///   in the same session must exhaust without re-invoking the downloader.
///
/// All collaborators are faked — no real disk, no real downloads.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/services/hardware_info_service.dart' as hw;
import 'package:whispaste/services/stt/server_binary_recovery.dart';
import 'package:whispaste/services/whisper_server_downloader.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Captures `download()` invocations and lets the test script the outcome.
class _FakeWhisperServerDownloader implements WhisperServerDownloader {
  _FakeWhisperServerDownloader({this.throwOnDownload});

  /// Set to non-null to make the next [download] throw — used to drive
  /// the "download-failed → exhausted" branch.
  Object? throwOnDownload;

  final List<({String destDir, String gpuMode})> calls =
      <({String destDir, String gpuMode})>[];

  @override
  Future<void> download({
    required String destDir,
    required String gpuMode,
    ServerFetchProgressCallback? onProgress,
    ServerExtractingCallback? onExtracting,
  }) async {
    calls.add((destDir: destDir, gpuMode: gpuMode));
    if (throwOnDownload != null) throw throwOnDownload!;
  }

  // The members below are not exercised by the recovery orchestrator — we
  // implement them as no-ops/asserts so `implements` stays satisfied
  // without dragging real Dio / fetcher dependencies into the test.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'Unexpected call to ${invocation.memberName} on fake downloader',
    );
  }
}

/// In-memory implementation of [BinaryStore] — records writes and lets
/// the test pre-seed the current backend, "compatible-after-recovery"
/// outcome, and inspect what was persisted.
class _FakeBinaryStore implements BinaryStore {
  _FakeBinaryStore({
    this.currentBackend,
    this.compatibleAfterRecovery = true,
    this.vcRuntimeInstalled = true,
    this.dirFiles = const <String>[],
  });

  String? currentBackend;
  bool compatibleAfterRecovery;

  /// Drives [listBinaryDirFiles] — the file inventory the orchestrator uses
  /// to corroborate (or veto) a `vcRuntimeMissing` claim when the
  /// `existsSync`-based [vcRuntimePresent] probe disagrees with what is
  /// actually on disk (the MSIX false-negative behind FLUTTER_WHISPASTE-A0).
  List<String> dirFiles;

  /// Drives [vcRuntimePresent]. Defaults to `true` — the common real case
  /// (a modern Windows box with the VC++ Redistributable installed), which
  /// is exactly the state that must NOT be misclassified as vcRuntimeMissing.
  bool vcRuntimeInstalled;

  int deleteCalls = 0;
  int compatibilityCalls = 0;
  final List<({String path, String backend})> serverInfoWrites =
      <({String path, String backend})>[];

  @override
  String? readBackend(String sttDirPath) => currentBackend;

  @override
  Future<void> deleteBinary(String sttDirPath) async {
    deleteCalls += 1;
  }

  @override
  bool isCompatible(String sttDirPath, hw.GpuInfo gpu) {
    compatibilityCalls += 1;
    return compatibleAfterRecovery;
  }

  @override
  bool vcRuntimePresent(String sttDirPath) => vcRuntimeInstalled;

  @override
  List<String> listBinaryDirFiles(String sttDirPath) => dirFiles;

  @override
  Future<void> writeServerInfo(
    String sttDirPath,
    hw.GpuInfo gpu, {
    required String installedBackend,
  }) async {
    serverInfoWrites.add((path: sttDirPath, backend: installedBackend));
  }
}

// ---------------------------------------------------------------------------
// GPU fixtures
// ---------------------------------------------------------------------------

const _nvidia = hw.GpuInfo(
  vendor: hw.GpuVendor.nvidia,
  name: 'NVIDIA GeForce RTX 3060',
  cudaAvailable: true,
  vulkanAvailable: true,
);

const _amd = hw.GpuInfo(
  vendor: hw.GpuVendor.amd,
  name: 'AMD Radeon RX 6700 XT',
  vulkanAvailable: true,
);

const _intel = hw.GpuInfo(
  vendor: hw.GpuVendor.intel,
  name: 'Intel Iris Xe',
  vulkanAvailable: true,
);

const _apple = hw.GpuInfo(vendor: hw.GpuVendor.apple, name: 'Apple M2');

const _cpuOnly = hw.GpuInfo(
  vendor: hw.GpuVendor.none,
  name: 'Detection failed — using CPU',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('nextVariant (pure function)', () {
    test('cuda12 / cublas-12 → vulkan on NVIDIA', () {
      expect(nextVariant('cuda12', _nvidia), 'vulkan');
      expect(nextVariant('cublas-12', _nvidia), 'vulkan');
      // case-insensitive parsing
      expect(nextVariant('CUDA12', _nvidia), 'vulkan');
    });

    test('vulkan → cpu', () {
      expect(nextVariant('vulkan', _amd), 'cpu');
      expect(nextVariant('vulkan', _intel), 'cpu');
      expect(nextVariant('vulkan', _nvidia), 'cpu');
    });

    test('metal → cpu', () {
      expect(nextVariant('metal', _apple), 'cpu');
    });

    test('cpu / blas-bin → null (exhausted)', () {
      expect(nextVariant('cpu', _amd), isNull);
      expect(nextVariant('blas-bin', _amd), isNull);
      expect(nextVariant('cpu', _cpuOnly), isNull);
    });

    test('unknown current variant → GPU optimal backend', () {
      // Empty / null current means `.server-info.json` is missing — the
      // PRD says to attempt a fresh download per the GPU detector.
      expect(nextVariant(null, _nvidia), 'cuda12');
      expect(nextVariant('', _amd), 'vulkan');
      expect(nextVariant('   ', _apple), 'metal');
      expect(nextVariant(null, _cpuOnly), 'cpu');
    });
  });

  group('ServerBinaryRecovery.recover', () {
    test('dllMissing + NVIDIA + cublas-12 → RecoveryRetried(vulkan), '
        'download invoked, validated, .server-info.json written', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(currentBackend: 'cublas-12');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryRetried>());
      expect((result as RecoveryRetried).chosenVariant, 'vulkan');

      expect(downloader.calls, hasLength(1));
      expect(downloader.calls.single.destDir, '/fake/stt');
      // Non-CPU variant → keeps gpuMode 'auto' so the downloader's own
      // pattern picker selects the Vulkan asset.
      expect(downloader.calls.single.gpuMode, 'auto');

      expect(
        store.compatibilityCalls,
        1,
        reason: 'recovery must validate the new binary',
      );
      expect(store.serverInfoWrites, hasLength(1));
      expect(
        store.serverInfoWrites.single.backend,
        'vulkan',
        reason: 'PRD: .server-info.json carries backend=vulkan after recovery',
      );
    });

    test('dllMissing + AMD + vulkan → RecoveryFellBackToCpu, '
        'download invoked with CPU/BLAS via gpuMode="disabled"', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(currentBackend: 'vulkan');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _amd,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryFellBackToCpu>());
      expect(downloader.calls, hasLength(1));
      // CPU/blas-bin path → gpuMode forced to 'disabled' so the
      // downloader's asset patterns collapse to the CPU/BLAS asset
      // regardless of the still-detected AMD GPU.
      expect(downloader.calls.single.gpuMode, 'disabled');

      expect(store.serverInfoWrites, hasLength(1));
      // Note: writeServerInfo persists `gpu.optimalBackend` because the
      // current GPU is still AMD/Vulkan — the binary itself is CPU,
      // but the metadata reflects the GPU. For CPU-fallback callers
      // typically also flip the runtime gpuMode to 'disabled' so the
      // server is launched in CPU mode; see SttServerStateNotifier.
    });

    test(
      'dllMissing + already on CPU floor + VC++ runtime ABSENT → '
      'RecoveryExhausted flagged vcRuntimeMissing with VC++ message',
      () async {
        final downloader = _FakeWhisperServerDownloader();
        // VC++ runtime genuinely missing on this box.
        final store = _FakeBinaryStore(
          currentBackend: 'cpu',
          vcRuntimeInstalled: false,
        );
        final recovery = ServerBinaryRecovery(
          downloader: downloader,
          store: store,
        );

        // The installed CPU build itself aborts with STATUS_DLL_NOT_FOUND and
        // the probe confirms the Microsoft Visual C++ runtime is absent (e.g.
        // VCOMP140.DLL). No further variant exists, so recovery must exhaust —
        // with the actionable VC++ kind rather than the generic message.
        final result = await recovery.recover(
          reason: RecoveryReason.dllMissing,
          gpu: _cpuOnly,
          sttDirPath: '/fake/stt',
          activeModelId: 'whisper-small',
        );

        expect(result, isA<RecoveryExhausted>());
        final exhausted = result as RecoveryExhausted;
        expect(exhausted.kind, RecoveryExhaustedKind.vcRuntimeMissing);
        expect(exhausted.userMessage, contains('Sprachdienst kann nicht'));
        expect(exhausted.userMessage, contains('Visual C++'));
        // Vocabulary check — never the anti-vocabulary terms.
        expect(exhausted.userMessage, isNot(contains('Modell-Datei')));
        expect(exhausted.userMessage, isNot(contains('STT')));
        expect(exhausted.userMessage, isNot(contains('binary')));

        expect(
          downloader.calls,
          isEmpty,
          reason: 'exhausted path must not invoke download',
        );
      },
    );

    test('dllMissing + already on CPU floor but VC++ runtime PRESENT → '
        'generic exhaustion, NOT vcRuntimeMissing (FLUTTER_WHISPASTE-A0 '
        'false-positive regression)', () async {
      final downloader = _FakeWhisperServerDownloader();
      // The field case: VC++ runtime fully installed (System32 has VCRUNTIME140
      // et al.), yet the CPU build still died with STATUS_DLL_NOT_FOUND — the
      // real fault is some other DLL, NOT the redistributable. The old
      // name-only heuristic wrongly told the user to reinstall VC++.
      final store = _FakeBinaryStore(
        currentBackend: 'cpu',
        vcRuntimeInstalled: true,
      );
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _cpuOnly,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryExhausted>());
      final exhausted = result as RecoveryExhausted;
      expect(exhausted.kind, RecoveryExhaustedKind.generic);
      // Must NOT send the user on a VC++ reinstall goose chase.
      expect(exhausted.userMessage, isNot(contains('Visual C++')));
      // Every exhaustion routes the user to the diagnostics export so they
      // know what to send us.
      expect(exhausted.userMessage, contains('Debug-Informationen'));

      expect(
        downloader.calls,
        isEmpty,
        reason: 'exhausted path must not invoke download',
      );
    });

    test('dllMissing + CPU floor + existsSync probe says ABSENT but the VC++ '
        'DLLs ARE in the dir listing → generic, NOT vcRuntimeMissing '
        '(MSIX existsSync false-negative corroboration)', () async {
      // The exact FLUTTER_WHISPASTE-A0 field shape: the diagnostic dump shows
      // VCRUNTIME140/MSVCP140/VCOMP140 present in the stt dir, yet the live
      // `existsSync`-based probe returned false under MSIX and the user was
      // told to reinstall a redistributable they already had. When the file
      // inventory contradicts the probe, trust the inventory and stay generic.
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(
        currentBackend: 'cpu',
        vcRuntimeInstalled: false, // existsSync probe (flaky) says absent
        dirFiles: const [
          'whisper-server.exe',
          'vcruntime140.dll',
          'vcruntime140_1.dll',
          'msvcp140.dll',
          'vcomp140.dll',
          'ggml-cpu.dll',
        ],
      );
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _cpuOnly,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      final exhausted = result as RecoveryExhausted;
      expect(exhausted.kind, RecoveryExhaustedKind.generic);
      expect(exhausted.userMessage, isNot(contains('Visual C++')));
    });

    test('dllMissing while fetching CPU floor (current=GPU variant) → '
        'generic exhaustion, NOT vcRuntimeMissing', () async {
      // A network failure while downloading the CPU floor is not a VC++
      // problem: the crashed binary was the GPU build, so the user
      // message must stay generic (restart / re-download).
      final downloader = _FakeWhisperServerDownloader(
        throwOnDownload: Exception('network down'),
      );
      final store = _FakeBinaryStore(currentBackend: 'vulkan');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryExhausted>());
      final exhausted = result as RecoveryExhausted;
      expect(exhausted.kind, RecoveryExhaustedKind.generic);
      expect(exhausted.userMessage, isNot(contains('Visual C++')));
    });

    test('abiMismatch + cublas-12 → identical to dllMissing '
        '(re-download with next variant)', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(currentBackend: 'cublas-12');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.abiMismatch,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryRetried>());
      expect((result as RecoveryRetried).chosenVariant, 'vulkan');
      expect(downloader.calls, hasLength(1));
      expect(store.serverInfoWrites.single.backend, 'vulkan');
    });

    test('generation-counter guard: repeat recover() walks past the already '
        'tried variant down to the CPU floor, then exhausts', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(currentBackend: 'cublas-12');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      // First attempt: cublas-12 → vulkan, download fires.
      final first = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );
      expect(first, isA<RecoveryRetried>());
      expect(downloader.calls, hasLength(1));

      // Second attempt within the same session — current variant is
      // still cublas-12 (the recovery did not flip it because the test
      // store does not auto-mutate). "vulkan" was already tried, so the
      // orchestrator must walk the chain past it to the CPU floor instead
      // of exhausting (FLUTTER_WHISPASTE-A0: exhausting here left users
      // without the CPU fallback that would have worked).
      final second = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(second, isA<RecoveryFellBackToCpu>());
      expect(downloader.calls, hasLength(2));
      expect(
        downloader.calls.last.gpuMode,
        'disabled',
        reason: 'CPU floor download forces the CPU/BLAS asset',
      );

      // Third attempt: every fallback variant has now been tried — only
      // here may the guard exhaust, and it must do so without another
      // download (this is the actual infinite-loop protection).
      final third = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(third, isA<RecoveryExhausted>());
      expect(
        downloader.calls,
        hasLength(2),
        reason: 'guard must short-circuit before re-invoking download',
      );
    });

    test('FLUTTER_WHISPASTE-A0 field shape: cuda re-installed behind '
        'recovery\'s back, vulkan already tried → falls back to CPU '
        'instead of exhausting', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(currentBackend: 'cuda');
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      // Round 1: cuda fails → recovery installs vulkan.
      final first = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-medium',
      );
      expect(first, isA<RecoveryRetried>());
      expect((first as RecoveryRetried).chosenVariant, 'vulkan');

      // Meanwhile the proactive startup check re-installed the optimal
      // cuda build (the pre-fix `isServerBinaryCompatible` behaviour).
      store.currentBackend = 'cuda';

      // Round 2: cuda fails again. Old behaviour: nextVariant(cuda)=vulkan,
      // already tried → RecoveryExhausted("variant-already-tried-this-
      // session") — the exact Sentry event. New behaviour: walk on to cpu.
      final second = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-medium',
      );

      expect(second, isA<RecoveryFellBackToCpu>());
      expect(recovery.triedVariantsForTesting, containsAll(['vulkan', 'cpu']));
    });

    test(
      'download failure → RecoveryExhausted (variant counted as tried)',
      () async {
        final downloader = _FakeWhisperServerDownloader(
          throwOnDownload: Exception('network down'),
        );
        final store = _FakeBinaryStore(currentBackend: 'cublas-12');
        final recovery = ServerBinaryRecovery(
          downloader: downloader,
          store: store,
        );

        final result = await recovery.recover(
          reason: RecoveryReason.dllMissing,
          gpu: _nvidia,
          sttDirPath: '/fake/stt',
          activeModelId: 'whisper-small',
        );

        expect(result, isA<RecoveryExhausted>());
        expect(downloader.calls, hasLength(1));
        // The variant must be marked as tried so an immediate retry
        // doesn't loop forever on a flaky network.
        expect(recovery.triedVariantsForTesting, contains('vulkan'));
      },
    );

    test('post-download validation failure → RecoveryExhausted', () async {
      final downloader = _FakeWhisperServerDownloader();
      final store = _FakeBinaryStore(
        currentBackend: 'cublas-12',
        compatibleAfterRecovery: false,
      );
      final recovery = ServerBinaryRecovery(
        downloader: downloader,
        store: store,
      );

      final result = await recovery.recover(
        reason: RecoveryReason.dllMissing,
        gpu: _nvidia,
        sttDirPath: '/fake/stt',
        activeModelId: 'whisper-small',
      );

      expect(result, isA<RecoveryExhausted>());
      expect(downloader.calls, hasLength(1));
      expect(
        store.serverInfoWrites,
        isEmpty,
        reason: 'do not persist metadata when validation fails',
      );
    });
  });
}
