import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/history/data/database.dart';
import '../../services/config_service.dart';

/// All persisted app settings in one immutable data class.
class AppSettings {
  const AppSettings({
    // Interface
    this.themeMode = ThemeMode.dark,
    this.locale = 'en',
    this.launchAtStartup = false,
    this.showNotifications = true,
    // Audio
    this.microphone = 'Default',
    this.inputGain = 100.0,
    this.pushToTalk = false,
    // Recording Safety
    this.deadMicTimeout = 3.0,
    this.autoStopSilence = 0.0,
    // Speech Recognition
    this.sttProvider = 'On Device (Private)',
    this.sttModel = 'whisper-medium',
    this.sttLanguage = 'Auto-detect',
    // Post-Processing
    this.postProcessEnabled = true,
    this.postProcessPreset = 'Clean up',
    this.postProcessProvider = 'Local',
    // Sound & Feedback
    this.recordStartSound = true,
    this.recordStopSound = true,
    this.transcriptionCompleteSound = true,
    // Overlay & Floating Button
    this.showOverlay = true,
    this.showFloatingButton = true,
    this.floatingButtonOpacity = 0.9,
    this.floatingButtonSize = 'Normal',
    // Cloud Providers (API keys)
    this.openAiApiKey = '',
    this.groqApiKey = '',
    this.deepgramApiKey = '',
    this.anthropicApiKey = '',
  });

  // Interface
  final ThemeMode themeMode;
  final String locale;
  final bool launchAtStartup;
  final bool showNotifications;

  // Audio
  final String microphone;
  final double inputGain;
  final bool pushToTalk;

  // Recording Safety
  final double deadMicTimeout;
  final double autoStopSilence;

  // Speech Recognition
  final String sttProvider;
  final String sttModel;
  final String sttLanguage;

  // Post-Processing
  final bool postProcessEnabled;
  final String postProcessPreset;
  final String postProcessProvider;

  // Sound & Feedback
  final bool recordStartSound;
  final bool recordStopSound;
  final bool transcriptionCompleteSound;

  // Overlay & Floating Button
  final bool showOverlay;
  final bool showFloatingButton;
  final double floatingButtonOpacity;
  final String floatingButtonSize;

  // Cloud Providers (API keys)
  final String openAiApiKey;
  final String groqApiKey;
  final String deepgramApiKey;
  final String anthropicApiKey;

  /// Factory-reset defaults.
  static const AppSettings defaults = AppSettings();

  /// Creates settings from persisted key-value storage.
  factory AppSettings.fromStorageMap(Map<String, String> values) {
    return AppSettings(
      themeMode: _themeModeFromString(values['theme_mode'] ?? 'dark'),
      locale: values['locale'] ?? 'en',
      launchAtStartup:
          _readBool(values, 'launch_at_startup', defaults.launchAtStartup),
      showNotifications:
          _readBool(values, 'show_notifications', defaults.showNotifications),
      microphone: values['microphone'] ?? defaults.microphone,
      inputGain: _readDouble(values, 'input_gain', defaults.inputGain),
      pushToTalk: _readBool(values, 'push_to_talk', defaults.pushToTalk),
      deadMicTimeout:
          _readDouble(values, 'dead_mic_timeout', defaults.deadMicTimeout),
      autoStopSilence:
          _readDouble(values, 'auto_stop_silence', defaults.autoStopSilence),
      sttProvider: values['stt_provider'] ?? defaults.sttProvider,
      sttModel: _migrateModelId(values['stt_model'] ?? defaults.sttModel),
      sttLanguage: values['stt_language'] ?? defaults.sttLanguage,
      postProcessEnabled: _readBool(
        values,
        'post_process_enabled',
        defaults.postProcessEnabled,
      ),
      postProcessPreset:
          values['post_process_preset'] ?? defaults.postProcessPreset,
      postProcessProvider:
          values['post_process_provider'] ?? defaults.postProcessProvider,
      recordStartSound:
          _readBool(values, 'record_start_sound', defaults.recordStartSound),
      recordStopSound:
          _readBool(values, 'record_stop_sound', defaults.recordStopSound),
      transcriptionCompleteSound: _readBool(
        values,
        'transcription_complete_sound',
        defaults.transcriptionCompleteSound,
      ),
      showOverlay: _readBool(values, 'show_overlay', defaults.showOverlay),
      showFloatingButton: _readBool(
        values,
        'show_floating_button',
        defaults.showFloatingButton,
      ),
      floatingButtonOpacity: _readDouble(
        values,
        'floating_button_opacity',
        defaults.floatingButtonOpacity,
      ),
      floatingButtonSize:
          values['floating_button_size'] ?? defaults.floatingButtonSize,
      openAiApiKey: values['openai_api_key'] ?? defaults.openAiApiKey,
      groqApiKey: values['groq_api_key'] ?? defaults.groqApiKey,
      deepgramApiKey: values['deepgram_api_key'] ?? defaults.deepgramApiKey,
      anthropicApiKey:
          values['anthropic_api_key'] ?? defaults.anthropicApiKey,
    );
  }

