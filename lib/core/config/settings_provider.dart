/// App settings provider — persisted via SQLite.
///
/// **Architecture note**: This file lives in `core/config/` because every
/// layer depends on it (theme, l10n, services, features). It imports from
/// `core/data/` (database provider for persistence) and `services/path_service`
/// (cross-platform path helpers). The Go config dependency has been removed;
/// a one-time migration reads the legacy file directly if no Flutter settings
/// exist yet.
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../../services/path_service.dart';
import 'secure_key_store.dart';
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
    this.sttProvider = 'On Device',
    this.sttModel = 'whisper-medium',
    this.sttLanguage = 'Auto-detect',
    // Post-Processing
    this.postProcessEnabled = false,
    this.postProcessPreset = 'Clean up',
    this.postProcessProvider = 'Local',
    // Sound & Feedback
    this.recordStartSound = true,
    this.recordStopSound = true,
    this.transcriptionCompleteSound = true,
    this.durationWarningSound = true,
    this.soundVolume = 80.0,
    // After Transcription
    this.afterTranscription = 'clipboard',
    // Overlay & Floating Button
    this.showOverlay = false,
    this.overlayMode = 'in-window',
    this.overlayStartPosition = 'top-center',
    this.showFloatingButton = false,
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
    // Floating Button Position (persisted across sessions)
    this.floatingButtonX = -1.0,
    this.floatingButtonY = -1.0,
    // Floating Overlay Position (persisted across sessions; -1 = not set)
    this.floatingOverlayX = -1.0,
    this.floatingOverlayY = -1.0,
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
  final bool durationWarningSound;
  final double soundVolume;

  // After Transcription
  /// What happens after transcription: 'clipboard', 'paste', 'nothing'
  final String afterTranscription;

  // Overlay & Floating Button
  final bool showOverlay;
  /// 'in-window', 'floating', or 'off'.
  final String overlayMode;
  /// 'top-center', 'bottom-center', or 'last-position'.
  final String overlayStartPosition;
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

  // Floating Button Position (persisted across sessions; -1 = not set)
  final double floatingButtonX;
  final double floatingButtonY;

  // Floating Overlay Position (persisted across sessions; -1 = not set)
  final double floatingOverlayX;
  final double floatingOverlayY;

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
  OverlayStartPosition get overlayStartPositionType =>
      OverlayStartPosition.fromValue(overlayStartPosition);
  FloatingButtonSize get floatingButtonSizeType =>
      FloatingButtonSize.fromValue(floatingButtonSize);
  GpuAcceleration get gpuAccelerationType =>
      GpuAcceleration.fromValue(gpuAcceleration);

  /// Resolved model ID — falls back to `whisper-medium` if empty.
  String get effectiveModelId => sttModel.isEmpty ? 'whisper-medium' : sttModel;

  /// STT language code for the whisper server (e.g. `en`, `de`, `auto`).
  ///
  /// Converts the user-facing display value stored in [sttLanguage] to the
  /// short code expected by whisper-server's `language` parameter.
  String get sttLanguageCode => switch (sttLanguage) {
    'English' => 'en',
    'German' => 'de',
    'French' => 'fr',
    'Spanish' => 'es',
    _ => 'auto',
  };

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
      durationWarningSound: _readBool(
        values,
        'duration_warning_sound',
        defaults.durationWarningSound,
      ),
      soundVolume: _readDouble(values, 'sound_volume', defaults.soundVolume),
      afterTranscription:
          values['after_transcription'] ?? defaults.afterTranscription,
      showOverlay: _readBool(values, 'show_overlay', defaults.showOverlay),
      overlayMode: values['overlay_mode'] ??
          (_readBool(values, 'show_overlay', defaults.showOverlay)
              ? defaults.overlayMode
              : OverlayMode.off.value),
      overlayStartPosition:
          values['overlay_start_position'] ?? defaults.overlayStartPosition,
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
      floatingOverlayX: _readDouble(
        values,
        'floating_overlay_x',
        defaults.floatingOverlayX,
      ),
      floatingOverlayY: _readDouble(
        values,
        'floating_overlay_y',
        defaults.floatingOverlayY,
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

  /// One-time migration: seeds Flutter settings from the legacy Go
  /// `config.json`.  Accepts the raw JSON map so we don't depend on a
  /// Go config class.
  factory AppSettings.fromGoConfig(Map<String, dynamic> json) {
    final useLocal = json['use_local_stt'] as bool? ?? false;
    final modelId = json['local_model_id'] as String? ?? 'whisper-small';
    final lang = json['transcription_language'] as String? ?? 'auto';
    final gpu = json['gpu_acceleration'] as String? ?? 'auto';
    final smart = json['smart_mode'] as bool? ?? false;
    final smartPreset = json['smart_mode_preset'] as String? ?? '';
    final autoPaste = json['auto_paste'] as bool? ?? true;
    final sounds = json['play_sounds'] as bool? ?? true;
    final maxSec = json['max_record_sec'] as int? ?? 120;
    final gain = (json['input_gain'] as num?)?.toDouble() ?? 1.0;

    return AppSettings(
      inputGain: gain * 100.0,
      sttProvider: useLocal
          ? SttProviderType.onDevice.value
          : defaults.sttProvider,
      sttModel: _settingModelFromConfig(modelId),
      sttLanguage: _settingLanguageFromConfig(lang),
      postProcessEnabled: smart,
      postProcessPreset: _settingPresetFromConfig(smartPreset),
      postProcessProvider: PostProcessProviderType.local.value,
      recordStartSound: sounds,
      recordStopSound: sounds,
      transcriptionCompleteSound: sounds,
      durationWarningSound: sounds,
      afterTranscription: autoPaste ? 'clipboard' : 'nothing',
      maxRecordDuration: maxSec,
      gpuAcceleration: gpu,
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
      'duration_warning_sound': '$durationWarningSound',
      'sound_volume': '$soundVolume',
      'after_transcription': afterTranscription,
      'show_overlay': '$showOverlay',
      'overlay_mode': overlayMode,
      'overlay_start_position': overlayStartPosition,
      'show_floating_button': '$showFloatingButton',
      'floating_button_opacity': '$floatingButtonOpacity',
      'floating_button_size': floatingButtonSize,
      // API keys are stored in secure storage — never persist to SQLite.
      'openai_api_key': '',
      'groq_api_key': '',
      'deepgram_api_key': '',
      'anthropic_api_key': '',
      'gemini_api_key': '',
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
      'floating_button_x': '$floatingButtonX',
      'floating_button_y': '$floatingButtonY',
      'floating_overlay_x': '$floatingOverlayX',
      'floating_overlay_y': '$floatingOverlayY',
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
    bool? durationWarningSound,
    double? soundVolume,
    String? afterTranscription,
    bool? showOverlay,
    String? overlayMode,
    String? overlayStartPosition,
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
    double? floatingButtonX,
    double? floatingButtonY,
    double? floatingOverlayX,
    double? floatingOverlayY,
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
      durationWarningSound:
          durationWarningSound ?? this.durationWarningSound,
      soundVolume: soundVolume ?? this.soundVolume,
      afterTranscription: afterTranscription ?? this.afterTranscription,
      showOverlay: showOverlay ?? this.showOverlay,
      overlayMode: overlayMode ?? this.overlayMode,
      overlayStartPosition:
          overlayStartPosition ?? this.overlayStartPosition,
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
      floatingButtonX: floatingButtonX ?? this.floatingButtonX,
      floatingButtonY: floatingButtonY ?? this.floatingButtonY,
      floatingOverlayX: floatingOverlayX ?? this.floatingOverlayX,
      floatingOverlayY: floatingOverlayY ?? this.floatingOverlayY,
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
          durationWarningSound == other.durationWarningSound &&
          soundVolume == other.soundVolume &&
          afterTranscription == other.afterTranscription &&
          showOverlay == other.showOverlay &&
          overlayMode == other.overlayMode &&
          overlayStartPosition == other.overlayStartPosition &&
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
          floatingButtonX == other.floatingButtonX &&
          floatingButtonY == other.floatingButtonY &&
          floatingOverlayX == other.floatingOverlayX &&
          floatingOverlayY == other.floatingOverlayY &&
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
        durationWarningSound,
        // Object.hash supports max 20 positional args; nest for rest.
        Object.hash(
          soundVolume, afterTranscription,
          showOverlay, overlayMode, overlayStartPosition, showFloatingButton,
          floatingButtonOpacity, floatingButtonSize,
          openAiApiKey, groqApiKey, deepgramApiKey,
          anthropicApiKey, geminiApiKey,
          cloudSttProvider, cloudLlmModel,
          smartModePrompt, smartModeTarget,
          maxRecordDuration, closeToTray,
          Object.hash(
            errorReporting, gpuAcceleration, autoPasteDelay,
            trimSilence, useVAD, vadSensitivity,
            textReplacementsEnabled, checkUpdates,
            hotkeyKey, hotkeyModifiers,
            floatingButtonX, floatingButtonY,
            floatingOverlayX, floatingOverlayY,
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
  return PostProcessPreset.fromKey(preset).displayValue;
}

/// Central settings notifier — loads from and persists to Drift/SQLite.
///
/// API keys are stored in platform-native secure storage and merged into
/// the in-memory [AppSettings] on load. A one-time migration moves any
/// plaintext keys from SQLite into secure storage and clears the SQLite rows.
class SettingsNotifier extends AsyncNotifier<AppSettings> {
  /// Completes when deferred secure-key migration/merge finishes.
  @visibleForTesting
  Future<void>? secureKeysFuture;

  @override
  Future<AppSettings> build() async {
    final db = ref.watch(historyDatabaseProvider);
    final secureStore = ref.watch(secureKeyStoreProvider);
    final values = await db.readAppSettings();

    AppSettings settings;
    if (values.isNotEmpty) {
      settings = AppSettings.fromStorageMap(values);
    } else {
      // One-time migration: read the legacy Go config.json if it exists.
      final migrated = _tryMigrateGoConfig();
      if (migrated != null) {
        settings = migrated;
        // Persist immediately so migration never re-runs.
        await db.writeAppSettings(settings.toStorageMap());
        dev.log('Migrated Go config persisted to SQLite', name: 'Settings');
      } else {
        settings = AppSettings.defaults;
      }
    }

    // Defer slow secure store operations to after initial load.
    // This lets the app show its window and become interactive immediately.
    // API keys will be available within ~200ms after startup.
    secureKeysFuture = Future.microtask(() async {
      try {
        await _migrateApiKeys(values, secureStore, db);
        final merged =
            await _mergeSecureKeys(state.value ?? settings, secureStore);
        if (state.value != merged) {
          state = AsyncData(merged);
        }
      } catch (_) {
        // Non-fatal — keys will be missing until next restart.
      }
    });

    return settings;
  }

  /// Update one or more settings and persist the change.
  Future<void> updateSettings(AppSettings Function(AppSettings) updater) async {
    final current = state.value ?? const AppSettings();
    final updated = updater(current);
    state = AsyncData(updated);

    // Persist API key changes to secure storage.
    final secureStore = ref.read(secureKeyStoreProvider);
    await _syncApiKeysToSecureStorage(current, updated, secureStore);

    // Persist all non-key settings to SQLite (toStorageMap writes '' for keys).
    await ref.read(historyDatabaseProvider).writeAppSettings(
          updated.toStorageMap(),
        );
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
  ///
  /// Clears secure-storage API keys, persisted settings (including window
  /// position/size and floating-button position), and daily analytics stats.
  Future<void> resetToDefaults() async {
    // Clear secure storage API keys.
    final secureStore = ref.read(secureKeyStoreProvider);
    for (final secureKey in apiKeyMapping.values) {
      await secureStore.deleteKey(secureKey);
    }
    final db = ref.read(historyDatabaseProvider);
    await db.resetAppSettings();
    await db.resetDailyStats();
    state = const AsyncData(AppSettings.defaults);
  }

  /// Full factory reset — deletes ALL user data, models, and settings.
  ///
  /// The caller MUST stop the STT subprocess before calling this method
  /// (to avoid file-locking on the whisper-server binary).
  Future<void> factoryReset() async {
    final db = ref.read(historyDatabaseProvider);

    // 1. Clear ALL secure storage API keys.
    final secureStore = ref.read(secureKeyStoreProvider);
    for (final secureKey in apiKeyMapping.values) {
      await secureStore.deleteKey(secureKey);
    }

    // 2. Delete all database content (history, tags, projects, etc.).
    await db.deleteAllData();

    // 3. Delete downloaded models directory.
    _tryDeleteDir(sttDir());

    // 4. Delete log files.
    final logsDir = p.join(appDataDir(), 'logs');
    _tryDeleteDir(logsDir);

    // 5. Delete PID files from subprocess_guard.
    _tryDeleteFile(p.join(appDataDir(), '.whisper-server.pid'));
    _tryDeleteFile(p.join(appDataDir(), '.llama-server.pid'));

    // 6. Delete crash queue database.
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db'));
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db-wal'));
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db-shm'));

    // 7. Delete legacy Go config.
    _tryDeleteFile(p.join(appDataDir(), 'config.json'));

    // 8. Clean up temp WAV files.
    _cleanupTempWavFiles();

    // 9. Reset in-memory state.
    state = const AsyncData(AppSettings.defaults);

    dev.log('Factory reset complete', name: 'Settings');
  }

  static void _tryDeleteDir(String path) {
    try {
      final dir = Directory(path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      dev.log('Factory reset: failed to delete dir $path: $e',
          name: 'Settings');
    }
  }

  static void _tryDeleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      dev.log('Factory reset: failed to delete file $path: $e',
          name: 'Settings');
    }
  }

  static void _cleanupTempWavFiles() {
    try {
      final tempDir = Directory.systemTemp;
      for (final entity in tempDir.listSync()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('whispaste_') && name.endsWith('.wav')) {
            entity.deleteSync();
          }
        }
      }
    } catch (e) {
      dev.log('Factory reset: failed to clean temp WAVs: $e',
          name: 'Settings');
    }
  }

  /// Reads the legacy Go `config.json` once and converts it to [AppSettings].
  ///
  /// Returns `null` if the file doesn't exist or can't be parsed — callers
  /// fall back to [AppSettings.defaults].
  static AppSettings? _tryMigrateGoConfig() {
    try {
      final configPath = p.join(appDataDir(), 'config.json');
      final file = File(configPath);
      if (!file.existsSync()) return null;
      final contents = file.readAsStringSync();
      final raw = jsonDecode(contents);
      if (raw is! Map<String, dynamic>) {
        dev.log('Go config JSON is not an object, skipping migration',
            name: 'Settings');
        return null;
      }
      dev.log('Migrating Go config.json → Flutter settings', name: 'Settings');
      return AppSettings.fromGoConfig(raw);
    } catch (e) {
      // Catches StateError (missing APPDATA), FormatException (bad JSON),
      // FileSystemException (I/O failure), TypeError (unexpected JSON shape),
      // and anything else.  Migration is best-effort — never crash the app.
      dev.log('Go config migration failed, using defaults: $e',
          name: 'Settings');
      return null;
    }
  }
}

/// Migrate plaintext API keys from SQLite → secure storage, then clear SQLite.
Future<void> _migrateApiKeys(
  Map<String, String> sqliteValues,
  SecureKeyStore secureStore,
  HistoryDatabase db,
) async {
  // SQLite key → secure-storage key mapping.
  const sqliteToSecure = {
    'openai_api_key': 'wp_openai_api_key',
    'groq_api_key': 'wp_groq_api_key',
    'deepgram_api_key': 'wp_deepgram_api_key',
    'anthropic_api_key': 'wp_anthropic_api_key',
    'gemini_api_key': 'wp_gemini_api_key',
  };

  var migrated = false;
  for (final entry in sqliteToSecure.entries) {
    final plaintext = sqliteValues[entry.key];
    if (plaintext == null || plaintext.isEmpty) continue;

    // Only migrate if secure storage doesn't already have a value.
    final existing = await secureStore.readKey(entry.value);
    if (existing == null || existing.isEmpty) {
      await secureStore.writeKey(entry.value, plaintext);
    }
    migrated = true;
  }

  // Re-write settings with empty API key fields to clear SQLite.
  if (migrated) {
    final cleaned = Map<String, String>.from(sqliteValues);
    for (final key in sqliteToSecure.keys) {
      cleaned[key] = '';
    }
    await db.writeAppSettings(cleaned);
  }
}

/// Merge API keys from secure storage into [settings].
Future<AppSettings> _mergeSecureKeys(
  AppSettings settings,
  SecureKeyStore secureStore,
) async {
  final keys = await secureStore.readAllApiKeys();
  if (keys.isEmpty) return settings;

  return settings.copyWith(
    openAiApiKey: keys['wp_openai_api_key'] ?? settings.openAiApiKey,
    groqApiKey: keys['wp_groq_api_key'] ?? settings.groqApiKey,
    deepgramApiKey: keys['wp_deepgram_api_key'] ?? settings.deepgramApiKey,
    anthropicApiKey: keys['wp_anthropic_api_key'] ?? settings.anthropicApiKey,
    geminiApiKey: keys['wp_gemini_api_key'] ?? settings.geminiApiKey,
  );
}

/// Write changed API keys to secure storage.
Future<void> _syncApiKeysToSecureStorage(
  AppSettings oldSettings,
  AppSettings newSettings,
  SecureKeyStore secureStore,
) async {
  final pairs = <String, _KeyPair>{
    'wp_openai_api_key': (old: oldSettings.openAiApiKey, cur: newSettings.openAiApiKey),
    'wp_groq_api_key': (old: oldSettings.groqApiKey, cur: newSettings.groqApiKey),
    'wp_deepgram_api_key': (old: oldSettings.deepgramApiKey, cur: newSettings.deepgramApiKey),
    'wp_anthropic_api_key': (old: oldSettings.anthropicApiKey, cur: newSettings.anthropicApiKey),
    'wp_gemini_api_key': (old: oldSettings.geminiApiKey, cur: newSettings.geminiApiKey),
  };

  for (final entry in pairs.entries) {
    if (entry.value.old == entry.value.cur) continue;
    if (entry.value.cur.isEmpty) {
      await secureStore.deleteKey(entry.key);
    } else {
      await secureStore.writeKey(entry.key, entry.value.cur);
    }
  }
}

typedef _KeyPair = ({String old, String cur});

/// Central settings provider — single source of truth for all app settings.
final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
