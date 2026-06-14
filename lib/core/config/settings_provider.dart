/// App settings provider — persisted via SQLite.
///
/// **Architecture note**: This file lives in `core/config/` because every
/// layer depends on it (theme, l10n, services, features). It imports from
/// `core/data/` (database provider for persistence) and `services/path_service`
/// (cross-platform path helpers). The Go config dependency has been removed;
/// a one-time migration reads the legacy file directly if no Flutter settings
/// exist yet.
///
/// **Section architecture (issue 12)**: [AppSettings] is an aggregate of 16
/// immutable section classes defined in [settings_sections.dart].  Every
/// previous top-level field is preserved as a `@Deprecated` getter that
/// delegates to the appropriate section, so existing call-sites continue to
/// compile without modification.  New code should use the section fields
/// directly (e.g. `settings.stt.model`) and mutate via [copyWithSections].
library;

import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../../services/path_service.dart';
import 'quality_tier.dart' show QualityTier;
import 'secure_key_store.dart';
import 'settings_enums.dart';
import 'whisper_languages.dart';
import 'settings_sections.dart';

/// All persisted app settings in one immutable aggregate.
///
/// Fields are grouped into 16 immutable section objects.  Every legacy
/// top-level field is available as a `@Deprecated` getter for backward
/// compatibility until all call-sites are migrated to the section API.
class AppSettings {
  const AppSettings({
    this.interface_ = const InterfaceSettings(),
    this.audioInput = const AudioInputSettings(),
    this.recordingSafety = const RecordingSafetySettings(),
    this.stt = const SttSettings(),
    this.sound = const SoundSettings(),
    this.afterTranscriptionSection = const AfterTranscriptionSettings(),
    this.overlay = const OverlaySettings(),
    this.cloudProvider = const CloudProviderSettings(),
    this.behavior = const BehaviorSettings(),
    this.audioProcessing = const AudioProcessingSettings(),
    this.updates = const UpdateSettings(),
    this.history = const HistorySettings(),
    this.hotkey = const HotkeySettings(),
    this.windowPosition = const WindowPositionSettings(),
    this.onboarding = const OnboardingSettings(),
    this.benchmark = const BenchmarkSettings(),
  });

  // ---------------------------------------------------------------------------
  // Section fields
  // ---------------------------------------------------------------------------

  /// Interface settings (theme, locale, startup).
  final InterfaceSettings interface_;

  /// Audio input settings (microphone, gain, push-to-talk).
  final AudioInputSettings audioInput;

  /// Recording safety settings (dead-mic timeout, auto-stop silence).
  final RecordingSafetySettings recordingSafety;

  /// Speech-to-text settings (provider, model, language, idle timeout).
  final SttSettings stt;

  /// Sound feedback settings (start/stop sounds, volume).
  final SoundSettings sound;

  /// After-transcription action settings.
  final AfterTranscriptionSettings afterTranscriptionSection;

  /// Overlay & floating button settings.
  final OverlaySettings overlay;

  /// Cloud provider & API key settings.
  final CloudProviderSettings cloudProvider;

  /// General behavior settings (tray, error reporting, GPU, paste).
  final BehaviorSettings behavior;

  /// Audio processing settings (trim silence).
  final AudioProcessingSettings audioProcessing;

  /// Update check settings.
  final UpdateSettings updates;

  /// History retention settings.
  final HistorySettings history;

  /// Hotkey settings.
  final HotkeySettings hotkey;

  /// Window & overlay position settings.
  final WindowPositionSettings windowPosition;

  /// Onboarding completion state.
  final OnboardingSettings onboarding;

  /// Benchmark data for tier performance recommendations.
  final BenchmarkSettings benchmark;

  // ---------------------------------------------------------------------------
  // @Deprecated shims — delegate to sections.
  // Remove once all call-sites migrate to the section API.
  // ---------------------------------------------------------------------------

