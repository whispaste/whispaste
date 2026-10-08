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

import '../../core/config/settings_provider.dart';
import '../../core/data/database.dart';
import '../drift_recording_store.dart' show textReplacementRulesFrom;
import '../hardware_info_service.dart' as hw;
import '../replacements/text_replacement_matcher.dart';
import '../stt_engine_lifecycle_provider.dart';
import 'headless_transcription.dart';

/// Exit code for an invalid command line (BSD `EX_USAGE`).
const int headlessExitUsage = 64;

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

/// Runs the headless mode for [args] and returns the process exit code.
Future<int> runHeadlessCli(List<String> args) async {
  final HeadlessTranscriptionOptions options;
  try {
    options = HeadlessTranscriptionOptions.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('whispaste: ${e.message}\n\n$headlessUsage');
    return headlessExitUsage;
  }

  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(
        () => _HeadlessSettingsNotifier(options.applyTo(AppSettings.defaults)),
      ),
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
    await stdout.flush();
  }
}
