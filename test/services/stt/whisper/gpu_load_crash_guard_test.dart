/// Unit tests for [GpuLoadCrashGuard] and [recoverFromGpuLoadCrash].
///
/// The bug this guards against (native segfault in whisper.dll/ggml-vulkan
/// during model load — no catchable Dart exception) cannot be reproduced in
/// a test: a real crash would kill the test runner itself. What IS testable
/// without touching native code is the crash-loop-breaker mechanism: does
/// the marker file correctly record "load attempted, never confirmed", does
/// the consecutive-crash streak correctly gate the two-strike threshold
/// ([kGpuCrashStrikeThreshold]), and does the startup recovery correctly
/// force CPU-only (and arm the user notice) only once that threshold is
/// reached — never on a single crash.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/services/stt/whisper/gpu_load_crash_guard.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    state = AsyncData(updater(state.value ?? _settings));
  }
}

/// Simulates a persistence failure (locked secure storage, disk full, DB
/// locked) in the exact call `recoverFromGpuLoadCrash` makes — used to prove
/// that failure can never propagate out and block `runApp()`.
class _ThrowingSettingsNotifier extends SettingsNotifier {
  _ThrowingSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    throw StateError('simulated settings-persistence failure');
  }
}

void main() {
  group('GpuLoadCrashGuard', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gpu_load_crash_guard_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('crashedLastAttempt is false with no marker file', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('markAttempt creates the marker so crashedLastAttempt is true', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      guard.markAttempt();
      expect(guard.crashedLastAttempt, isTrue);
    });

    test('clearAttempt removes the marker so crashedLastAttempt is false '
        'again', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      guard.markAttempt();
      guard.clearAttempt();
      expect(guard.crashedLastAttempt, isFalse);
    });

    test('clearAttempt is a no-op (does not throw) when no marker exists', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(guard.clearAttempt, returnsNormally);
    });

    test('a fresh GpuLoadCrashGuard instance sees a marker left behind by an '
        'earlier instance pointed at the same directory — this is exactly '
        'the "next process launch" scenario after a hard crash', () {
      GpuLoadCrashGuard(dataDir: tempDir.path).markAttempt();

      final nextLaunch = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(nextLaunch.crashedLastAttempt, isTrue);
    });

    test('consumePendingUserNotice is false with nothing marked', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(guard.consumePendingUserNotice(), isFalse);
    });

    test('markPendingUserNotice then consumePendingUserNotice returns true '
        'exactly once — a later call must not re-show the same toast', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path)
        ..markPendingUserNotice();

      expect(guard.consumePendingUserNotice(), isTrue);
      expect(
        guard.consumePendingUserNotice(),
        isFalse,
        reason:
            'one-shot: a second consume (e.g. on a later relaunch or '
            'rebuild) must not fire the toast again for the same event',
      );
    });

    test('consecutiveCrashes is 0 with nothing recorded', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(guard.consecutiveCrashes, 0);
    });

    test('recordCrash increments across calls and persists the count', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      expect(guard.recordCrash(), 1);
      expect(guard.recordCrash(), 2);
      expect(guard.consecutiveCrashes, 2);
    });

    test('resetCrashStreak clears the streak so a later crash starts '
        'counting from 1 again — a confirmed successful GPU load must wipe '
        'out any prior crash history, not just pause it', () {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      guard.recordCrash();
      guard.recordCrash();
      expect(guard.consecutiveCrashes, 2);

      guard.resetCrashStreak();

      expect(guard.consecutiveCrashes, 0);
      expect(guard.recordCrash(), 1);
    });
  });

  group('recoverFromGpuLoadCrash', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('gpu_load_crash_guard_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('no marker present → settings are left untouched', () async {
      final container = ProviderContainer(
        overrides: [
          gpuLoadCrashGuardProvider.overrideWithValue(
            GpuLoadCrashGuard(dataDir: tempDir.path),
          ),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                behavior: AppSettings.defaults.behavior.copyWith(
                  gpuAcceleration: 'auto',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await recoverFromGpuLoadCrash(container);

      expect(
        container.read(settingsProvider).value!.behavior.gpuAcceleration,
        'auto',
      );
      expect(
        GpuLoadCrashGuard(dataDir: tempDir.path).consumePendingUserNotice(),
        isFalse,
        reason: 'nothing happened, so the user must not see a toast',
      );
    });

    test('a single crash stays below the two-strike threshold — GPU is '
        'retried silently on this very launch, no settings change, no user '
        'notice, but the streak is recorded for next time', () async {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path)..markAttempt();
      final container = ProviderContainer(
        overrides: [
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                behavior: AppSettings.defaults.behavior.copyWith(
                  gpuAcceleration: 'auto',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await recoverFromGpuLoadCrash(container);

      expect(
        container.read(settingsProvider).value!.behavior.gpuAcceleration,
        'auto',
        reason:
            'one crash must not cost the user their GPU — it may well be '
            'an unrelated fluke (Task-Manager kill, forced reboot)',
      );
      expect(
        guard.crashedLastAttempt,
        isFalse,
        reason: 'the in-flight marker is always cleared once accounted for',
      );
      expect(guard.consumePendingUserNotice(), isFalse);
      expect(
        guard.consecutiveCrashes,
        1,
        reason: 'the streak must be recorded so a second crash escalates',
      );
    });

    test('a second consecutive crash reaches the two-strike threshold — '
        'GPU acceleration is permanently disabled and the user notice is '
        'armed', () async {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      final container = ProviderContainer(
        overrides: [
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                behavior: AppSettings.defaults.behavior.copyWith(
                  gpuAcceleration: 'auto',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      // First launch: crashes, below threshold, retried silently.
      guard.markAttempt();
      await recoverFromGpuLoadCrash(container);
      expect(
        container.read(settingsProvider).value!.behavior.gpuAcceleration,
        'auto',
      );

      // Second launch: crashes again — threshold reached.
      guard.markAttempt();
      await recoverFromGpuLoadCrash(container);

      expect(
        container.read(settingsProvider).value!.behavior.gpuAcceleration,
        'disabled',
        reason:
            'two consecutive crashes must permanently switch to CPU-only — '
            'the user must never need to reach the settings screen '
            'themselves to escape the loop',
      );
      expect(
        guard.crashedLastAttempt,
        isFalse,
        reason:
            'the marker must be cleared once recovery has run, so a '
            'clean future GPU attempt is not misdiagnosed as another crash',
      );
      expect(
        guard.consumePendingUserNotice(),
        isTrue,
        reason:
            'the UI owes the user a one-time toast explaining the automatic '
            'CPU-only switch, with a way to re-enable GPU themselves — '
            'silently flipping the setting with no explanation is not '
            'acceptable UX for this audience',
      );
    });

    test('a persistence failure while writing the CPU-only override never '
        'throws out of recoverFromGpuLoadCrash — main.dart awaits this '
        'unguarded before runApp(), so a throw here would replace the GPU '
        'crash loop with a silent, windowless dead-boot loop, and leaves the '
        'streak at/above threshold so the very next crash retries the same '
        'escalation instead of demanding a fresh two-strike run', () async {
      final guard = GpuLoadCrashGuard(dataDir: tempDir.path);
      // Seed the streak at one crash below threshold (pure file I/O, no
      // settings involved yet), then mark the in-flight attempt for the
      // crash that pushes it over the threshold.
      guard.recordCrash();
      guard.markAttempt();
      final container = ProviderContainer(
        overrides: [
          gpuLoadCrashGuardProvider.overrideWithValue(guard),
          settingsProvider.overrideWith(
            () => _ThrowingSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                behavior: AppSettings.defaults.behavior.copyWith(
                  gpuAcceleration: 'auto',
                ),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsProvider.future);

      await expectLater(recoverFromGpuLoadCrash(container), completes);

      expect(
        guard.crashedLastAttempt,
        isFalse,
        reason:
            'even on a persistence failure, the in-flight marker must be '
            'cleared — otherwise every future launch keeps retrying '
            'recovery instead of just attempting GPU again',
      );
      expect(
        guard.consumePendingUserNotice(),
        isFalse,
        reason:
            'GPU was NOT actually disabled (the persistence write failed), '
            'so telling the user "we switched you to CPU" would be false',
      );
      expect(
        guard.consecutiveCrashes,
        greaterThanOrEqualTo(kGpuCrashStrikeThreshold),
        reason:
            'the streak must NOT reset on a persistence failure, so the '
            'next crash retries this same escalation rather than '
            'requiring two fresh strikes',
      );
    });
  });
}