  @Deprecated('Use interface_.themeMode instead')
  ThemeMode get themeMode => interface_.themeMode;

  @Deprecated('Use interface_.locale instead')
  String get locale => interface_.locale;

  @Deprecated('Use interface_.launchAtStartup instead')
  bool get launchAtStartup => interface_.launchAtStartup;

  @Deprecated('Use interface_.startMinimized instead')
  bool get startMinimized => interface_.startMinimized;

  @Deprecated('Use interface_.showNotifications instead')
  bool get showNotifications => interface_.showNotifications;

  @Deprecated('Use audioInput.microphone instead')
  String get microphone => audioInput.microphone;

  @Deprecated('Use audioInput.pushToTalk instead')
  bool get pushToTalk => audioInput.pushToTalk;

  @Deprecated('Use audioInput.inputGain instead')
  double get inputGain => audioInput.inputGain;

  @Deprecated('Use recordingSafety.deadMicTimeout instead')
  double get deadMicTimeout => recordingSafety.deadMicTimeout;

  @Deprecated('Use recordingSafety.autoStopSilence instead')
  double get autoStopSilence => recordingSafety.autoStopSilence;

  @Deprecated('Use stt.provider instead')
  String get sttProvider => stt.provider;

  @Deprecated('Use stt.model instead')
  String get sttModel => stt.model;

  @Deprecated('Use stt.language instead')
  String get sttLanguage => stt.language;

  @Deprecated('Use stt.idleTimeoutMinutes instead')
  int get sttIdleTimeoutMinutes => stt.idleTimeoutMinutes;

  @Deprecated('Use stt.customVocabulary instead')
  String get customVocabulary => stt.customVocabulary;

  @Deprecated('Use sound.recordStartSound instead')
  bool get recordStartSound => sound.recordStartSound;

  @Deprecated('Use sound.recordStopSound instead')
  bool get recordStopSound => sound.recordStopSound;

  @Deprecated('Use sound.transcriptionCompleteSound instead')
  bool get transcriptionCompleteSound => sound.transcriptionCompleteSound;

  @Deprecated('Use sound.durationWarningSound instead')
  bool get durationWarningSound => sound.durationWarningSound;

  @Deprecated('Use sound.soundVolume instead')
  double get soundVolume => sound.soundVolume;

  @Deprecated('Use afterTranscriptionSection.afterTranscription instead')
  String get afterTranscription => afterTranscriptionSection.afterTranscription;

  @Deprecated('Use overlay.showOverlay instead')
  bool get showOverlay => overlay.showOverlay;

  @Deprecated('Use overlay.overlayMode instead')
  String get overlayMode => overlay.overlayMode;

  @Deprecated('Use overlay.overlayStartPosition instead')
  String get overlayStartPosition => overlay.overlayStartPosition;

  @Deprecated('Use overlay.overlaySize instead')
  String get overlaySize => overlay.overlaySize;

  @Deprecated('Use overlay.showFloatingButton instead')
  bool get showFloatingButton => overlay.showFloatingButton;

  @Deprecated('Use cloudProvider.openAiApiKey instead')
  String get openAiApiKey => cloudProvider.openAiApiKey;

  @Deprecated('Use cloudProvider.deepgramApiKey instead')
  String get deepgramApiKey => cloudProvider.deepgramApiKey;

  @Deprecated('Use cloudProvider.cloudSttProvider instead')
  String get cloudSttProvider => cloudProvider.cloudSttProvider;

  @Deprecated('Use behavior.maxRecordDuration instead')
  int get maxRecordDuration => behavior.maxRecordDuration;

  @Deprecated('Use behavior.closeToTray instead')
  bool get closeToTray => behavior.closeToTray;

  @Deprecated('Use behavior.errorReporting instead')
  bool get errorReporting => behavior.errorReporting;

  @Deprecated('Use behavior.gpuAcceleration instead')
  String get gpuAcceleration => behavior.gpuAcceleration;

