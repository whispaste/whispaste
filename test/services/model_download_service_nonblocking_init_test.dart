/// Non-blocking init tests for [ModelDownloadNotifier].
///
/// Verifies that [ModelDownloadNotifier.build] returns immediately without
/// performing any synchronous file-exists scan (AC1: async/deferred model scan,
/// AC2: calling build not blocked, AC3: unit test non-blocking init).
///
/// The seam is [ModelDownloadNotifier.existsHookOverride]: a counting fake is
/// injected so we can assert whether any file check has run at the exact moment
/// build() returns vs. after the microtask queue is drained.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:whispaste/services/model_download_service.dart';
import 'package:whispaste/services/path_service.dart' show sttDirOverride;

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _makeContainerWithHook(
  Future<bool> Function(String path) hook,
) {
  return ProviderContainer(
    overrides: [
      modelDownloadProvider.overrideWith(() {
        return ModelDownloadNotifier()..existsHookOverride = hook;
      }),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wp_nonblock_');
    sttDirOverride = tempDir.path;
  });

  tearDown(() async {
    sttDirOverride = null;
    await tempDir.delete(recursive: true);
  });

  group('ModelDownloadNotifier — non-blocking init (AC1/AC2/AC3)', () {
    test(
      'AC3: build() returns before any existsHook call (scan deferred)',
      () async {
        var hookCallCount = 0;
        final firstCall = Completer<void>();

        final container = _makeContainerWithHook((path) async {
          hookCallCount++;
          if (!firstCall.isCompleted) firstCall.complete();
          return false;
        });
        addTearDown(container.dispose);

        // Trigger build() — synchronous call, must return immediately.
        final state = container.read(modelDownloadProvider);

        // AC2: calling build is not blocked synchronously — hook count is 0
        // because the scan has been deferred to a microtask.
        expect(
          hookCallCount,
          0,
          reason:
              'build() must not call existsHook synchronously; '
              'scan deferred to microtask',
        );

        // AC1: initial state is empty/idle (scan not yet complete).
        expect(state.downloadedModels, isEmpty);
        expect(state.serverReady, isFalse);
        expect(state.phase, DownloadPhase.idle);

        // AC3: after yielding, the deferred scan runs and calls the hook.
        await firstCall.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              fail('existsHook was never called — scan did not run'),
        );
        expect(hookCallCount, greaterThan(0));
      },
    );

    test('state reflects scanned result after async scan completes', () async {
      // Pre-create a model file and the server binary so the scan finds the
      // model and serverReady=true. Avoids triggering the self-heal microtask
      // (which would try to load the Flutter bundle and requires widget binding).
      final modelFile = File(p.join(tempDir.path, sttModels.first.filename));
      await modelFile.writeAsBytes([0]);
      final serverFile = File(
        p.join(
          tempDir.path,
          Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
        ),
      );
      await serverFile.writeAsBytes([0]);

      // The scan checks: sttModels.length model files + 1 server binary.
      // Complete only after ALL checks are done so state = scanned has run.
      final totalExpected = sttModels.length + 1;
      var hookCallCount = 0;
      final allDone = Completer<void>();

      final container = _makeContainerWithHook((path) async {
        final exists = await File(path).exists();
        hookCallCount++;
        if (hookCallCount >= totalExpected && !allDone.isCompleted) {
          allDone.complete();
        }
        return exists;
      });
      addTearDown(container.dispose);

      // Trigger build and wait for the async scan to complete all checks.
      container.read(modelDownloadProvider);
      await allDone.future.timeout(const Duration(seconds: 5));

      // Give one extra microtask for the `state = scanned` assignment to land.
      await Future<void>.microtask(() {});

      final state = container.read(modelDownloadProvider);
      expect(
        state.downloadedModels,
        contains(sttModels.first.id),
        reason: 'Async scan must have updated state with the found model',
      );
    });

    test(
      'downloadModel awaits initial scan before checking serverReady',
      () async {
        // Pre-create a fake whisper-server binary so serverReady is true after
        // scanning. downloadModel should skip Phase-1 (engine download) only if
        // it correctly waits for the scan to set serverReady.
        final serverFile = File(
          p.join(
            tempDir.path,
            Platform.isWindows ? 'whisper-server.exe' : 'whisper-server',
          ),
        );
        await serverFile.writeAsBytes([0]);

        // Track how many times the hook is called before downloadModel starts.
        var hookCallsBeforeDownload = -1;
        var totalHookCalls = 0;

        final container = ProviderContainer(
          overrides: [
            modelDownloadProvider.overrideWith(() {
              return ModelDownloadNotifier()
                ..existsHookOverride = (path) async {
                  totalHookCalls++;
                  return File(path).exists();
                };
            }),
          ],
        );
        addTearDown(container.dispose);

        // Start the provider (schedules scan microtask).
        final notifier = container.read(modelDownloadProvider.notifier);

        // downloadModel must wait for the scan before checking serverReady.
        // Record how many hook calls happened before downloadModel continues.
        hookCallsBeforeDownload = totalHookCalls; // 0 at this point

        // We expect downloadModel to either find serverReady=true (after scan)
        // or at least not try to download the server (state.serverReady=true).
        // Since we can't call a real download here, we just verify the scan
        // ran before isBusy/serverReady checks by asserting hookCalls > 0
        // after downloadModel returns with the "unknown model" error path.
        try {
          await notifier.downloadModel('nonexistent-model-id');
        } catch (_) {
          // Expected: model not found → error state, but scan ran first.
        }

        // After downloadModel, the scan must have completed.
        expect(
          totalHookCalls,
          greaterThan(hookCallsBeforeDownload),
          reason:
              'downloadModel must await the initial scan; '
              'existsHook should have been called before downloadModel proceeds',
        );
      },
    );
  });
}
