/// WhisPaste config reader — loads the Go-written config.json.
///
/// Reads `%APPDATA%\WhisPaste\config.json` and exposes a typed
/// [WhisPasteConfig] via a Riverpod [AsyncNotifier].
/// Field names match the Go Config struct exactly so both runtimes
/// read/write the same file without drift.
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Model ID → GGML filename lookup (mirrors internal/models/models.go)
// ---------------------------------------------------------------------------

/// Maps Go model IDs to their on-disk GGML filenames.
const Map<String, String> _modelFilenames = {
  'whisper-tiny': 'ggml-tiny-q5_1.bin',
  'whisper-base': 'ggml-base-q5_1.bin',
  'whisper-small': 'ggml-small-q5_1.bin',
  'whisper-medium': 'ggml-medium-q5_0.bin',
  'whisper-large-v3-turbo': 'ggml-large-v3-turbo-q5_0.bin',
  'whisper-large-v3': 'ggml-large-v3-q5_0.bin',
};

/// Falls back to scanning the STT directory for a matching `ggml-*.bin`
/// file if the ID is not in the known table — this covers custom models
/// that may have been added after this code was compiled.
String? resolveModelFilename(String modelId) {
  final known = _modelFilenames[modelId];
  if (known != null) return known;

  // Fallback: scan the stt directory for a file whose stem contains the ID.
  try {
    final dir = Directory(sttDir());
    if (!dir.existsSync()) return null;
    for (final entity in dir.listSync()) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.startsWith('ggml-') &&
            name.endsWith('.bin') &&
            name.contains(modelId)) {
          return name;
        }
      }
    }
  } on FileSystemException {
    // Can't scan — fall through to null.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Config data class
// ---------------------------------------------------------------------------

/// Typed subset of the Go Config struct relevant to the recording pipeline.
class WhisPasteConfig {
  const WhisPasteConfig({
    this.useLocalStt = false,
    this.localModelId = 'whisper-small',
    this.transcriptionLanguage = 'auto',
    this.gpuAcceleration = 'auto',
    this.smartMode = false,
    this.smartModePreset = '',
    this.localLlmModel = '',
    this.autoPaste = true,
    this.playSounds = true,
    this.maxRecordSec = 120,
    this.inputGain = 1.0,
  });

  /// Parse from the Go-written JSON map.
  factory WhisPasteConfig.fromJson(Map<String, dynamic> json) {
    return WhisPasteConfig(
      useLocalStt: json['use_local_stt'] as bool? ?? false,
      localModelId:
          json['local_model_id'] as String? ?? 'whisper-small',
      transcriptionLanguage:
          json['transcription_language'] as String? ?? 'auto',
      gpuAcceleration:
          json['gpu_acceleration'] as String? ?? 'auto',
      smartMode: json['smart_mode'] as bool? ?? false,
      smartModePreset:
          json['smart_mode_preset'] as String? ?? '',
      localLlmModel:
          json['local_llm_model'] as String? ?? '',
      autoPaste: json['auto_paste'] as bool? ?? true,
      playSounds: json['play_sounds'] as bool? ?? true,
      maxRecordSec: json['max_record_sec'] as int? ?? 120,
      inputGain: (json['input_gain'] as num?)?.toDouble() ?? 1.0,
    );
  }

  /// Whether to use the local whisper-server instead of a cloud API.
  final bool useLocalStt;

  /// Go model ID, e.g. `whisper-large-v3-turbo`.
  final String localModelId;

  /// Language hint for transcription (`auto` = auto-detect).
  final String transcriptionLanguage;

  /// GPU acceleration mode: `auto`, `enabled`, or `disabled`.
  final String gpuAcceleration;

  /// Whether smart-mode (LLM post-processing) is enabled.
  final bool smartMode;

  /// Smart-mode preset name (e.g. `cleanup`, `translate`).
  final String smartModePreset;

  /// Local LLM model for smart-mode.
  final String localLlmModel;

  /// Whether to auto-paste transcript to the active window.
  final bool autoPaste;

  /// Whether to play start/stop sounds.
  final bool playSounds;

  /// Maximum recording duration in seconds (safety limit).
  final int maxRecordSec;

  /// Microphone input gain multiplier.
  final double inputGain;

  /// GGML filename for the current STT model, or `null` if unknown.
  String? get sttModelFilename => resolveModelFilename(localModelId);

  /// Returns a copy with selective overrides applied.
  WhisPasteConfig copyWith({
    bool? useLocalStt,
    String? localModelId,
    String? transcriptionLanguage,
    String? gpuAcceleration,
    bool? smartMode,
    String? smartModePreset,
    String? localLlmModel,
    bool? autoPaste,
    bool? playSounds,
    int? maxRecordSec,
    double? inputGain,
  }) {
    return WhisPasteConfig(
      useLocalStt: useLocalStt ?? this.useLocalStt,
      localModelId: localModelId ?? this.localModelId,
      transcriptionLanguage:
          transcriptionLanguage ?? this.transcriptionLanguage,
      gpuAcceleration: gpuAcceleration ?? this.gpuAcceleration,
      smartMode: smartMode ?? this.smartMode,
      smartModePreset: smartModePreset ?? this.smartModePreset,
      localLlmModel: localLlmModel ?? this.localLlmModel,
      autoPaste: autoPaste ?? this.autoPaste,
      playSounds: playSounds ?? this.playSounds,
      maxRecordSec: maxRecordSec ?? this.maxRecordSec,
      inputGain: inputGain ?? this.inputGain,
    );
  }

  @override
  String toString() =>
      'WhisPasteConfig(stt=$useLocalStt, model=$localModelId, '
      'lang=$transcriptionLanguage, gpu=$gpuAcceleration)';
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

/// Returns `%APPDATA%\WhisPaste` on Windows.
///
/// Throws [StateError] if APPDATA is not set (non-Windows or broken env).
String _appDataDir() {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) {
    throw StateError('APPDATA environment variable is not set');
  }
  return p.join(appData, 'WhisPaste');
}

/// Full path to the config file.
String configFilePath() => p.join(_appDataDir(), 'config.json');

/// Directory containing STT model files and whisper-server.
String sttDir() => p.join(_appDataDir(), 'models', 'stt');

/// Full path to the whisper-server executable.
String whisperServerPath() => p.join(sttDir(), 'whisper-server.exe');

/// Full path to the GGML model file for [modelId].
///
/// Returns `null` if the model ID is not in the lookup table.
String? sttModelPath(String modelId) {
  final filename = resolveModelFilename(modelId);
  if (filename == null) return null;
  return p.join(sttDir(), filename);
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

/// Loads [WhisPasteConfig] from disk asynchronously.
///
/// Returns [WhisPasteConfig] defaults if the file does not exist or is
/// unparseable — the app must work before the Go backend creates the file.
class ConfigNotifier extends AsyncNotifier<WhisPasteConfig> {
  @override
  Future<WhisPasteConfig> build() => _load();

  /// Force-reload the config from disk.
  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<WhisPasteConfig> _load() async {
    try {
      final file = File(configFilePath());
      if (!file.existsSync()) {
        dev.log(
          'Config file not found, using defaults',
          name: 'ConfigService',
        );
        return const WhisPasteConfig();
      }
      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;
      final config = WhisPasteConfig.fromJson(json);
      dev.log('Config loaded: $config', name: 'ConfigService');
      return config;
    } on FormatException catch (e) {
      dev.log(
        'Invalid config JSON, using defaults: $e',
        name: 'ConfigService',
      );
      return const WhisPasteConfig();
    }
  }
}

/// Global config provider — loads once, can be reloaded.
final configProvider =
    AsyncNotifierProvider<ConfigNotifier, WhisPasteConfig>(
  ConfigNotifier.new,
);
