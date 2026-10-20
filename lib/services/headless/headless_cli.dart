/// Process-level wiring for `whispaste --transcribe-file` (see
/// [runHeadlessTranscription]): reads the WAV, builds a provider container
/// with fixed settings, runs, prints the result and frees the engine.
///
/// Started from `main()` before any UI, single-instance guard or crash
/// reporting, so a benchmark never touches a running instance or the user's
/// persisted settings.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../drift_recording_store.dart' show textReplacementRulesFrom;
import '../hardware_info_service.dart' as hw;
import '../stt/whisper/cuda_pack.dart'
    show
        CudaPackError,
        activeCudaPackDirProvider,
        cudaPackForThisPlatform,
        cudaEulaConsentValue,
        cudaPackProvider,
        kCudaNvidiaEulaUrl;
import '../replacements/text_replacement_matcher.dart';
import '../stt_engine_lifecycle_provider.dart';
import 'headless_transcription.dart';

/// Exit code for an invalid command line (BSD `EX_USAGE`).
const int headlessExitUsage = 64;

/// `whispaste --download-cuda-pack --accept-nvidia-eula`.
const String kDownloadCudaPackFlag = '--download-cuda-pack';
const String kAcceptNvidiaEulaFlag = '--accept-nvidia-eula';

/// Usage text for `--download-cuda-pack`, also printed on refusal.
const String cudaPackDownloadUsage = '''
Usage: whispaste --download-cuda-pack --accept-nvidia-eula

Downloads and installs the optional NVIDIA CUDA pack (Windows/Linux x64)
without opening the app window, then exits.
  --accept-nvidia-eula       required. The pack contains NVIDIA components
                             under the NVIDIA CUDA End User License Agreement,
                             https://docs.nvidia.com/cuda/eula/index.html
                             The flag records your acceptance for this run only;
                             nothing is stored in the app settings.
''';

/// Whether [args] ask for the CUDA pack download.
bool isCudaPackDownloadRequested(List<String> args) =>
    args.contains(kDownloadCudaPackFlag);

/// Why the CUDA pack download must not start for [args], or `null` when it
/// may. Without `--accept-nvidia-eula` nothing is downloaded.
String? cudaPackDownloadRefusal(List<String> args) {
  if (args.contains(kAcceptNvidiaEulaFlag)) return null;
  return 'whispaste: refused to download the CUDA pack: it contains NVIDIA '
      'components under the NVIDIA CUDA EULA ($kCudaNvidiaEulaUrl). Read it, '
      'then re-run with $kAcceptNvidiaEulaFlag to accept it.';
}

/// Settings held in memory only: the engine's post-load bookkeeping (e.g.
/// the tier benchmark) must not overwrite the user's persisted settings.
class _HeadlessSettingsNotifier extends SettingsNotifier {
  _HeadlessSettingsNotifier(this._settings);

  AppSettings _settings;

  @override
  Future<AppSettings> build() async => _settings;

  @override
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    _settings = updater(_settings);
    state = AsyncData(_settings);
  }
}

/// Downloads the CUDA pack for [args] and returns the process exit code.
/// Refuses without `--accept-nvidia-eula`: the download never starts, and the
/// reason is printed to stderr.
Future<int> runCudaPackDownloadCli(List<String> args) async {
  if (cudaPackDownloadRefusal(args) case final reason?) {
    stderr.writeln('$reason\n\n$cudaPackDownloadUsage');
    return headlessExitUsage;
  }
  final pack = cudaPackForThisPlatform();
  if (pack == null) {
    stderr.writeln('whispaste: no CUDA pack exists for this platform');
    return 1;
  }
  WidgetsFlutterBinding.ensureInitialized();
  // Consent for this run only: an in-memory acceptance, never written to the
  // user's persisted settings (the same rule as the rest of headless mode).
  final base = AppSettings.defaults;
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _HeadlessSettingsNotifier(
          base.copyWithSections(
            behavior: base.behavior.copyWith(
              cudaEulaAccepted: cudaEulaConsentValue(pack.id),
            ),
          ),
        ),
      ),
    ],
  );
  try {
    stderr.writeln('whispaste: downloading CUDA pack ${pack.id} …');
    final notifier = container.read(cudaPackProvider.notifier);
    await notifier.install();
    final state = container.read(cudaPackProvider);
    if (state.installed) {
      stdout.writeln('CUDA pack ${pack.id} installed');
      return 0;
    }
    final reason = switch (state.error) {
      CudaPackError.network => 'network error',
      CudaPackError.verification => 'verification failed',
      CudaPackError.storage => 'could not save the pack',
      null => 'unknown error',
    };
    stderr.writeln('whispaste: CUDA pack download failed: $reason');
    return 1;
  } finally {
    container.dispose();
    await stdout.flush();
  }
}

/// Runs the headless mode for [args] and returns the process exit code.
Future<int> runHeadlessCli(List<String> args) async {
  final HeadlessTranscriptionOptions options;
  try {
    options = HeadlessTranscriptionOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('whispaste: ${e.message}\n\n$headlessUsage');
    return headlessExitUsage;
  }

  // Without a listener, package:logging drops every record, so engine
  // warnings (e.g. a GPU load that fell back to CPU) would be invisible in
  // a benchmark run. Warnings go to stderr only: stdout carries the result
  // and must stay parseable. configureLogging() is deliberately not used:
  // it writes the app's log file and prints its path to stdout.
  final logSub = Logger.root.onRecord
      .where((r) => r.level >= Level.WARNING)
      .listen(
        (r) => stderr.writeln(
          'whispaste: [${r.level.name}] ${r.loggerName}: ${r.message}',
        ),
      );
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _HeadlessSettingsNotifier(options.applyTo(AppSettings.defaults)),
      ),
      if (options.cudaPackDir case final dir?)
        activeCudaPackDirProvider.overrideWithValue(dir),
    ],
  );
  try {
    final wav = canonicalPcm16MonoWav(
      await File(options.wavPath).readAsBytes(),
    );
    // Same as app start: the whisper engine reads the detected GPU backend
    // synchronously, so detection has to settle first.
    await container.read(hw.gpuInfoProvider.future);
    var rules = const <TextReplacementRule>[];
    if (options.applyReplacements) {
      rules = textReplacementRulesFrom(
        await container.read(historyDatabaseProvider).readAllReplacements(),
      );
    }

    final report = await runHeadlessTranscription(
      container,
      options,
      wav,
      replacementRules: rules,
    );
    final json = const JsonEncoder.withIndent('  ').convert(report.toJson());
    if (options.outPath case final path?) {
      await File(path).writeAsString('$json\n');
    }
    stdout.writeln(options.json ? json : report.transcript);
    return 0;
  } on Object catch (e) {
    // FileSystemException, FormatException (WAV) and engine failures alike:
    // a one-line reason, no stack trace — this is a CLI.
    stderr.writeln('whispaste: transcription failed: $e');
    return 1;
  } finally {
    // Free the native model before the process exits (FLUTTER_WHISPASTE-BC:
    // a native teardown racing process exit crashes).
    try {
      await container
          .read(onDeviceEngineLifecycleProvider)
          .stop()
          .timeout(const Duration(seconds: 10));
    } on Object catch (e) {
      stderr.writeln('whispaste: engine stop failed: $e');
    }
    container.dispose();
    await logSub.cancel();
    await stdout.flush();
  }
}
