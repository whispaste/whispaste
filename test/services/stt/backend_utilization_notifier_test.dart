/// Unit tests for [BackendUtilizationNotifier].
///
/// Style mirrors `stt_server_state_notifier_test.dart`'s `_FakeSettingsNotifier`
/// pattern for [settingsProvider], plus a lightweight fake
/// [SttServerStateNotifier] subclass so [localSttBundleProvider] can be
/// pinned to a fixed [SttStatus] without spinning up the real engine seam.
/// Real polling intervals are short (milliseconds), driven with
/// `Future.delayed` rather than fakeAsync — same as
/// `mic_permission_notifier_test.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_sections.dart';
import 'package:whispaste/services/stt/backend_utilization_notifier.dart';
import 'package:whispaste/services/stt/process_cpu_probe.dart';
import 'package:whispaste/services/stt/stt_bundle.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._settings);
  final AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;
}

class _FakeSttNotifier extends SttServerStateNotifier {
  _FakeSttNotifier(this._status);
  final SttStatus _status;

  @override
  SttStatus build() => _status;

  void setStatus(SttStatus status) => state = status;
}

class _FakeCpuSampler implements CpuSampler {
  _FakeCpuSampler(this._samples);

  final List<ProcessCpuSample> _samples;
  var _index = 0;

  @override
  ProcessCpuSample sample() {
    // Repeats the final sample once exhausted, rather than throwing — a
    // notifier that outlives the fixture's scripted samples (e.g. one extra
    // poll tick) degrades to a flat reading instead of crashing the test.
    final sample = _samples[_index.clamp(0, _samples.length - 1)];
    if (_index < _samples.length - 1) _index++;
    return sample;
  }
}

void main() {
  final t0 = DateTime(2026, 1, 1);

  ProviderContainer makeContainer({
    required WhisperBackend? backend,
    required bool showBackendUtilization,
    required List<ProcessCpuSample> samples,
    // Pinned to 1 by default so the notifier's per-core→whole-machine
    // normalization is a no-op — most expected percentages below assert
    // against the raw per-core deltas, independent of the test host's real
    // core count. Override explicitly to exercise the normalization itself.
    int processorCount = 1,
  }) {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(
          () => _FakeSettingsNotifier(
            AppSettings.defaults.copyWithSections(
              interface_: InterfaceSettings.defaults.copyWith(
                showBackendUtilization: showBackendUtilization,
              ),
            ),
          ),
        ),
        localSttBundleProvider.overrideWith(
          () => _FakeSttNotifier(SttStatus(backend: backend)),
        ),
        cpuSamplerProvider.overrideWithValue(_FakeCpuSampler(samples)),
        backendUtilizationPollIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
        processorCountProvider.overrideWithValue(processorCount),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('no backend loaded yet — never polls, cpuPercent stays null', () async {
    final container = makeContainer(
      backend: null,
      showBackendUtilization: true,
      samples: [ProcessCpuSample(cpuTime: Duration.zero, wallTime: t0)],
    );
    // Force build() to run.
    container.read(backendUtilizationProvider);

    expect(
      container.read(backendUtilizationProvider.notifier).isPolling,
      isFalse,
    );
    expect(container.read(backendUtilizationProvider).cpuPercent, isNull);
  });

  test('setting disabled — never polls even with a backend loaded', () async {
    final container = makeContainer(
      backend: WhisperBackend.metal,
      showBackendUtilization: false,
      samples: [ProcessCpuSample(cpuTime: Duration.zero, wallTime: t0)],
    );
    container.read(backendUtilizationProvider);
    // settingsProvider is an AsyncNotifier — its fake resolves via a real
    // microtask, so the notifier's first build() sees `s.value == null`
    // and defaults `enabled` to true until settings settle.
    await container.read(settingsProvider.future);

    expect(
      container.read(backendUtilizationProvider.notifier).isPolling,
      isFalse,
    );
  });

  test(
    'backend loaded and setting enabled — polls and derives a percentage',
    () async {
      final container = makeContainer(
        backend: WhisperBackend.cpu,
        showBackendUtilization: true,
        samples: [
          ProcessCpuSample(cpuTime: Duration.zero, wallTime: t0),
          ProcessCpuSample(
            cpuTime: const Duration(milliseconds: 500),
            wallTime: t0.add(const Duration(seconds: 1)),
          ),
        ],
      );
      final notifier = container.read(backendUtilizationProvider.notifier);
      container.read(backendUtilizationProvider); // triggers build()
      expect(notifier.isPolling, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(
        container.read(backendUtilizationProvider).cpuPercent,
        closeTo(50, 0.01),
      );
    },
  );

  test('normalizes the raw per-core reading by processor count — 4 cores fully '
      'saturated (400% raw) reads as 100%, not 400%', () async {
    final container = makeContainer(
      backend: WhisperBackend.cpu,
      showBackendUtilization: true,
      processorCount: 4,
      samples: [
        ProcessCpuSample(cpuTime: Duration.zero, wallTime: t0),
        ProcessCpuSample(
          cpuTime: const Duration(seconds: 4),
          wallTime: t0.add(const Duration(seconds: 1)),
        ),
      ],
    );
    container.read(backendUtilizationProvider);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      container.read(backendUtilizationProvider).cpuPercent,
      closeTo(100, 0.01),
    );
  });

  test(
    'backend unloading again (e.g. idle timeout) stops polling and resets',
    () async {
      // Built inline (not via makeContainer) so the test can reach into the
      // real, running `_FakeSttNotifier` and mutate its state — mirroring how
      // the production `SttServerStateNotifier` actually transitions
      // (`state = ...`), rather than swapping provider overrides mid-test
      // (which does not itself trigger a dependent rebuild).
      final sttNotifier = _FakeSttNotifier(
        const SttStatus(backend: WhisperBackend.cpu),
      );
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(
            () => _FakeSettingsNotifier(
              AppSettings.defaults.copyWithSections(
                interface_: InterfaceSettings.defaults.copyWith(
                  showBackendUtilization: true,
                ),
              ),
            ),
          ),
          localSttBundleProvider.overrideWith(() => sttNotifier),
          cpuSamplerProvider.overrideWithValue(
            _FakeCpuSampler([
              ProcessCpuSample(cpuTime: Duration.zero, wallTime: t0),
              ProcessCpuSample(
                cpuTime: const Duration(milliseconds: 500),
                wallTime: t0.add(const Duration(seconds: 1)),
              ),
            ]),
          ),
          backendUtilizationPollIntervalProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
          processorCountProvider.overrideWithValue(1),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(backendUtilizationProvider.notifier);
      container.read(backendUtilizationProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(container.read(backendUtilizationProvider).cpuPercent, isNotNull);

      sttNotifier.setStatus(const SttStatus()); // backend: null again

      expect(notifier.isPolling, isFalse);
      expect(container.read(backendUtilizationProvider).cpuPercent, isNull);
    },
  );
}