  @Deprecated('Use behavior.autoPasteDelay instead')
  int get autoPasteDelay => behavior.autoPasteDelay;

  @Deprecated('Use behavior.autoPasteBlocklist instead')
  String get autoPasteBlocklist => behavior.autoPasteBlocklist;

  @Deprecated('Use audioProcessing.trimSilence instead')
  bool get trimSilence => audioProcessing.trimSilence;

  @Deprecated('Use behavior.textReplacementsEnabled instead')
  bool get textReplacementsEnabled => behavior.textReplacementsEnabled;

  @Deprecated('Use updates.checkUpdates instead')
  bool get checkUpdates => updates.checkUpdates;

  @Deprecated('Use history.historyMaxEntries instead')
  int get historyMaxEntries => history.historyMaxEntries;

  @Deprecated('Use history.historyAutoTrashDays instead')
  int get historyAutoTrashDays => history.historyAutoTrashDays;

  @Deprecated('Use hotkey.hotkeyEnabled instead')
  bool get hotkeyEnabled => hotkey.hotkeyEnabled;

  @Deprecated('Use hotkey.hotkeyKey instead')
  String get hotkeyKey => hotkey.hotkeyKey;

  @Deprecated('Use hotkey.hotkeyModifiers instead')
  String get hotkeyModifiers => hotkey.hotkeyModifiers;

  @Deprecated('Use windowPosition.floatingButtonX instead')
  double get floatingButtonX => windowPosition.floatingButtonX;

  @Deprecated('Use windowPosition.floatingButtonY instead')
  double get floatingButtonY => windowPosition.floatingButtonY;

  @Deprecated('Use windowPosition.floatingOverlayX instead')
  double get floatingOverlayX => windowPosition.floatingOverlayX;

  @Deprecated('Use windowPosition.floatingOverlayY instead')
  double get floatingOverlayY => windowPosition.floatingOverlayY;

  @Deprecated('Use windowPosition.windowX instead')
  double get windowX => windowPosition.windowX;

  @Deprecated('Use windowPosition.windowY instead')
  double get windowY => windowPosition.windowY;

  @Deprecated('Use windowPosition.windowWidth instead')
  double get windowWidth => windowPosition.windowWidth;

  @Deprecated('Use windowPosition.windowHeight instead')
  double get windowHeight => windowPosition.windowHeight;

  @Deprecated('Use windowPosition.windowMaximized instead')
  bool get windowMaximized => windowPosition.windowMaximized;

  @Deprecated('Use onboarding.onboardingCompleted instead')
  bool get onboardingCompleted => onboarding.onboardingCompleted;

  @Deprecated('Use benchmark.tierBenchmarkRtf instead')
  Map<QualityTier, double>? get tierBenchmarkRtf => benchmark.tierBenchmarkRtf;

  @Deprecated('Use benchmark.benchmarkHardwareId instead')
  String? get benchmarkHardwareId => benchmark.benchmarkHardwareId;

  @Deprecated('Use benchmark.benchmarkTimestamp instead')
  DateTime? get benchmarkTimestamp => benchmark.benchmarkTimestamp;

  // ---------------------------------------------------------------------------
  // Typed accessors — prefer these over raw string comparisons.
  // ---------------------------------------------------------------------------

  SttProviderType get sttProviderType =>
      SttProviderType.fromValue(stt.provider);
  CloudSttProvider get cloudSttProviderType =>
      CloudSttProvider.fromValue(cloudProvider.cloudSttProvider);
  AfterTranscriptionAction get afterTranscriptionAction =>
      AfterTranscriptionAction.fromValue(
        afterTranscriptionSection.afterTranscription,
      );
  OverlayMode get overlayModeType => OverlayMode.fromValue(overlay.overlayMode);

  /// Returns the effective overlay mode. Now that the native floating overlay
  /// is implemented, `floating` is passed through directly.
  OverlayMode get effectiveOverlayMode => overlayModeType;