  /// Seeds settings from the existing Go config when no Flutter row exists yet.
  factory AppSettings.fromGoConfig(WhisPasteConfig config) {
    return AppSettings(
      inputGain: config.inputGain * 100.0,
      sttProvider: config.useLocalStt ? 'On Device (Private)' : defaults.sttProvider,
      sttModel: _settingModelFromConfig(config.localModelId),
      sttLanguage: _settingLanguageFromConfig(config.transcriptionLanguage),
      postProcessEnabled: config.smartMode,
      postProcessPreset: _settingPresetFromConfig(config.smartModePreset),
      postProcessProvider: 'Local',
      recordStartSound: config.playSounds,
      recordStopSound: config.playSounds,
      transcriptionCompleteSound: config.playSounds,
    );
  }

  /// Serializes settings into a string map for SQLite persistence.
  Map<String, String> toStorageMap() {
    return {
      'theme_mode': themeMode.name,
      'locale': locale,
      'launch_at_startup': '$launchAtStartup',
      'show_notifications': '$showNotifications',
      'microphone': microphone,
      'input_gain': '$inputGain',
      'push_to_talk': '$pushToTalk',
      'dead_mic_timeout': '$deadMicTimeout',
      'auto_stop_silence': '$autoStopSilence',
      'stt_provider': sttProvider,
      'stt_model': sttModel,
      'stt_language': sttLanguage,
      'post_process_enabled': '$postProcessEnabled',
      'post_process_preset': postProcessPreset,
      'post_process_provider': postProcessProvider,
      'record_start_sound': '$recordStartSound',
      'record_stop_sound': '$recordStopSound',
      'transcription_complete_sound': '$transcriptionCompleteSound',
      'show_overlay': '$showOverlay',
      'show_floating_button': '$showFloatingButton',
      'floating_button_opacity': '$floatingButtonOpacity',
      'floating_button_size': floatingButtonSize,
      'openai_api_key': openAiApiKey,
      'groq_api_key': groqApiKey,
      'deepgram_api_key': deepgramApiKey,
      'anthropic_api_key': anthropicApiKey,
    };
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? locale,
    bool? launchAtStartup,
    bool? showNotifications,
    String? microphone,
    double? inputGain,
    bool? pushToTalk,
    double? deadMicTimeout,
    double? autoStopSilence,
    String? sttProvider,
    String? sttModel,
    String? sttLanguage,
    bool? postProcessEnabled,
    String? postProcessPreset,
    String? postProcessProvider,
    bool? recordStartSound,
    bool? recordStopSound,
    bool? transcriptionCompleteSound,
    bool? showOverlay,
    bool? showFloatingButton,
    double? floatingButtonOpacity,
    String? floatingButtonSize,
    String? openAiApiKey,
    String? groqApiKey,
    String? deepgramApiKey,
    String? anthropicApiKey,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      locale: locale ?? this.locale,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      showNotifications: showNotifications ?? this.showNotifications,
      microphone: microphone ?? this.microphone,
      inputGain: inputGain ?? this.inputGain,
      pushToTalk: pushToTalk ?? this.pushToTalk,
      deadMicTimeout: deadMicTimeout ?? this.deadMicTimeout,
      autoStopSilence: autoStopSilence ?? this.autoStopSilence,
      sttProvider: sttProvider ?? this.sttProvider,
      sttModel: sttModel ?? this.sttModel,
      sttLanguage: sttLanguage ?? this.sttLanguage,
      postProcessEnabled: postProcessEnabled ?? this.postProcessEnabled,
      postProcessPreset: postProcessPreset ?? this.postProcessPreset,
      postProcessProvider: postProcessProvider ?? this.postProcessProvider,
      recordStartSound: recordStartSound ?? this.recordStartSound,
      recordStopSound: recordStopSound ?? this.recordStopSound,
      transcriptionCompleteSound:
          transcriptionCompleteSound ?? this.transcriptionCompleteSound,
      showOverlay: showOverlay ?? this.showOverlay,
      showFloatingButton: showFloatingButton ?? this.showFloatingButton,
      floatingButtonOpacity:
          floatingButtonOpacity ?? this.floatingButtonOpacity,
      floatingButtonSize: floatingButtonSize ?? this.floatingButtonSize,
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      groqApiKey: groqApiKey ?? this.groqApiKey,
      deepgramApiKey: deepgramApiKey ?? this.deepgramApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
    );
  }
}

