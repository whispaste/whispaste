/// Immutable section classes that partition [AppSettings] into 16 coherent groups.
///
/// Each section is self-contained: it knows its own defaults, how to read from
/// and write to the shared flat storage map (`Map<String,String>`), and how to
/// copy-with-changes.  Storage keys are identical to the old flat schema so no
/// data migration is required.
///
/// Usage:
/// ```dart
/// // Deep mutation via sections
/// final updated = settings.copyWithSections(
///   stt: settings.stt.copyWith(model: 'whisper-large-v3-turbo'),
/// );
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'quality_tier.dart' show QualityTier;
import 'settings_enums.dart';

// ---------------------------------------------------------------------------
// Private helpers (mirrored from settings_provider to keep the file self-contained)
// ---------------------------------------------------------------------------

bool _readBool(Map<String, String> v, String key, bool fallback) {
  final s = v[key];
  if (s == null) return fallback;
  return s == 'true';
}

double _readDouble(Map<String, String> v, String key, double fallback) =>
    double.tryParse(v[key] ?? '') ?? fallback;

int _readInt(Map<String, String> v, String key, int fallback) =>
    int.tryParse(v[key] ?? '') ?? fallback;

ThemeMode _themeModeFromString(String name) => switch (name) {
  'light' => ThemeMode.light,
  'system' => ThemeMode.system,
  _ => ThemeMode.dark,
};

Map<QualityTier, double>? _readBenchmarkRtf(String? value) {
  if (value == null || value.isEmpty) return null;
  try {
    final json = jsonDecode(value) as Map<String, dynamic>;
    final result = <QualityTier, double>{};
    for (final entry in json.entries) {
      final tier = QualityTier.values.firstWhere(
        (t) => t.name == entry.key,
        orElse: () => throw FormatException('Unknown tier: ${entry.key}'),
      );
      result[tier] = (entry.value as num).toDouble();
    }
    return result;
  } catch (_) {
    return null;
  }
}

String _writeBenchmarkRtf(Map<QualityTier, double>? rtfMap) {
  if (rtfMap == null || rtfMap.isEmpty) return '';
  final json = <String, double>{};
  for (final entry in rtfMap.entries) {
    json[entry.key.name] = entry.value;
  }
  return jsonEncode(json);
}