  OverlayStartPosition get overlayStartPositionType =>
      OverlayStartPosition.fromValue(overlay.overlayStartPosition);
  FloatingOverlaySize get overlaySizeType =>
      FloatingOverlaySize.fromValue(overlay.overlaySize);

  /// Resolved model ID — falls back to `whisper-medium` if empty.
  String get effectiveModelId =>
      stt.model.isEmpty ? 'whisper-medium' : stt.model;

  /// STT language code for the whisper server (e.g. `en`, `ru`, `auto`).
  ///
  /// Normalizes the persisted [stt.language] value to the short code
  /// expected by whisper-server's `language` parameter. Accepts both the
  /// legacy display values written by ≤1.2.x ('Auto-detect', 'English', …)
  /// and the short codes written since the 99-language settings dropdown.
  /// Anything outside the [whisperLanguages] catalog degrades to `'auto'`.
  String get sttLanguageCode {
    final value = stt.language;
    if (whisperLanguages.containsKey(value)) return value;
    return switch (value) {
      'English' => 'en',
      'German' => 'de',
      'French' => 'fr',
      'Spanish' => 'es',
      _ => 'auto',
    };
  }

  /// Platform-aware factory-reset defaults.
  ///
  /// On macOS the default hotkey uses ⌘+Shift (meta) instead of Ctrl+Shift.
  static final AppSettings defaults = AppSettings(
    hotkey: buildDefaultHotkeySettings(),
  );

