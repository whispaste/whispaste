/// App settings provider — persisted via SQLite, loaded from Go config.
///
/// **Architecture note**: This file lives in `core/config/` because every
/// layer depends on it (theme, l10n, services, features). It intentionally
/// imports from `features/history/data/` (database provider for persistence)
/// and `services/` (Go config reader). This is a documented bridge — not a
/// bug. Moving the database provider to `core/data/` would be the clean
/// resolution; tracked as a future refactor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/history/data/database.dart'; // see note above
import '../../services/config_service.dart'; // see note above
import 'settings_enums.dart';

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
    this.soundVolume = 80.0,
    // After Transcription
    this.afterTranscription = 'clipboard',
    // Overlay & Floating Button
    this.showOverlay = true,
    this.overlayMode = 'in-window',
    this.showFloatingButton = true,
    this.floatingButtonOpacity = 0.9,
    this.floatingButtonSize = 'Normal',
    // Cloud Providers (API keys)
    this.openAiApiKey = '',
    this.groqApiKey = '',
    this.deepgramApiKey = '',
    this.anthropicApiKey = '',
    this.geminiApiKey = '',
    // Cloud Provider Details
    this.cloudSttProvider = 'openai',
    this.cloudLlmModel = '',
    // Post-Processing Advanced
    this.smartModePrompt = '',
    this.smartModeTarget = '',
    // Behavior
    this.maxRecordDuration = 120,
    this.closeToTray = true,
    this.errorReporting = true,
    this.gpuAcceleration = 'auto',
    this.autoPasteDelay = 200,
    // Audio Processing
    this.trimSilence = false,
    this.useVAD = false,
    this.vadSensitivity = 0.5,
    // Text Replacements
    this.textReplacementsEnabled = false,
    // Updates
    this.checkUpdates = true,
    // Hotkey
    this.hotkeyKey = 'D',
    this.hotkeyModifiers = 'ctrl+shift',
    // Floating Button Advanced
    this.floatingButtonLocked = false,
    this.floatingButtonAutoHide = 'never',
    // Floating Button Position (persisted across sessions)
    this.floatingButtonX = -1.0,
    this.floatingButtonY = -1.0,
    // Main Window State (persisted across sessions; -1 = not set)
    this.windowX = -1.0,
    this.windowY = -1.0,
    this.windowWidth = 1100.0,
    this.windowHeight = 750.0,
    this.windowMaximized = false,
    // Onboarding
    this.onboardingCompleted = false,
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
  final double soundVolume;

  // After Transcription
  /// What happens after transcription: 'clipboard', 'paste', 'nothing'
  final String afterTranscription;

  // Overlay & Floating Button
  final bool showOverlay;
  /// 'in-window', 'floating', or 'off'.
  final String overlayMode;
  final bool showFloatingButton;
  final double floatingButtonOpacity;
  final String floatingButtonSize;

  // Cloud Providers (API keys)
  final String openAiApiKey;
  final String groqApiKey;
  final String deepgramApiKey;
  final String anthropicApiKey;
  final String geminiApiKey;

  // Cloud Provider Details
  final String cloudSttProvider;
  final String cloudLlmModel;

  // Post-Processing Advanced
  final String smartModePrompt;
  final String smartModeTarget;

  // Behavior
  final int maxRecordDuration;
  final bool closeToTray;
  final bool errorReporting;
  final String gpuAcceleration;
  final int autoPasteDelay;

  // Audio Processing
  final bool trimSilence;
  final bool useVAD;
  final double vadSensitivity;

  // Text Replacements
  final bool textReplacementsEnabled;

  // Updates
  final bool checkUpdates;

  // Hotkey
  final String hotkeyKey;
  final String hotkeyModifiers;

  // Floating Button Advanced
  final bool floatingButtonLocked;
  final String floatingButtonAutoHide;

  // Floating Button Position (persisted across sessions; -1 = not set)
  final double floatingButtonX;
  final double floatingButtonY;

  // Main Window State (persisted across sessions; -1 = not set)
  final double windowX;
  final double windowY;
  final double windowWidth;
  final double windowHeight;
  final bool windowMaximized;

  // Onboarding
  final bool onboardingCompleted;

  // ---------------------------------------------------------------------------
  // Typed accessors — prefer these over raw string comparisons.
  // ---------------------------------------------------------------------------

  SttProviderType get sttProviderType => SttProviderType.fromValue(sttProvider);
  CloudSttProvider get cloudSttProviderType =>
      CloudSttProvider.fromValue(cloudSttProvider);
  PostProcessProviderType get postProcessProviderType =>
      PostProcessProviderType.fromValue(postProcessProvider);
  PostProcessPreset get postProcessPresetType =>
      PostProcessPreset.fromDisplayValue(postProcessPreset);
  AfterTranscriptionAction get afterTranscriptionAction =>
      AfterTranscriptionAction.fromValue(afterTranscription);
  OverlayMode get overlayModeType => OverlayMode.fromValue(overlayMode);
  FloatingButtonSize get floatingButtonSizeType =>
      FloatingButtonSize.fromValue(floatingButtonSize);
  GpuAcceleration get gpuAccelerationType =>
      GpuAcceleration.fromValue(gpuAcceleration);
  FloatingButtonAutoHide get floatingButtonAutoHideType =>
      FloatingButtonAutoHide.fromValue(floatingButtonAutoHide);

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
      soundVolume: _readDouble(values, 'sound_volume', defaults.soundVolume),
      afterTranscription:
          values['after_transcription'] ?? defaults.afterTranscription,
      showOverlay: _readBool(values, 'show_overlay', defaults.showOverlay),
      overlayMode: values['overlay_mode'] ??
          (_readBool(values, 'show_overlay', defaults.showOverlay)
              ? defaults.overlayMode
              : OverlayMode.off.value),
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
      geminiApiKey: values['gemini_api_key'] ?? defaults.geminiApiKey,
      cloudSttProvider:
          values['cloud_stt_provider'] ?? defaults.cloudSttProvider,
      cloudLlmModel: values['cloud_llm_model'] ?? defaults.cloudLlmModel,
      smartModePrompt:
          values['smart_mode_prompt'] ?? defaults.smartModePrompt,
      smartModeTarget:
          values['smart_mode_target'] ?? defaults.smartModeTarget,
      maxRecordDuration:
          _readInt(values, 'max_record_duration', defaults.maxRecordDuration),
      closeToTray: _readBool(values, 'close_to_tray', defaults.closeToTray),
      errorReporting:
          _readBool(values, 'error_reporting', defaults.errorReporting),
      gpuAcceleration:
          values['gpu_acceleration'] ?? defaults.gpuAcceleration,
      autoPasteDelay:
          _readInt(values, 'auto_paste_delay', defaults.autoPasteDelay),
      trimSilence: _readBool(values, 'trim_silence', defaults.trimSilence),
      useVAD: _readBool(values, 'use_vad', defaults.useVAD),
      vadSensitivity:
          _readDouble(values, 'vad_sensitivity', defaults.vadSensitivity),
      textReplacementsEnabled: _readBool(
        values,
        'text_replacements_enabled',
        defaults.textReplacementsEnabled,
      ),
      checkUpdates:
          _readBool(values, 'check_updates', defaults.checkUpdates),
      hotkeyKey: values['hotkey_key'] ?? defaults.hotkeyKey,
      hotkeyModifiers:
          values['hotkey_modifiers'] ?? defaults.hotkeyModifiers,
      floatingButtonLocked: _readBool(
        values,
        'floating_button_locked',
        defaults.floatingButtonLocked,
      ),
      floatingButtonAutoHide:
          values['floating_button_auto_hide'] ?? defaults.floatingButtonAutoHide,
      floatingButtonX: _readDouble(
        values,
        'floating_button_x',
        defaults.floatingButtonX,
      ),
      floatingButtonY: _readDouble(
        values,
        'floating_button_y',
        defaults.floatingButtonY,
      ),
      windowX: _readDouble(values, 'window_x', defaults.windowX),
      windowY: _readDouble(values, 'window_y', defaults.windowY),
      windowWidth:
          _readDouble(values, 'window_width', defaults.windowWidth),
      windowHeight:
          _readDouble(values, 'window_height', defaults.windowHeight),
      windowMaximized:
          _readBool(values, 'window_maximized', defaults.windowMaximized),
      onboardingCompleted: _readBool(
        values,
        'onboarding_completed',
        defaults.onboardingCompleted,
      ),
    );
  }

  /// Seeds settings from the existing Go config when no Flutter row exists yet.
  factory AppSettings.fromGoConfig(WhisPasteConfig config) {
    return AppSettings(
      inputGain: config.inputGain * 100.0,
      sttProvider: config.useLocalStt
          ? SttProviderType.onDevice.value
          : defaults.sttProvider,
      sttModel: _settingModelFromConfig(config.localModelId),
      sttLanguage: _settingLanguageFromConfig(config.transcriptionLanguage),
      postProcessEnabled: config.smartMode,
      postProcessPreset: _settingPresetFromConfig(config.smartModePreset),
      postProcessProvider: PostProcessProviderType.local.value,
      recordStartSound: config.playSounds,
      recordStopSound: config.playSounds,
      transcriptionCompleteSound: config.playSounds,
      maxRecordDuration: config.maxRecordSec,
      gpuAcceleration: config.gpuAcceleration,
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
      'sound_volume': '$soundVolume',
      'after_transcription': afterTranscription,
      'show_overlay': '$showOverlay',
      'overlay_mode': overlayMode,
      'show_floating_button': '$showFloatingButton',
      'floating_button_opacity': '$floatingButtonOpacity',
      'floating_button_size': floatingButtonSize,
      'openai_api_key': openAiApiKey,
      'groq_api_key': groqApiKey,
      'deepgram_api_key': deepgramApiKey,
      'anthropic_api_key': anthropicApiKey,
      'gemini_api_key': geminiApiKey,
      'cloud_stt_provider': cloudSttProvider,
      'cloud_llm_model': cloudLlmModel,
      'smart_mode_prompt': smartModePrompt,
      'smart_mode_target': smartModeTarget,
      'max_record_duration': '$maxRecordDuration',
      'close_to_tray': '$closeToTray',
      'error_reporting': '$errorReporting',
      'gpu_acceleration': gpuAcceleration,
      'auto_paste_delay': '$autoPasteDelay',
      'trim_silence': '$trimSilence',
      'use_vad': '$useVAD',
      'vad_sensitivity': '$vadSensitivity',
      'text_replacements_enabled': '$textReplacementsEnabled',
      'check_updates': '$checkUpdates',
      'hotkey_key': hotkeyKey,
      'hotkey_modifiers': hotkeyModifiers,
      'floating_button_locked': '$floatingButtonLocked',
      'floating_button_auto_hide': floatingButtonAutoHide,
      'floating_button_x': '$floatingButtonX',
      'floating_button_y': '$floatingButtonY',
      'window_x': '$windowX',
      'window_y': '$windowY',
      'window_width': '$windowWidth',
      'window_height': '$windowHeight',
      'window_maximized': '$windowMaximized',
      'onboarding_completed': '$onboardingCompleted',
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
    double? soundVolume,
    String? afterTranscription,
    bool? showOverlay,
    String? overlayMode,
    bool? showFloatingButton,
    double? floatingButtonOpacity,
    String? floatingButtonSize,
    String? openAiApiKey,
    String? groqApiKey,
    String? deepgramApiKey,
    String? anthropicApiKey,
    String? geminiApiKey,
    String? cloudSttProvider,
    String? cloudLlmModel,
    String? smartModePrompt,
    String? smartModeTarget,
    int? maxRecordDuration,
    bool? closeToTray,
    bool? errorReporting,
    String? gpuAcceleration,
    int? autoPasteDelay,
    bool? trimSilence,
    bool? useVAD,
    double? vadSensitivity,
    bool? textReplacementsEnabled,
    bool? checkUpdates,
    String? hotkeyKey,
    String? hotkeyModifiers,
    bool? floatingButtonLocked,
    String? floatingButtonAutoHide,
    double? floatingButtonX,
    double? floatingButtonY,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
    bool? windowMaximized,
    bool? onboardingCompleted,
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
      soundVolume: soundVolume ?? this.soundVolume,
      afterTranscription: afterTranscription ?? this.afterTranscription,
      showOverlay: showOverlay ?? this.showOverlay,
      overlayMode: overlayMode ?? this.overlayMode,
      showFloatingButton: showFloatingButton ?? this.showFloatingButton,
      floatingButtonOpacity:
          floatingButtonOpacity ?? this.floatingButtonOpacity,
      floatingButtonSize: floatingButtonSize ?? this.floatingButtonSize,
      openAiApiKey: openAiApiKey ?? this.openAiApiKey,
      groqApiKey: groqApiKey ?? this.groqApiKey,
      deepgramApiKey: deepgramApiKey ?? this.deepgramApiKey,
      anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      cloudSttProvider: cloudSttProvider ?? this.cloudSttProvider,
      cloudLlmModel: cloudLlmModel ?? this.cloudLlmModel,
      smartModePrompt: smartModePrompt ?? this.smartModePrompt,
      smartModeTarget: smartModeTarget ?? this.smartModeTarget,
      maxRecordDuration: maxRecordDuration ?? this.maxRecordDuration,
      closeToTray: closeToTray ?? this.closeToTray,
      errorReporting: errorReporting ?? this.errorReporting,
      gpuAcceleration: gpuAcceleration ?? this.gpuAcceleration,
      autoPasteDelay: autoPasteDelay ?? this.autoPasteDelay,
      trimSilence: trimSilence ?? this.trimSilence,
      useVAD: useVAD ?? this.useVAD,
      vadSensitivity: vadSensitivity ?? this.vadSensitivity,
      textReplacementsEnabled:
          textReplacementsEnabled ?? this.textReplacementsEnabled,
      checkUpdates: checkUpdates ?? this.checkUpdates,
      hotkeyKey: hotkeyKey ?? this.hotkeyKey,
      hotkeyModifiers: hotkeyModifiers ?? this.hotkeyModifiers,
      floatingButtonLocked: floatingButtonLocked ?? this.floatingButtonLocked,
      floatingButtonAutoHide:
          floatingButtonAutoHide ?? this.floatingButtonAutoHide,
      floatingButtonX: floatingButtonX ?? this.floatingButtonX,
      floatingButtonY: floatingButtonY ?? this.floatingButtonY,
      windowX: windowX ?? this.windowX,
      windowY: windowY ?? this.windowY,
      windowWidth: windowWidth ?? this.windowWidth,
      windowHeight: windowHeight ?? this.windowHeight,
      windowMaximized: windowMaximized ?? this.windowMaximized,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          themeMode == other.themeMode &&
          locale == other.locale &&
          launchAtStartup == other.launchAtStartup &&
          showNotifications == other.showNotifications &&
          microphone == other.microphone &&
          inputGain == other.inputGain &&
          pushToTalk == other.pushToTalk &&
          deadMicTimeout == other.deadMicTimeout &&
          autoStopSilence == other.autoStopSilence &&
          sttProvider == other.sttProvider &&
          sttModel == other.sttModel &&
          sttLanguage == other.sttLanguage &&
          postProcessEnabled == other.postProcessEnabled &&
          postProcessPreset == other.postProcessPreset &&
          postProcessProvider == other.postProcessProvider &&
          recordStartSound == other.recordStartSound &&
          recordStopSound == other.recordStopSound &&
          transcriptionCompleteSound == other.transcriptionCompleteSound &&
          soundVolume == other.soundVolume &&
          afterTranscription == other.afterTranscription &&
          showOverlay == other.showOverlay &&
          overlayMode == other.overlayMode &&
          showFloatingButton == other.showFloatingButton &&
          floatingButtonOpacity == other.floatingButtonOpacity &&
          floatingButtonSize == other.floatingButtonSize &&
          openAiApiKey == other.openAiApiKey &&
          groqApiKey == other.groqApiKey &&
          deepgramApiKey == other.deepgramApiKey &&
          anthropicApiKey == other.anthropicApiKey &&
          geminiApiKey == other.geminiApiKey &&
          cloudSttProvider == other.cloudSttProvider &&
          cloudLlmModel == other.cloudLlmModel &&
          smartModePrompt == other.smartModePrompt &&
          smartModeTarget == other.smartModeTarget &&
          maxRecordDuration == other.maxRecordDuration &&
          closeToTray == other.closeToTray &&
          errorReporting == other.errorReporting &&
          gpuAcceleration == other.gpuAcceleration &&
          autoPasteDelay == other.autoPasteDelay &&
          trimSilence == other.trimSilence &&
          useVAD == other.useVAD &&
          vadSensitivity == other.vadSensitivity &&
          textReplacementsEnabled == other.textReplacementsEnabled &&
          checkUpdates == other.checkUpdates &&
          hotkeyKey == other.hotkeyKey &&
          hotkeyModifiers == other.hotkeyModifiers &&
          floatingButtonLocked == other.floatingButtonLocked &&
          floatingButtonAutoHide == other.floatingButtonAutoHide &&
          floatingButtonX == other.floatingButtonX &&
          floatingButtonY == other.floatingButtonY &&
          windowX == other.windowX &&
          windowY == other.windowY &&
          windowWidth == other.windowWidth &&
          windowHeight == other.windowHeight &&
          windowMaximized == other.windowMaximized &&
          onboardingCompleted == other.onboardingCompleted;

  @override
  int get hashCode => Object.hash(
        themeMode, locale, launchAtStartup, showNotifications,
        microphone, inputGain, pushToTalk,
        deadMicTimeout, autoStopSilence,
        sttProvider, sttModel, sttLanguage,
        postProcessEnabled, postProcessPreset, postProcessProvider,
        recordStartSound, recordStopSound, transcriptionCompleteSound,
        // Object.hash supports max 20 positional args; nest for rest.
        Object.hash(
          soundVolume, afterTranscription,
          showOverlay, overlayMode, showFloatingButton,
          floatingButtonOpacity, floatingButtonSize,
          openAiApiKey, groqApiKey, deepgramApiKey,
          anthropicApiKey, geminiApiKey,
          cloudSttProvider, cloudLlmModel,
          smartModePrompt, smartModeTarget,
          maxRecordDuration, closeToTray, errorReporting,
          Object.hash(
            gpuAcceleration, autoPasteDelay,
            trimSilence, useVAD, vadSensitivity,
            textReplacementsEnabled, checkUpdates,
            hotkeyKey, hotkeyModifiers,
            floatingButtonLocked, floatingButtonAutoHide,
            floatingButtonX, floatingButtonY,
            windowX, windowY, windowWidth, windowHeight,
            windowMaximized, onboardingCompleted,
          ),
        ),
      );
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

int _readInt(
  Map<String, String> values,
  String key,
  int fallback,
) {
  return int.tryParse(values[key] ?? '') ?? fallback;
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
  return PostProcessPreset.fromGoKey(preset).displayValue;
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
  return PostProcessPreset.fromDisplayValue(setting).goKey;
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
    useLocalStt: settings.sttProviderType.isLocal,
    localModelId: _configModelIdFromSetting(settings.sttModel),
    transcriptionLanguage: _configLanguageFromSetting(settings.sttLanguage),
    smartMode: settings.postProcessEnabled,
    smartModePreset: _configPresetFromSetting(settings.postProcessPreset),
    playSounds: settings.recordStartSound ||
        settings.recordStopSound ||
        settings.transcriptionCompleteSound,
    inputGain: settings.inputGain / 100.0,
    maxRecordSec: settings.maxRecordDuration,
    gpuAcceleration: settings.gpuAcceleration,
  );
});