ThemeMode _themeModeFromString(String name) {
  return switch (name) {
    'light' => ThemeMode.light,
    'system' => ThemeMode.system,
    _ => ThemeMode.dark,
  };
}

bool _readBool(
  Map<String, String> values,
  String key,
  bool fallback,
) {
  final value = values[key];
  if (value == null) return fallback;
  return value == 'true';
}

double _readDouble(
  Map<String, String> values,
  String key,
  double fallback,
) {
  return double.tryParse(values[key] ?? '') ?? fallback;
}

String _settingModelFromConfig(String modelId) {
  // Now settings store actual model IDs directly.
  return modelId.isEmpty ? 'whisper-medium' : modelId;
}

/// Migrates legacy display-name model values to proper IDs.
String _migrateModelId(String raw) {
  return switch (raw) {
    'Fast (Tiny)' => 'whisper-tiny',
    'Balanced (Small)' => 'whisper-small',
    'High Quality (Medium)' => 'whisper-medium',
    'Best Quality (Large)' => 'whisper-large-v3',
    _ => raw, // already a model ID or unknown → keep as-is
  };
}

String _settingLanguageFromConfig(String languageCode) {
  return switch (languageCode) {
    'en' => 'English',
    'de' => 'German',
    'fr' => 'French',
    'es' => 'Spanish',
    _ => 'Auto-detect',
  };
}

String _settingPresetFromConfig(String preset) {
  return switch (preset) {
    'concise' => 'Concise',
    'translate' => 'Translate',
    _ => 'Clean up',
  };
}

String _configModelIdFromSetting(String setting) {
  // Settings now store model IDs directly.
  return setting.isEmpty ? 'whisper-medium' : setting;
}

String _configLanguageFromSetting(String setting) {
  return switch (setting) {
    'English' => 'en',
    'German' => 'de',
    'French' => 'fr',
    'Spanish' => 'es',
    _ => 'auto',
  };
}

String _configPresetFromSetting(String setting) {
  return switch (setting) {
    'Concise' => 'concise',
    'Translate' => 'translate',
    _ => 'cleanup',
  };
}

/// Central settings notifier — loads from and persists to Drift/SQLite.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final db = ref.watch(historyDatabaseProvider);
    final values = await db.readAppSettings();
    if (values.isNotEmpty) {
      return AppSettings.fromStorageMap(values);
    }

    try {
      final config = await ref.read(configProvider.future);
      return AppSettings.fromGoConfig(config);
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  /// Update one or more settings and persist the change.
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? const AppSettings();
    final updated = updater(current);
    state = AsyncData(updated);
    await ref.read(historyDatabaseProvider).writeAppSettings(updated.toStorageMap());
  }

  /// Toggle between dark and light theme.
  Future<void> toggleDarkLight() async {
    await updateSettings(
      (s) => s.copyWith(
        themeMode:
            s.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
    );
  }

  /// Restore all settings to factory defaults.
  Future<void> resetToDefaults() async {
    await ref.read(historyDatabaseProvider).resetAppSettings();
    state = const AsyncData(AppSettings.defaults);
  }
}

/// Central settings provider — single source of truth for all app settings.
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Effective recording/runtime config: Go config overlaid with Flutter settings.
final effectiveConfigProvider = Provider<WhisPasteConfig>((ref) {
  final diskConfig = ref.watch(configProvider).value ?? const WhisPasteConfig();
  final settings = ref.watch(settingsProvider).value;
  if (settings == null) return diskConfig;

  return diskConfig.copyWith(
    useLocalStt: settings.sttProvider == 'On Device (Private)',
    localModelId: _configModelIdFromSetting(settings.sttModel),
    transcriptionLanguage: _configLanguageFromSetting(settings.sttLanguage),
    smartMode: settings.postProcessEnabled,
    smartModePreset: _configPresetFromSetting(settings.postProcessPreset),
    playSounds: settings.recordStartSound ||
        settings.recordStopSound ||
        settings.transcriptionCompleteSound,
    inputGain: settings.inputGain / 100.0,
  );
});