  /// Creates settings from persisted key-value storage.
  factory AppSettings.fromStorageMap(Map<String, String> values) {
    return AppSettings(
      interface_: InterfaceSettings.fromMap(values),
      audioInput: AudioInputSettings.fromMap(values),
      recordingSafety: RecordingSafetySettings.fromMap(values),
      stt: SttSettings.fromMap(values),
      sound: SoundSettings.fromMap(values),
      afterTranscriptionSection: AfterTranscriptionSettings.fromMap(values),
      overlay: OverlaySettings.fromMap(values),
      cloudProvider: CloudProviderSettings.fromMap(values),
      behavior: BehaviorSettings.fromMap(values),
      audioProcessing: AudioProcessingSettings.fromMap(values),
      updates: UpdateSettings.fromMap(values),
      history: HistorySettings.fromMap(values),
      hotkey: HotkeySettings.fromMap(values),
      windowPosition: WindowPositionSettings.fromMap(values),
      onboarding: OnboardingSettings.fromMap(values),
      benchmark: BenchmarkSettings.fromMap(values),
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
    final autoPaste = json['auto_paste'] as bool? ?? true;
    final sounds = json['play_sounds'] as bool? ?? true;
    final maxSec = json['max_record_sec'] as int? ?? 120;

    return AppSettings(
      stt: SttSettings(
        provider: useLocal
            ? SttProviderType.onDevice.value
            : defaults.stt.provider,
        model: _settingModelFromConfig(modelId),
        language: _settingLanguageFromConfig(lang),
      ),
      sound: SoundSettings(
        recordStartSound: sounds,
        recordStopSound: sounds,
        transcriptionCompleteSound: sounds,
        durationWarningSound: sounds,
      ),
      afterTranscriptionSection: AfterTranscriptionSettings(
        afterTranscription: autoPaste ? 'clipboard' : 'nothing',
      ),
      behavior: BehaviorSettings(
        maxRecordDuration: maxSec,
        gpuAcceleration: gpu,
      ),
    );
  }

  /// Serializes settings into a string map for SQLite persistence.
  Map<String, String> toStorageMap() => {
    'schema_version': '2',
    ...interface_.toMap(),
    ...audioInput.toMap(),
    ...recordingSafety.toMap(),
    ...stt.toMap(),
    ...sound.toMap(),
    ...afterTranscriptionSection.toMap(),
    ...overlay.toMap(),
    ...cloudProvider.toMap(),
    ...behavior.toMap(),
    ...audioProcessing.toMap(),
    ...updates.toMap(),
    ...history.toMap(),
    ...hotkey.toMap(),
    ...windowPosition.toMap(),
    ...onboarding.toMap(),
    ...benchmark.toMap(),
  };

  // ---------------------------------------------------------------------------
  // copyWithSections — the new 16-param section-based API.
  // ---------------------------------------------------------------------------

  /// Returns a copy of this [AppSettings] with one or more sections replaced.
  ///
  /// This is the preferred mutation API for new code:
  /// ```dart
  /// final updated = settings.copyWithSections(
  ///   stt: settings.stt.copyWith(model: 'whisper-large-v3-turbo'),
  /// );
  /// ```
  AppSettings copyWithSections({
    InterfaceSettings? interface_,
    AudioInputSettings? audioInput,
    RecordingSafetySettings? recordingSafety,
    SttSettings? stt,
    SoundSettings? sound,
    AfterTranscriptionSettings? afterTranscriptionSection,
    OverlaySettings? overlay,
    CloudProviderSettings? cloudProvider,
    BehaviorSettings? behavior,
    AudioProcessingSettings? audioProcessing,
    UpdateSettings? updates,
    HistorySettings? history,
    HotkeySettings? hotkey,
    WindowPositionSettings? windowPosition,
    OnboardingSettings? onboarding,
    BenchmarkSettings? benchmark,
  }) {
    return AppSettings(
      interface_: interface_ ?? this.interface_,
      audioInput: audioInput ?? this.audioInput,
      recordingSafety: recordingSafety ?? this.recordingSafety,
      stt: stt ?? this.stt,
      sound: sound ?? this.sound,
      afterTranscriptionSection:
          afterTranscriptionSection ?? this.afterTranscriptionSection,
      overlay: overlay ?? this.overlay,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      behavior: behavior ?? this.behavior,
      audioProcessing: audioProcessing ?? this.audioProcessing,
      updates: updates ?? this.updates,
      history: history ?? this.history,
      hotkey: hotkey ?? this.hotkey,
      windowPosition: windowPosition ?? this.windowPosition,
      onboarding: onboarding ?? this.onboarding,
      benchmark: benchmark ?? this.benchmark,
    );
  }

  // ---------------------------------------------------------------------------
  // copyWith — backward-compatible 49-param API.
  // Preserved so existing callers continue to compile without modification.
  // New code should use [copyWithSections] instead.
  // ---------------------------------------------------------------------------

  @Deprecated(
    'Use copyWithSections() for new callers. '
    'Existing call sites (including snapshot tests) will migrate gradually.',
  )
  AppSettings copyWith({
    ThemeMode? themeMode,
    String? locale,
    bool? launchAtStartup,
    bool? startMinimized,
    bool? showNotifications,
    String? microphone,
    bool? pushToTalk,
    double? inputGain,
    double? deadMicTimeout,
    double? autoStopSilence,
    String? sttProvider,
    String? sttModel,
    String? sttLanguage,
    int? sttIdleTimeoutMinutes,
    String? customVocabulary,
    bool? recordStartSound,
    bool? recordStopSound,
    bool? transcriptionCompleteSound,
    bool? durationWarningSound,
    double? soundVolume,
    String? afterTranscription,
    bool? showOverlay,
    String? overlayMode,
    String? overlayStartPosition,
    String? overlaySize,
    bool? showFloatingButton,
    String? openAiApiKey,
    String? deepgramApiKey,
    String? cloudSttProvider,
    int? maxRecordDuration,
    bool? closeToTray,
    bool? errorReporting,
    String? gpuAcceleration,
    int? autoPasteDelay,
    String? autoPasteBlocklist,
    bool? trimSilence,
    bool? textReplacementsEnabled,
    bool? checkUpdates,
    int? historyMaxEntries,
    int? historyAutoTrashDays,
    bool? hotkeyEnabled,
    String? hotkeyKey,
    String? hotkeyKeyDisplay,
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
    bool? autoPasteOffHintDismissed,
    Map<QualityTier, double>? tierBenchmarkRtf,
    String? benchmarkHardwareId,
    DateTime? benchmarkTimestamp,
  }) {
    return AppSettings(
      interface_: interface_.copyWith(
        themeMode: themeMode,
        locale: locale,
        launchAtStartup: launchAtStartup,
        startMinimized: startMinimized,
        showNotifications: showNotifications,
      ),
      audioInput: audioInput.copyWith(
        microphone: microphone,
        pushToTalk: pushToTalk,
        inputGain: inputGain,
      ),
      recordingSafety: recordingSafety.copyWith(
        deadMicTimeout: deadMicTimeout,
        autoStopSilence: autoStopSilence,
      ),
      stt: stt.copyWith(
        provider: sttProvider,
        model: sttModel,
        language: sttLanguage,
        idleTimeoutMinutes: sttIdleTimeoutMinutes,
        customVocabulary: customVocabulary,
      ),
      sound: sound.copyWith(
        recordStartSound: recordStartSound,
        recordStopSound: recordStopSound,
        transcriptionCompleteSound: transcriptionCompleteSound,
        durationWarningSound: durationWarningSound,
        soundVolume: soundVolume,
      ),
      afterTranscriptionSection: afterTranscriptionSection.copyWith(
        afterTranscription: afterTranscription,
      ),
      overlay: overlay.copyWith(
        showOverlay: showOverlay,
        overlayMode: overlayMode,
        overlayStartPosition: overlayStartPosition,
        overlaySize: overlaySize,
        showFloatingButton: showFloatingButton,
      ),
      cloudProvider: cloudProvider.copyWith(
        openAiApiKey: openAiApiKey,
        deepgramApiKey: deepgramApiKey,
        cloudSttProvider: cloudSttProvider,
      ),
      behavior: behavior.copyWith(
        maxRecordDuration: maxRecordDuration,
        closeToTray: closeToTray,
        errorReporting: errorReporting,
        gpuAcceleration: gpuAcceleration,
        autoPasteDelay: autoPasteDelay,
        autoPasteBlocklist: autoPasteBlocklist,
        textReplacementsEnabled: textReplacementsEnabled,
      ),
      audioProcessing: audioProcessing.copyWith(trimSilence: trimSilence),
      updates: updates.copyWith(checkUpdates: checkUpdates),
      history: history.copyWith(
        historyMaxEntries: historyMaxEntries,
        historyAutoTrashDays: historyAutoTrashDays,
      ),
      hotkey: hotkey.copyWith(
        hotkeyEnabled: hotkeyEnabled,
        hotkeyKey: hotkeyKey,
        hotkeyKeyDisplay: hotkeyKeyDisplay,
        hotkeyModifiers: hotkeyModifiers,
      ),
      windowPosition: windowPosition.copyWith(
        floatingButtonX: floatingButtonX,
        floatingButtonY: floatingButtonY,
        floatingOverlayX: floatingOverlayX,
        floatingOverlayY: floatingOverlayY,
        windowX: windowX,
        windowY: windowY,
        windowWidth: windowWidth,
        windowHeight: windowHeight,
        windowMaximized: windowMaximized,
      ),
      onboarding: onboarding.copyWith(
        onboardingCompleted: onboardingCompleted,
        autoPasteOffHintDismissed: autoPasteOffHintDismissed,
      ),
      benchmark: benchmark.copyWith(
        tierBenchmarkRtf: tierBenchmarkRtf,
        benchmarkHardwareId: benchmarkHardwareId,
        benchmarkTimestamp: benchmarkTimestamp,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          interface_ == other.interface_ &&
          audioInput == other.audioInput &&
          recordingSafety == other.recordingSafety &&
          stt == other.stt &&
          sound == other.sound &&
          afterTranscriptionSection == other.afterTranscriptionSection &&
          overlay == other.overlay &&
          cloudProvider == other.cloudProvider &&
          behavior == other.behavior &&
          audioProcessing == other.audioProcessing &&
          updates == other.updates &&
          history == other.history &&
          hotkey == other.hotkey &&
          windowPosition == other.windowPosition &&
          onboarding == other.onboarding &&
          benchmark == other.benchmark;

  @override
  int get hashCode => Object.hash(
    interface_,
    audioInput,
    recordingSafety,
    stt,
    sound,
    afterTranscriptionSection,
    overlay,
    cloudProvider,
    behavior,
    audioProcessing,
    updates,
    history,
    hotkey,
    windowPosition,
    onboarding,
    benchmark,
  );
}

String _settingModelFromConfig(String modelId) {
  // Now settings store actual model IDs directly.
  return modelId.isEmpty ? 'whisper-medium' : modelId;
}

String _settingLanguageFromConfig(String languageCode) {
  return whisperLanguages.containsKey(languageCode) ? languageCode : 'auto';
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
        // Groq removal (v1.2.13): delete any residual wp_groq_api_key from
        // secure storage so no stale credentials remain on device.
        try {
          await secureStore.deleteKey('wp_groq_api_key');
        } catch (_) {
          // Best-effort — keychain may be locked or key absent.
        }
        final merged = await _mergeSecureKeys(
          state.value ?? settings,
          secureStore,
        );
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
    await ref
        .read(historyDatabaseProvider)
        .writeAppSettings(updated.toStorageMap());
  }

  /// Toggle between dark and light theme.
  Future<void> toggleDarkLight() async {
    await updateSettings(
      (s) => s.copyWith(
        themeMode: s.interface_.themeMode == ThemeMode.dark
            ? ThemeMode.light
            : ThemeMode.dark,
      ),
    );
  }

  /// Restore all settings to factory defaults.
  ///
  /// Clears secure-storage API keys, persisted settings (including window
  /// position/size and floating-button position), and daily analytics stats.
  Future<void> resetToDefaults() async {
    // Clear secure storage API keys (best-effort — keychain may be locked).
    try {
      final secureStore = ref.read(secureKeyStoreProvider);
      for (final secureKey in apiKeyMapping.values) {
        await secureStore.deleteKey(secureKey);
      }
    } catch (e) {
      dev.log(
        'resetToDefaults: secure store cleanup failed: $e',
        name: 'Settings',
      );
    }
    final db = ref.read(historyDatabaseProvider);
    await db.resetAppSettings();
    await db.resetDailyStats();
    state = AsyncData(AppSettings.defaults);
  }

  /// Full factory reset — deletes ALL user data, models, and settings.
  ///
  /// The caller MUST stop the STT subprocess before calling this method
  /// (to avoid file-locking on the whisper-server binary).
  ///
  /// Prefer routing user-triggered resets through [FactoryResetCoordinator]
  /// (see `lib/services/factory_reset/factory_reset_coordinator.dart`):
  /// it splits the destructive work into phases the UI can render and
  /// performs the multi-GB directory deletes off-isolate so the app does
  /// not appear frozen (the Idmir-Junio 1★ store cluster). This monolithic
  /// method remains for non-UI callers and tests that want the entire
  /// reset in one shot.
  Future<void> factoryReset() async {
    final db = ref.read(historyDatabaseProvider);

    // 1. Clear ALL secure storage API keys (best-effort).
    await eraseSecureStore();

    // 2. Delete all database content (history, tags, projects, etc.).
    try {
      await db.deleteAllData();
    } catch (e) {
      dev.log('Factory reset: deleteAllData failed: $e', name: 'Settings');
    }

    // 3. Delete downloaded models directory.
    _tryDeleteDir(sttDir());

    // 4. Delete log files.
    final logsDir = p.join(appDataDir(), 'logs');
    _tryDeleteDir(logsDir);

    // 5–9 — small-file cleanup + in-memory state reset. Extracted so that
    // [FactoryResetCoordinator]'s `resetSettings` hook can reuse exactly
    // this tail without duplicating the file list.
    await factoryResetFinalize();
  }

  /// Best-effort secure-store cleanup. Extracted from [factoryReset] so
  /// the [FactoryResetCoordinator]'s `eraseSecureStore` hook can call it
  /// directly.
  Future<void> eraseSecureStore() async {
    try {
      final secureStore = ref.read(secureKeyStoreProvider);
      for (final secureKey in apiKeyMapping.values) {
        await secureStore.deleteKey(secureKey);
      }
    } catch (e) {
      dev.log(
        'Factory reset: secure store cleanup failed: $e',
        name: 'Settings',
      );
    }
  }

  /// Tail of the factory-reset sequence: deletes PID/crash-queue/legacy
  /// files, cleans up temp WAVs, and resets the in-memory settings state
  /// so the next render shows the onboarding overlay.
  ///
  /// Intended to be invoked as the `resetSettings` hook of
  /// [FactoryResetCoordinator] after the large-IO phases (model dir,
  /// logs dir, DB, secure store) have already run.
  Future<void> factoryResetFinalize() async {
    // PID files from subprocess_guard.
    _tryDeleteFile(p.join(appDataDir(), '.whisper-server.pid'));
    _tryDeleteFile(p.join(appDataDir(), '.llama-server.pid'));

    // Crash queue database.
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db'));
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db-wal'));
    _tryDeleteFile(p.join(appDataDir(), 'crash_queue.db-shm'));

    // Legacy Go config.
    _tryDeleteFile(p.join(appDataDir(), 'config.json'));

    // Temp WAV files.
    _cleanupTempWavFiles();

    // Reset in-memory state — triggers onboarding via onboardingCompleted=false.
    state = AsyncData(AppSettings.defaults);

    dev.log('Factory reset complete', name: 'Settings');
  }

  static void _tryDeleteDir(String path) {
    try {
      final dir = Directory(path);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (e) {
      dev.log(
        'Factory reset: failed to delete dir $path: $e',
        name: 'Settings',
      );
    }
  }

  static void _tryDeleteFile(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      dev.log(
        'Factory reset: failed to delete file $path: $e',
        name: 'Settings',
      );
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
      dev.log('Factory reset: failed to clean temp WAVs: $e', name: 'Settings');
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
        dev.log(
          'Go config JSON is not an object, skipping migration',
          name: 'Settings',
        );
        return null;
      }
      dev.log('Migrating Go config.json → Flutter settings', name: 'Settings');
      return AppSettings.fromGoConfig(raw);
    } catch (e) {
      // Catches StateError (missing APPDATA), FormatException (bad JSON),
      // FileSystemException (I/O failure), TypeError (unexpected JSON shape),
      // and anything else.  Migration is best-effort — never crash the app.
      dev.log(
        'Go config migration failed, using defaults: $e',
        name: 'Settings',
      );
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
    'deepgram_api_key': 'wp_deepgram_api_key',
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
    deepgramApiKey: keys['wp_deepgram_api_key'] ?? settings.deepgramApiKey,
  );
}

/// Write changed API keys to secure storage.
Future<void> _syncApiKeysToSecureStorage(
  AppSettings oldSettings,
  AppSettings newSettings,
  SecureKeyStore secureStore,
) async {
  final pairs = <String, _KeyPair>{
    'wp_openai_api_key': (
      old: oldSettings.openAiApiKey,
      cur: newSettings.openAiApiKey,
    ),
    'wp_deepgram_api_key': (
      old: oldSettings.deepgramApiKey,
      cur: newSettings.deepgramApiKey,
    ),
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
final settingsProvider = AsyncNotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