DateTime? _readDateTime(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Migrates legacy model identifiers to the current downloadable set
/// (`whisper-small`, `whisper-medium`, `whisper-large-v3-turbo`).
///
/// Covers both old display-name values (`'Fast (Tiny)'` etc.) and removed
/// model IDs (`whisper-tiny`, `whisper-base`, `whisper-large-v3`). Each
/// legacy value maps to the tier representative — see [sttModels].
String _migrateModelId(String raw) => switch (raw) {
  'Fast (Tiny)' || 'whisper-tiny' || 'whisper-base' => 'whisper-small',
  'Balanced (Small)' => 'whisper-small',
  'High Quality (Medium)' => 'whisper-medium',
  'Best Quality (Large)' || 'whisper-large-v3' => 'whisper-large-v3-turbo',
  _ => raw,
};

// ===========================================================================
// Section 1 — Interface
// ===========================================================================

class InterfaceSettings {
  const InterfaceSettings({
    this.themeMode = ThemeMode.dark,
    this.locale = 'en',
    this.launchAtStartup = false,
    this.startMinimized = false,
    this.showNotifications = true,
  });

  final ThemeMode themeMode;
  final String locale;
  final bool launchAtStartup;
  final bool startMinimized;
  final bool showNotifications;

  static const InterfaceSettings defaults = InterfaceSettings();

  factory InterfaceSettings.fromMap(Map<String, String> v) => InterfaceSettings(
    themeMode: _themeModeFromString(v['theme_mode'] ?? 'dark'),
    locale: v['locale'] ?? defaults.locale,
    launchAtStartup: _readBool(
      v,
      'launch_at_startup',
      defaults.launchAtStartup,
    ),
    startMinimized: _readBool(v, 'start_minimized', defaults.startMinimized),
    showNotifications: _readBool(
      v,
      'show_notifications',
      defaults.showNotifications,
    ),
  );

  Map<String, String> toMap() => {
    'theme_mode': themeMode.name,
    'locale': locale,
    'launch_at_startup': '$launchAtStartup',
    'start_minimized': '$startMinimized',
    'show_notifications': '$showNotifications',
  };

  InterfaceSettings copyWith({
    ThemeMode? themeMode,
    String? locale,
    bool? launchAtStartup,
    bool? startMinimized,
    bool? showNotifications,
  }) => InterfaceSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    launchAtStartup: launchAtStartup ?? this.launchAtStartup,
    startMinimized: startMinimized ?? this.startMinimized,
    showNotifications: showNotifications ?? this.showNotifications,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterfaceSettings &&
          themeMode == other.themeMode &&
          locale == other.locale &&
          launchAtStartup == other.launchAtStartup &&
          startMinimized == other.startMinimized &&
          showNotifications == other.showNotifications;

  @override
  int get hashCode => Object.hash(
    themeMode,
    locale,
    launchAtStartup,
    startMinimized,
    showNotifications,
  );
}

// ===========================================================================
// Section 2 — Audio Input
// ===========================================================================

class AudioInputSettings {
  const AudioInputSettings({
    this.microphone = 'Default',
    this.pushToTalk = false,
    this.inputGain = 1.0,
  });

  final String microphone;
  final bool pushToTalk;

  /// User-controlled gain multiplier applied to the raw PCM stream during
  /// recording. `1.0` is identity (no scaling). The settings UI exposes this
  /// as a 0–300 % slider (0.0–3.0). When non-default, the recording pipeline
  /// switches off the `record`-plugin's library-side `autoGain` and applies
  /// the user multiplier instead via `PcmGainProcessor`.
  final double inputGain;

  static const AudioInputSettings defaults = AudioInputSettings();

  factory AudioInputSettings.fromMap(Map<String, String> v) =>
      AudioInputSettings(
        microphone: v['microphone'] ?? defaults.microphone,
        pushToTalk: _readBool(v, 'push_to_talk', defaults.pushToTalk),
        inputGain: _readDouble(v, 'input_gain', defaults.inputGain),
      );

  Map<String, String> toMap() => {
    'microphone': microphone,
    'push_to_talk': '$pushToTalk',
    'input_gain': '$inputGain',
  };

  AudioInputSettings copyWith({
    String? microphone,
    bool? pushToTalk,
    double? inputGain,
  }) => AudioInputSettings(
    microphone: microphone ?? this.microphone,
    pushToTalk: pushToTalk ?? this.pushToTalk,
    inputGain: inputGain ?? this.inputGain,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioInputSettings &&
          microphone == other.microphone &&
          pushToTalk == other.pushToTalk &&
          inputGain == other.inputGain;

  @override
  int get hashCode => Object.hash(microphone, pushToTalk, inputGain);
}

// ===========================================================================
// Section 3 — Recording Safety
// ===========================================================================

class RecordingSafetySettings {
  const RecordingSafetySettings({
    this.deadMicTimeout = 3.0,
    this.autoStopSilence = 0.0,
  });

  final double deadMicTimeout;
  final double autoStopSilence;

  static const RecordingSafetySettings defaults = RecordingSafetySettings();

  factory RecordingSafetySettings.fromMap(Map<String, String> v) =>
      RecordingSafetySettings(
        deadMicTimeout: _readDouble(
          v,
          'dead_mic_timeout',
          defaults.deadMicTimeout,
        ),
        autoStopSilence: _readDouble(
          v,
          'auto_stop_silence',
          defaults.autoStopSilence,
        ),
      );

  Map<String, String> toMap() => {
    'dead_mic_timeout': '$deadMicTimeout',
    'auto_stop_silence': '$autoStopSilence',
  };

  RecordingSafetySettings copyWith({
    double? deadMicTimeout,
    double? autoStopSilence,
  }) => RecordingSafetySettings(
    deadMicTimeout: deadMicTimeout ?? this.deadMicTimeout,
    autoStopSilence: autoStopSilence ?? this.autoStopSilence,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingSafetySettings &&
          deadMicTimeout == other.deadMicTimeout &&
          autoStopSilence == other.autoStopSilence;

  @override
  int get hashCode => Object.hash(deadMicTimeout, autoStopSilence);
}

// ===========================================================================
// Section 4 — STT
// ===========================================================================

class SttSettings {
  const SttSettings({
    this.provider = 'On Device',
    this.model = 'whisper-medium',
    this.language = 'Auto-detect',
    this.idleTimeoutMinutes = 5,
    this.customVocabulary = '',
  });

  final String provider;
  final String model;
  final String language;

  /// Minutes before idle STT server is shut down (0 = keep alive).
  final int idleTimeoutMinutes;

  /// User-defined vocabulary terms (names, jargon) passed as Whisper prompt
  /// prefix to improve recognition of domain-specific words.
  final String customVocabulary;

  static const SttSettings defaults = SttSettings();

  factory SttSettings.fromMap(Map<String, String> v) => SttSettings(
    provider: v['stt_provider'] ?? defaults.provider,
    model: _migrateModelId(v['stt_model'] ?? defaults.model),
    language: v['stt_language'] ?? defaults.language,
    idleTimeoutMinutes: _readInt(
      v,
      'stt_idle_timeout_minutes',
      defaults.idleTimeoutMinutes,
    ),
    customVocabulary: v['custom_vocabulary'] ?? defaults.customVocabulary,
  );

  Map<String, String> toMap() => {
    'stt_provider': provider,
    'stt_model': model,
    'stt_language': language,
    'stt_idle_timeout_minutes': '$idleTimeoutMinutes',
    'custom_vocabulary': customVocabulary,
  };

  SttSettings copyWith({
    String? provider,
    String? model,
    String? language,
    int? idleTimeoutMinutes,
    String? customVocabulary,
  }) => SttSettings(
    provider: provider ?? this.provider,
    model: model ?? this.model,
    language: language ?? this.language,
    idleTimeoutMinutes: idleTimeoutMinutes ?? this.idleTimeoutMinutes,
    customVocabulary: customVocabulary ?? this.customVocabulary,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SttSettings &&
          provider == other.provider &&
          model == other.model &&
          language == other.language &&
          idleTimeoutMinutes == other.idleTimeoutMinutes &&
          customVocabulary == other.customVocabulary;

  @override
  int get hashCode => Object.hash(
    provider,
    model,
    language,
    idleTimeoutMinutes,
    customVocabulary,
  );
}

// ===========================================================================
// Section 5 — Sound
// ===========================================================================

class SoundSettings {
  const SoundSettings({
    this.recordStartSound = true,
    this.recordStopSound = true,
    this.transcriptionCompleteSound = true,
    this.durationWarningSound = true,
    this.soundVolume = 80.0,
  });

  final bool recordStartSound;
  final bool recordStopSound;
  final bool transcriptionCompleteSound;
  final bool durationWarningSound;
  final double soundVolume;

  static const SoundSettings defaults = SoundSettings();

  factory SoundSettings.fromMap(Map<String, String> v) => SoundSettings(
    recordStartSound: _readBool(
      v,
      'record_start_sound',
      defaults.recordStartSound,
    ),
    recordStopSound: _readBool(
      v,
      'record_stop_sound',
      defaults.recordStopSound,
    ),
    transcriptionCompleteSound: _readBool(
      v,
      'transcription_complete_sound',
      defaults.transcriptionCompleteSound,
    ),
    durationWarningSound: _readBool(
      v,
      'duration_warning_sound',
      defaults.durationWarningSound,
    ),
    soundVolume: _readDouble(v, 'sound_volume', defaults.soundVolume),
  );

  Map<String, String> toMap() => {
    'record_start_sound': '$recordStartSound',
    'record_stop_sound': '$recordStopSound',
    'transcription_complete_sound': '$transcriptionCompleteSound',
    'duration_warning_sound': '$durationWarningSound',
    'sound_volume': '$soundVolume',
  };

  SoundSettings copyWith({
    bool? recordStartSound,
    bool? recordStopSound,
    bool? transcriptionCompleteSound,
    bool? durationWarningSound,
    double? soundVolume,
  }) => SoundSettings(
    recordStartSound: recordStartSound ?? this.recordStartSound,
    recordStopSound: recordStopSound ?? this.recordStopSound,
    transcriptionCompleteSound:
        transcriptionCompleteSound ?? this.transcriptionCompleteSound,
    durationWarningSound: durationWarningSound ?? this.durationWarningSound,
    soundVolume: soundVolume ?? this.soundVolume,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoundSettings &&
          recordStartSound == other.recordStartSound &&
          recordStopSound == other.recordStopSound &&
          transcriptionCompleteSound == other.transcriptionCompleteSound &&
          durationWarningSound == other.durationWarningSound &&
          soundVolume == other.soundVolume;

  @override
  int get hashCode => Object.hash(
    recordStartSound,
    recordStopSound,
    transcriptionCompleteSound,
    durationWarningSound,
    soundVolume,
  );
}

// ===========================================================================
// Section 6 — After Transcription
// ===========================================================================

class AfterTranscriptionSettings {
  const AfterTranscriptionSettings({this.afterTranscription = 'clipboard'});

  /// What happens after transcription: 'clipboard', 'paste',
  /// 'clipboard_and_paste', or 'nothing'
  final String afterTranscription;

  static const AfterTranscriptionSettings defaults =
      AfterTranscriptionSettings();

  factory AfterTranscriptionSettings.fromMap(Map<String, String> v) =>
      AfterTranscriptionSettings(
        afterTranscription:
            v['after_transcription'] ?? defaults.afterTranscription,
      );

  Map<String, String> toMap() => {'after_transcription': afterTranscription};

  AfterTranscriptionSettings copyWith({String? afterTranscription}) =>
      AfterTranscriptionSettings(
        afterTranscription: afterTranscription ?? this.afterTranscription,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AfterTranscriptionSettings &&
          afterTranscription == other.afterTranscription;

  @override
  int get hashCode => afterTranscription.hashCode;
}

// ===========================================================================
// Section 7 — Overlay
// ===========================================================================

class OverlaySettings {
  const OverlaySettings({
    this.showOverlay = false,
    this.overlayMode = 'floating',
    this.overlayStartPosition = 'top-center',
    this.overlaySize = 'normal',
    this.showFloatingButton = false,
  });

  final bool showOverlay;

  /// 'floating' or 'off'.
  final String overlayMode;

  /// 'top-center', 'bottom-center', or 'last-position'.
  final String overlayStartPosition;

  /// 'normal' or 'compact'.
  final String overlaySize;

  final bool showFloatingButton;

  static const OverlaySettings defaults = OverlaySettings();

  factory OverlaySettings.fromMap(Map<String, String> v) => OverlaySettings(
    showOverlay: _readBool(v, 'show_overlay', defaults.showOverlay),
    overlayMode:
        v['overlay_mode'] ??
        (_readBool(v, 'show_overlay', defaults.showOverlay)
            ? defaults.overlayMode
            : OverlayMode.off.value),
    overlayStartPosition:
        v['overlay_start_position'] ?? defaults.overlayStartPosition,
    overlaySize: v['overlay_size'] ?? defaults.overlaySize,
    showFloatingButton: _readBool(
      v,
      'show_floating_button',
      defaults.showFloatingButton,
    ),
    // 'floating_button_size' is intentionally not read — removed in issue 11.
    // Old configs may have it; the key is silently ignored (no migration needed).
  );

  Map<String, String> toMap() => {
    'show_overlay': '$showOverlay',
    'overlay_mode': overlayMode,
    'overlay_start_position': overlayStartPosition,
    'overlay_size': overlaySize,
    'show_floating_button': '$showFloatingButton',
  };

  OverlaySettings copyWith({
    bool? showOverlay,
    String? overlayMode,
    String? overlayStartPosition,
    String? overlaySize,
    bool? showFloatingButton,
  }) => OverlaySettings(
    showOverlay: showOverlay ?? this.showOverlay,
    overlayMode: overlayMode ?? this.overlayMode,
    overlayStartPosition: overlayStartPosition ?? this.overlayStartPosition,
    overlaySize: overlaySize ?? this.overlaySize,
    showFloatingButton: showFloatingButton ?? this.showFloatingButton,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlaySettings &&
          showOverlay == other.showOverlay &&
          overlayMode == other.overlayMode &&
          overlayStartPosition == other.overlayStartPosition &&
          overlaySize == other.overlaySize &&
          showFloatingButton == other.showFloatingButton;

  @override
  int get hashCode => Object.hash(
    showOverlay,
    overlayMode,
    overlayStartPosition,
    overlaySize,
    showFloatingButton,
  );
}

// ===========================================================================
// Section 8 — Cloud Provider
// ===========================================================================

class CloudProviderSettings {
  const CloudProviderSettings({
    this.openAiApiKey = '',
    this.deepgramApiKey = '',
    this.cloudSttProvider = 'openai',
  });

  // API keys are stored in secure storage — never persisted to SQLite.
  final String openAiApiKey;
  final String deepgramApiKey;
  final String cloudSttProvider;

  static const CloudProviderSettings defaults = CloudProviderSettings();

  factory CloudProviderSettings.fromMap(Map<String, String> v) =>
      CloudProviderSettings(
        openAiApiKey: v['openai_api_key'] ?? defaults.openAiApiKey,
        deepgramApiKey: v['deepgram_api_key'] ?? defaults.deepgramApiKey,
        cloudSttProvider: v['cloud_stt_provider'] ?? defaults.cloudSttProvider,
      );

  Map<String, String> toMap() => {
    // API keys are stored in secure storage — always write empty string.
    'openai_api_key': '',
    'deepgram_api_key': '',
    'cloud_stt_provider': cloudSttProvider,
  };

  CloudProviderSettings copyWith({
    String? openAiApiKey,
    String? deepgramApiKey,
    String? cloudSttProvider,
  }) => CloudProviderSettings(
    openAiApiKey: openAiApiKey ?? this.openAiApiKey,
    deepgramApiKey: deepgramApiKey ?? this.deepgramApiKey,
    cloudSttProvider: cloudSttProvider ?? this.cloudSttProvider,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudProviderSettings &&
          openAiApiKey == other.openAiApiKey &&
          deepgramApiKey == other.deepgramApiKey &&
          cloudSttProvider == other.cloudSttProvider;

  @override
  int get hashCode =>
      Object.hash(openAiApiKey, deepgramApiKey, cloudSttProvider);
}

// ===========================================================================
// Section 9 — Behavior
// ===========================================================================

class BehaviorSettings {
  const BehaviorSettings({
    this.maxRecordDuration = 120,
    this.closeToTray = true,
    this.errorReporting = true,
    this.gpuAcceleration = 'auto',
    this.autoPasteDelay = 200,
    this.autoPasteBlocklist = '',
    this.textReplacementsEnabled = false,
  });

  final int maxRecordDuration;
  final bool closeToTray;
  final bool errorReporting;
  final String gpuAcceleration;
  final int autoPasteDelay;

  /// Comma-separated list of app bundle IDs (macOS) or process names (Windows)
  /// where auto-paste should be suppressed.
  final String autoPasteBlocklist;

  final bool textReplacementsEnabled;

  static const BehaviorSettings defaults = BehaviorSettings();

  factory BehaviorSettings.fromMap(Map<String, String> v) => BehaviorSettings(
    maxRecordDuration: _readInt(
      v,
      'max_record_duration',
      defaults.maxRecordDuration,
    ),
    closeToTray: _readBool(v, 'close_to_tray', defaults.closeToTray),
    errorReporting: _readBool(v, 'error_reporting', defaults.errorReporting),
    gpuAcceleration: v['gpu_acceleration'] ?? defaults.gpuAcceleration,
    autoPasteDelay: _readInt(v, 'auto_paste_delay', defaults.autoPasteDelay),
    autoPasteBlocklist:
        v['auto_paste_blocklist'] ?? defaults.autoPasteBlocklist,
    textReplacementsEnabled: _readBool(
      v,
      'text_replacements_enabled',
      defaults.textReplacementsEnabled,
    ),
  );

  Map<String, String> toMap() => {
    'max_record_duration': '$maxRecordDuration',
    'close_to_tray': '$closeToTray',
    'error_reporting': '$errorReporting',
    'gpu_acceleration': gpuAcceleration,
    'auto_paste_delay': '$autoPasteDelay',
    'auto_paste_blocklist': autoPasteBlocklist,
    'text_replacements_enabled': '$textReplacementsEnabled',
  };

  BehaviorSettings copyWith({
    int? maxRecordDuration,
    bool? closeToTray,
    bool? errorReporting,
    String? gpuAcceleration,
    int? autoPasteDelay,
    String? autoPasteBlocklist,
    bool? textReplacementsEnabled,
  }) => BehaviorSettings(
    maxRecordDuration: maxRecordDuration ?? this.maxRecordDuration,
    closeToTray: closeToTray ?? this.closeToTray,
    errorReporting: errorReporting ?? this.errorReporting,
    gpuAcceleration: gpuAcceleration ?? this.gpuAcceleration,
    autoPasteDelay: autoPasteDelay ?? this.autoPasteDelay,
    autoPasteBlocklist: autoPasteBlocklist ?? this.autoPasteBlocklist,
    textReplacementsEnabled:
        textReplacementsEnabled ?? this.textReplacementsEnabled,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BehaviorSettings) return false;
    return maxRecordDuration == other.maxRecordDuration &&
        closeToTray == other.closeToTray &&
        errorReporting == other.errorReporting &&
        gpuAcceleration == other.gpuAcceleration &&
        autoPasteDelay == other.autoPasteDelay &&
        autoPasteBlocklist == other.autoPasteBlocklist &&
        textReplacementsEnabled == other.textReplacementsEnabled;
  }

  @override
  int get hashCode => Object.hash(
    maxRecordDuration,
    closeToTray,
    errorReporting,
    gpuAcceleration,
    autoPasteDelay,
    autoPasteBlocklist,
    textReplacementsEnabled,
  );
}

// ===========================================================================
// Section 10 — Audio Processing
// ===========================================================================

class AudioProcessingSettings {
  const AudioProcessingSettings();

  factory AudioProcessingSettings.fromMap(Map<String, String> _) =>
      const AudioProcessingSettings();

  Map<String, String> toMap() => const <String, String>{};

  AudioProcessingSettings copyWith() => const AudioProcessingSettings();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AudioProcessingSettings;

  @override
  int get hashCode => 0;
}

// ===========================================================================
// Section 11 — Updates
// ===========================================================================

class UpdateSettings {
  const UpdateSettings({this.checkUpdates = true});

  final bool checkUpdates;

  static const UpdateSettings defaults = UpdateSettings();

  factory UpdateSettings.fromMap(Map<String, String> v) => UpdateSettings(
    checkUpdates: _readBool(v, 'check_updates', defaults.checkUpdates),
  );

  Map<String, String> toMap() => {'check_updates': '$checkUpdates'};

  UpdateSettings copyWith({bool? checkUpdates}) =>
      UpdateSettings(checkUpdates: checkUpdates ?? this.checkUpdates);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateSettings && checkUpdates == other.checkUpdates;

  @override
  int get hashCode => checkUpdates.hashCode;
}

// ===========================================================================
// Section 12 — History
// ===========================================================================

class HistorySettings {
  const HistorySettings({
    this.historyMaxEntries = 1000,
    this.historyAutoTrashDays = 90,
  });

  /// Max active (non-trashed) history entries to keep. 0 = unlimited.
  final int historyMaxEntries;

  /// Days to keep soft-deleted entries before permanent purge. 0 = never purge.
  final int historyAutoTrashDays;

  static const HistorySettings defaults = HistorySettings();

  factory HistorySettings.fromMap(Map<String, String> v) => HistorySettings(
    historyMaxEntries: _readInt(
      v,
      'history_max_entries',
      defaults.historyMaxEntries,
    ),
    historyAutoTrashDays: _readInt(
      v,
      'history_auto_trash_days',
      defaults.historyAutoTrashDays,
    ),
  );

  Map<String, String> toMap() => {
    'history_max_entries': '$historyMaxEntries',
    'history_auto_trash_days': '$historyAutoTrashDays',
  };

  HistorySettings copyWith({
    int? historyMaxEntries,
    int? historyAutoTrashDays,
  }) => HistorySettings(
    historyMaxEntries: historyMaxEntries ?? this.historyMaxEntries,
    historyAutoTrashDays: historyAutoTrashDays ?? this.historyAutoTrashDays,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HistorySettings &&
          historyMaxEntries == other.historyMaxEntries &&
          historyAutoTrashDays == other.historyAutoTrashDays;

  @override
  int get hashCode => Object.hash(historyMaxEntries, historyAutoTrashDays);
}

// ===========================================================================
// Section 13 — Hotkey
// ===========================================================================

class HotkeySettings {
  const HotkeySettings({
    this.hotkeyEnabled = true,
    this.hotkeyKey = 'D',
    this.hotkeyKeyDisplay = '',
    this.hotkeyModifiers = 'ctrl+shift',
  });

  final bool hotkeyEnabled;

  /// Canonical storage token for the non-modifier key — what `resolveKey`
  /// consumes (e.g. `'D'`, `'F1'`, `';'`).
  final String hotkeyKey;

  /// User-visible label for [hotkeyKey] as captured by the recorder. When
  /// empty, UI formatters fall back to [hotkeyKey]. Lets a DE-layout user
  /// who pressed `Ö` (physical position `semicolon`) see `Ö` in settings and
  /// status bar while the registrar still binds to the stable physical
  /// position via `hotkeyKey=';'`.
  final String hotkeyKeyDisplay;

  final String hotkeyModifiers;

  static const HotkeySettings defaults = HotkeySettings();

  factory HotkeySettings.fromMap(Map<String, String> v) => HotkeySettings(
    hotkeyEnabled: _readBool(v, 'hotkey_enabled', defaults.hotkeyEnabled),
    hotkeyKey: v['hotkey_key'] ?? defaults.hotkeyKey,
    hotkeyKeyDisplay: v['hotkey_key_display'] ?? defaults.hotkeyKeyDisplay,
    hotkeyModifiers: v['hotkey_modifiers'] ?? defaults.hotkeyModifiers,
  );

  Map<String, String> toMap() => {
    'hotkey_enabled': '$hotkeyEnabled',
    'hotkey_key': hotkeyKey,
    'hotkey_key_display': hotkeyKeyDisplay,
    'hotkey_modifiers': hotkeyModifiers,
  };

  HotkeySettings copyWith({
    bool? hotkeyEnabled,
    String? hotkeyKey,
    String? hotkeyKeyDisplay,
    String? hotkeyModifiers,
  }) => HotkeySettings(
    hotkeyEnabled: hotkeyEnabled ?? this.hotkeyEnabled,
    hotkeyKey: hotkeyKey ?? this.hotkeyKey,
    hotkeyKeyDisplay: hotkeyKeyDisplay ?? this.hotkeyKeyDisplay,
    hotkeyModifiers: hotkeyModifiers ?? this.hotkeyModifiers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotkeySettings &&
          hotkeyEnabled == other.hotkeyEnabled &&
          hotkeyKey == other.hotkeyKey &&
          hotkeyKeyDisplay == other.hotkeyKeyDisplay &&
          hotkeyModifiers == other.hotkeyModifiers;

  @override
  int get hashCode =>
      Object.hash(hotkeyEnabled, hotkeyKey, hotkeyKeyDisplay, hotkeyModifiers);
}

// ===========================================================================
// Section 14 — Window Positions
// ===========================================================================

class WindowPositionSettings {
  const WindowPositionSettings({
    this.floatingButtonX = -1.0,
    this.floatingButtonY = -1.0,
    this.floatingOverlayX = -1.0,
    this.floatingOverlayY = -1.0,
    this.windowX = -1.0,
    this.windowY = -1.0,
    this.windowWidth = 1100.0,
    this.windowHeight = 750.0,
    this.windowMaximized = false,
  });

  final double floatingButtonX;
  final double floatingButtonY;
  final double floatingOverlayX;
  final double floatingOverlayY;
  final double windowX;
  final double windowY;
  final double windowWidth;
  final double windowHeight;
  final bool windowMaximized;

  static const WindowPositionSettings defaults = WindowPositionSettings();

  factory WindowPositionSettings.fromMap(Map<String, String> v) =>
      WindowPositionSettings(
        floatingButtonX: _readDouble(
          v,
          'floating_button_x',
          defaults.floatingButtonX,
        ),
        floatingButtonY: _readDouble(
          v,
          'floating_button_y',
          defaults.floatingButtonY,
        ),
        floatingOverlayX: _readDouble(
          v,
          'floating_overlay_x',
          defaults.floatingOverlayX,
        ),
        floatingOverlayY: _readDouble(
          v,
          'floating_overlay_y',
          defaults.floatingOverlayY,
        ),
        windowX: _readDouble(v, 'window_x', defaults.windowX),
        windowY: _readDouble(v, 'window_y', defaults.windowY),
        windowWidth: _readDouble(v, 'window_width', defaults.windowWidth),
        windowHeight: _readDouble(v, 'window_height', defaults.windowHeight),
        windowMaximized: _readBool(
          v,
          'window_maximized',
          defaults.windowMaximized,
        ),
      );

  Map<String, String> toMap() => {
    'floating_button_x': '$floatingButtonX',
    'floating_button_y': '$floatingButtonY',
    'floating_overlay_x': '$floatingOverlayX',
    'floating_overlay_y': '$floatingOverlayY',
    'window_x': '$windowX',
    'window_y': '$windowY',
    'window_width': '$windowWidth',
    'window_height': '$windowHeight',
    'window_maximized': '$windowMaximized',
  };

  WindowPositionSettings copyWith({
    double? floatingButtonX,
    double? floatingButtonY,
    double? floatingOverlayX,
    double? floatingOverlayY,
    double? windowX,
    double? windowY,
    double? windowWidth,
    double? windowHeight,
    bool? windowMaximized,
  }) => WindowPositionSettings(
    floatingButtonX: floatingButtonX ?? this.floatingButtonX,
    floatingButtonY: floatingButtonY ?? this.floatingButtonY,
    floatingOverlayX: floatingOverlayX ?? this.floatingOverlayX,
    floatingOverlayY: floatingOverlayY ?? this.floatingOverlayY,
    windowX: windowX ?? this.windowX,
    windowY: windowY ?? this.windowY,
    windowWidth: windowWidth ?? this.windowWidth,
    windowHeight: windowHeight ?? this.windowHeight,
    windowMaximized: windowMaximized ?? this.windowMaximized,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WindowPositionSettings &&
          floatingButtonX == other.floatingButtonX &&
          floatingButtonY == other.floatingButtonY &&
          floatingOverlayX == other.floatingOverlayX &&
          floatingOverlayY == other.floatingOverlayY &&
          windowX == other.windowX &&
          windowY == other.windowY &&
          windowWidth == other.windowWidth &&
          windowHeight == other.windowHeight &&
          windowMaximized == other.windowMaximized;

  @override
  int get hashCode => Object.hash(
    floatingButtonX,
    floatingButtonY,
    floatingOverlayX,
    floatingOverlayY,
    windowX,
    windowY,
    windowWidth,
    windowHeight,
    windowMaximized,
  );
}

// ===========================================================================
// Section 15 — Onboarding
// ===========================================================================

class OnboardingSettings {
  const OnboardingSettings({
    this.onboardingCompleted = false,
    this.autoPasteOffHintDismissed = false,
  });

  final bool onboardingCompleted;

  /// Persistent dismiss of the "Auto-Paste deaktiviert" status-bar hint that
  /// appears after the user skips Auto-Paste during onboarding. When `true`,
  /// the chip is hidden permanently — even while Auto-Paste remains off.
  /// Re-enabling Auto-Paste in Settings makes the chip irrelevant regardless.
  final bool autoPasteOffHintDismissed;

  static const OnboardingSettings defaults = OnboardingSettings();

  factory OnboardingSettings.fromMap(Map<String, String> v) =>
      OnboardingSettings(
        onboardingCompleted: _readBool(
          v,
          'onboarding_completed',
          defaults.onboardingCompleted,
        ),
        autoPasteOffHintDismissed: _readBool(
          v,
          'auto_paste_off_hint_dismissed',
          defaults.autoPasteOffHintDismissed,
        ),
      );

  Map<String, String> toMap() => {
    'onboarding_completed': '$onboardingCompleted',
    'auto_paste_off_hint_dismissed': '$autoPasteOffHintDismissed',
  };

  OnboardingSettings copyWith({
    bool? onboardingCompleted,
    bool? autoPasteOffHintDismissed,
  }) => OnboardingSettings(
    onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
    autoPasteOffHintDismissed:
        autoPasteOffHintDismissed ?? this.autoPasteOffHintDismissed,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnboardingSettings &&
          onboardingCompleted == other.onboardingCompleted &&
          autoPasteOffHintDismissed == other.autoPasteOffHintDismissed;

  @override
  int get hashCode =>
      Object.hash(onboardingCompleted, autoPasteOffHintDismissed);
}

// ===========================================================================
// Section 16 — Benchmark
// ===========================================================================

class BenchmarkSettings {
  const BenchmarkSettings({
    this.tierBenchmarkRtf,
    this.benchmarkHardwareId,
    this.benchmarkTimestamp,
  });

  /// Real-time factor (RTF) for each quality tier from last benchmark.
  /// RTF = processing_time / audio_duration. Lower is better.
  final Map<QualityTier, double>? tierBenchmarkRtf;

  /// Hardware ID (hash) that the benchmark was run on.
  final String? benchmarkHardwareId;

  /// When the benchmark was last run.
  final DateTime? benchmarkTimestamp;

  factory BenchmarkSettings.fromMap(Map<String, String> v) => BenchmarkSettings(
    tierBenchmarkRtf: _readBenchmarkRtf(v['tier_benchmark_rtf']),
    benchmarkHardwareId: v['benchmark_hardware_id'],
    benchmarkTimestamp: _readDateTime(v['benchmark_timestamp']),
  );

  Map<String, String> toMap() => {
    'tier_benchmark_rtf': _writeBenchmarkRtf(tierBenchmarkRtf),
    'benchmark_hardware_id': benchmarkHardwareId ?? '',
    'benchmark_timestamp': benchmarkTimestamp?.toIso8601String() ?? '',
  };

  BenchmarkSettings copyWith({
    Map<QualityTier, double>? tierBenchmarkRtf,
    String? benchmarkHardwareId,
    DateTime? benchmarkTimestamp,
  }) => BenchmarkSettings(
    tierBenchmarkRtf: tierBenchmarkRtf ?? this.tierBenchmarkRtf,
    benchmarkHardwareId: benchmarkHardwareId ?? this.benchmarkHardwareId,
    benchmarkTimestamp: benchmarkTimestamp ?? this.benchmarkTimestamp,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BenchmarkSettings &&
          tierBenchmarkRtf == other.tierBenchmarkRtf &&
          benchmarkHardwareId == other.benchmarkHardwareId &&
          benchmarkTimestamp == other.benchmarkTimestamp;

  @override
  int get hashCode =>
      Object.hash(tierBenchmarkRtf, benchmarkHardwareId, benchmarkTimestamp);
}

// ===========================================================================
// Section 17 — Privacy
// ===========================================================================

class PrivacySettings {
  // Opt-out by design (PRD Säule D): anonymous, cookieless, self-hosted usage
  // stats default ON, with DSGVO Art. 6 (1) (f) as the legal basis. Consistent
  // with the default-on Sentry crash reporter; a discrete Datenschutz toggle
  // lets users opt out.
  const PrivacySettings({this.shareUsageStats = true});

  final bool shareUsageStats;

  static const PrivacySettings defaults = PrivacySettings();

  factory PrivacySettings.fromMap(Map<String, String> v) => PrivacySettings(
    shareUsageStats: _readBool(
      v,
      'share_usage_stats',
      defaults.shareUsageStats,
    ),
  );

  Map<String, String> toMap() => {'share_usage_stats': '$shareUsageStats'};

  PrivacySettings copyWith({bool? shareUsageStats}) =>
      PrivacySettings(shareUsageStats: shareUsageStats ?? this.shareUsageStats);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacySettings && shareUsageStats == other.shareUsageStats;

  @override
  int get hashCode => shareUsageStats.hashCode;
}

// ===========================================================================
// Platform-aware defaults factory
// ===========================================================================

/// Build a [HotkeySettings] with the platform-correct default modifier.
HotkeySettings buildDefaultHotkeySettings() => HotkeySettings(
  hotkeyModifiers: Platform.isMacOS ? 'meta+shift' : 'ctrl+shift',
);
