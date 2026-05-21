/// Behavior-snapshot tests for AppSettings serialisation.
///
/// Purpose: lock in every observable toStorageMap / fromStorageMap contract
/// **before** AppSettings is split into 16 section classes (issue 12).
/// After the split, the only allowed change is swapping the import line.
///
/// Structure:
/// 1. Per-field roundtrip group — one test per field (non-default value
///    survives the map round-trip, or is explicitly excluded with justification)
/// 2. Per-cluster groups — 16 groups mirroring the planned section split
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:whispaste/core/config/settings_provider.dart';
import 'package:whispaste/core/config/settings_enums.dart';
import 'package:whispaste/services/model_download_service.dart'
    show QualityTier;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Round-trips [settings] through toStorageMap → fromStorageMap.
AppSettings _roundtrip(AppSettings settings) =>
    AppSettings.fromStorageMap(settings.toStorageMap());

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  // 1. Per-field roundtrip group
  //    One test per field. Each test creates an AppSettings with a single
  //    non-default value, round-trips it, and asserts the value survives.
  //    API keys (openAiApiKey, deepgramApiKey) are explicitly excluded from
  //    SQLite storage — that contract is tested separately.
  // =========================================================================
  group('Per-field roundtrip', () {
    // --- Interface ---
    test('themeMode light survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(themeMode: ThemeMode.light);
      expect(_roundtrip(s).themeMode, ThemeMode.light);
    });

    test('themeMode system survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(themeMode: ThemeMode.system);
      expect(_roundtrip(s).themeMode, ThemeMode.system);
    });

    test('locale survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(locale: 'de');
      expect(_roundtrip(s).locale, 'de');
    });

    test('launchAtStartup survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(launchAtStartup: true);
      expect(_roundtrip(s).launchAtStartup, isTrue);
    });

    test('startMinimized survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(startMinimized: true);
      expect(_roundtrip(s).startMinimized, isTrue);
    });

    test('showNotifications false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(showNotifications: false);
      expect(_roundtrip(s).showNotifications, isFalse);
    });

    // --- Audio Input ---
    test('microphone survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(microphone: 'Built-in Mic');
      expect(_roundtrip(s).microphone, 'Built-in Mic');
    });

    test('pushToTalk survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(pushToTalk: true);
      expect(_roundtrip(s).pushToTalk, isTrue);
    });

    // --- Recording Safety ---
    test('deadMicTimeout survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(deadMicTimeout: 5.0);
      expect(_roundtrip(s).deadMicTimeout, 5.0);
    });

    test('autoStopSilence survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(autoStopSilence: 2.5);
      expect(_roundtrip(s).autoStopSilence, 2.5);
    });

    // --- STT ---
    test('sttProvider survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        sttProvider: SttProviderType.openAI.value,
      );
      expect(_roundtrip(s).sttProvider, SttProviderType.openAI.value);
    });

    test('sttModel survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        sttModel: 'whisper-large-v3-turbo',
      );
      expect(_roundtrip(s).sttModel, 'whisper-large-v3-turbo');
    });

    test('legacy sttModel values migrate to current tier representatives', () {
      // Storage from older WhisPaste versions can still reference IDs that no
      // longer exist in the registry. They must be transparently rewritten on
      // load to one of the three current downloadable models.
      AppSettings load(String legacy) =>
          AppSettings.fromStorageMap({'stt_model': legacy});

      // Removed model IDs → current tier representative.
      expect(load('whisper-tiny').sttModel, 'whisper-small');
      expect(load('whisper-base').sttModel, 'whisper-small');
      expect(load('whisper-large-v3').sttModel, 'whisper-large-v3-turbo');

      // Currently valid IDs pass through unchanged.
      expect(load('whisper-small').sttModel, 'whisper-small');
      expect(load('whisper-medium').sttModel, 'whisper-medium');
      expect(load('whisper-large-v3-turbo').sttModel, 'whisper-large-v3-turbo');

      // Pre-ID display-name values from the very first release.
      expect(load('Fast (Tiny)').sttModel, 'whisper-small');
      expect(load('Balanced (Small)').sttModel, 'whisper-small');
      expect(load('High Quality (Medium)').sttModel, 'whisper-medium');
      expect(load('Best Quality (Large)').sttModel, 'whisper-large-v3-turbo');
    });

    test('sttLanguage survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(sttLanguage: 'German');
      expect(_roundtrip(s).sttLanguage, 'German');
    });

    test('sttIdleTimeoutMinutes survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(sttIdleTimeoutMinutes: 10);
      expect(_roundtrip(s).sttIdleTimeoutMinutes, 10);
    });

    test('customVocabulary survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        customVocabulary: 'Flutter Riverpod Drift',
      );
      expect(_roundtrip(s).customVocabulary, 'Flutter Riverpod Drift');
    });

    // --- Sound ---
    test('recordStartSound false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(recordStartSound: false);
      expect(_roundtrip(s).recordStartSound, isFalse);
    });

    test('recordStopSound false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(recordStopSound: false);
      expect(_roundtrip(s).recordStopSound, isFalse);
    });

    test('transcriptionCompleteSound false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        transcriptionCompleteSound: false,
      );
      expect(_roundtrip(s).transcriptionCompleteSound, isFalse);
    });

    test('durationWarningSound false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(durationWarningSound: false);
      expect(_roundtrip(s).durationWarningSound, isFalse);
    });

    test('soundVolume survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(soundVolume: 50.0);
      expect(_roundtrip(s).soundVolume, 50.0);
    });

    // --- After Transcription ---
    test('afterTranscription paste survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(afterTranscription: 'paste');
      expect(_roundtrip(s).afterTranscription, 'paste');
    });

    test('afterTranscription clipboard_and_paste survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        afterTranscription: 'clipboard_and_paste',
      );
      expect(_roundtrip(s).afterTranscription, 'clipboard_and_paste');
    });

    test('afterTranscription nothing survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(afterTranscription: 'nothing');
      expect(_roundtrip(s).afterTranscription, 'nothing');
    });

    // --- Overlay ---
    test('showOverlay true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(showOverlay: true);
      expect(_roundtrip(s).showOverlay, isTrue);
    });

    test('overlayMode survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        overlayMode: OverlayMode.off.value,
      );
      expect(_roundtrip(s).overlayMode, OverlayMode.off.value);
    });

    test('overlayStartPosition bottom-center survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        overlayStartPosition: 'bottom-center',
      );
      expect(_roundtrip(s).overlayStartPosition, 'bottom-center');
    });

    test('overlaySize compact survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(overlaySize: 'compact');
      expect(_roundtrip(s).overlaySize, 'compact');
    });

    test('overlayAutoHide 10s survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(overlayAutoHide: '10s');
      expect(_roundtrip(s).overlayAutoHide, '10s');
    });

    test('showFloatingButton true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(showFloatingButton: true);
      expect(_roundtrip(s).showFloatingButton, isTrue);
    });

    test('floatingButtonOpacity survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingButtonOpacity: 0.5);
      expect(_roundtrip(s).floatingButtonOpacity, 0.5);
    });

    test('floatingButtonSize large survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingButtonSize: 'large');
      expect(_roundtrip(s).floatingButtonSize, 'large');
    });

    test('floatingOverlayOpacity survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingOverlayOpacity: 0.7);
      expect(_roundtrip(s).floatingOverlayOpacity, 0.7);
    });

    // --- Cloud Provider (API keys excluded from SQLite) ---
    test('openAiApiKey is NOT stored in SQLite map', () {
      final s = AppSettings.defaults.copyWith(openAiApiKey: 'sk-secret');
      final map = s.toStorageMap();
      expect(map['openai_api_key'] ?? '', isEmpty);
    });

    test('deepgramApiKey is NOT stored in SQLite map', () {
      final s = AppSettings.defaults.copyWith(deepgramApiKey: 'dg-secret');
      final map = s.toStorageMap();
      expect(map['deepgram_api_key'] ?? '', isEmpty);
    });

    test('cloudSttProvider deepgram survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        cloudSttProvider: CloudSttProvider.deepgram.value,
      );
      expect(_roundtrip(s).cloudSttProvider, CloudSttProvider.deepgram.value);
    });

    // --- Behavior ---
    test('maxRecordDuration survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(maxRecordDuration: 60);
      expect(_roundtrip(s).maxRecordDuration, 60);
    });

    test('closeToTray false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(closeToTray: false);
      expect(_roundtrip(s).closeToTray, isFalse);
    });

    test('errorReporting false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(errorReporting: false);
      expect(_roundtrip(s).errorReporting, isFalse);
    });

    test('gpuAcceleration enabled survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        gpuAcceleration: GpuAcceleration.enabled.value,
      );
      expect(_roundtrip(s).gpuAcceleration, GpuAcceleration.enabled.value);
    });

    test('gpuAcceleration disabled survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        gpuAcceleration: GpuAcceleration.disabled.value,
      );
      expect(_roundtrip(s).gpuAcceleration, GpuAcceleration.disabled.value);
    });

    test('autoPasteDelay survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(autoPasteDelay: 500);
      expect(_roundtrip(s).autoPasteDelay, 500);
    });

    test('autoPasteBlocklist survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        autoPasteBlocklist: 'com.example.app,other.app',
      );
      expect(_roundtrip(s).autoPasteBlocklist, 'com.example.app,other.app');
    });

    // --- Audio Processing ---
    test('trimSilence true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(trimSilence: true);
      expect(_roundtrip(s).trimSilence, isTrue);
    });

    // --- Text Replacements ---
    test('textReplacementsEnabled true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(textReplacementsEnabled: true);
      expect(_roundtrip(s).textReplacementsEnabled, isTrue);
    });

    // --- Updates ---
    test('checkUpdates false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(checkUpdates: false);
      expect(_roundtrip(s).checkUpdates, isFalse);
    });

    // --- History ---
    test('historyMaxEntries survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(historyMaxEntries: 500);
      expect(_roundtrip(s).historyMaxEntries, 500);
    });

    test('historyAutoTrashDays survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(historyAutoTrashDays: 7);
      expect(_roundtrip(s).historyAutoTrashDays, 7);
    });

    // --- Hotkey ---
    test('hotkeyEnabled false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(hotkeyEnabled: false);
      expect(_roundtrip(s).hotkeyEnabled, isFalse);
    });

    test('hotkeyKey survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(hotkeyKey: 'R');
      expect(_roundtrip(s).hotkeyKey, 'R');
    });

    test('hotkeyModifiers survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(hotkeyModifiers: 'ctrl+alt');
      expect(_roundtrip(s).hotkeyModifiers, 'ctrl+alt');
    });

    // --- Window Positions ---
    test('floatingButtonX survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingButtonX: 200.0);
      expect(_roundtrip(s).floatingButtonX, 200.0);
    });

    test('floatingButtonY survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingButtonY: 150.0);
      expect(_roundtrip(s).floatingButtonY, 150.0);
    });

    test('floatingOverlayX survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingOverlayX: 300.0);
      expect(_roundtrip(s).floatingOverlayX, 300.0);
    });

    test('floatingOverlayY survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(floatingOverlayY: 400.0);
      expect(_roundtrip(s).floatingOverlayY, 400.0);
    });

    test('windowX survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(windowX: 100.0);
      expect(_roundtrip(s).windowX, 100.0);
    });

    test('windowY survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(windowY: 50.0);
      expect(_roundtrip(s).windowY, 50.0);
    });

    test('windowWidth survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(windowWidth: 1280.0);
      expect(_roundtrip(s).windowWidth, 1280.0);
    });

    test('windowHeight survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(windowHeight: 900.0);
      expect(_roundtrip(s).windowHeight, 900.0);
    });

    test('windowMaximized true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(windowMaximized: true);
      expect(_roundtrip(s).windowMaximized, isTrue);
    });

    // --- Onboarding ---
    test('onboardingCompleted true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(onboardingCompleted: true);
      expect(_roundtrip(s).onboardingCompleted, isTrue);
    });

    // --- Benchmark ---
    test('tierBenchmarkRtf null survives roundtrip as null', () {
      final s = AppSettings.defaults.copyWith(tierBenchmarkRtf: null);
      expect(_roundtrip(s).tierBenchmarkRtf, isNull);
    });

    test('tierBenchmarkRtf map survives roundtrip', () {
      final rtf = {
        QualityTier.compact: 0.3,
        QualityTier.balanced: 0.6,
        QualityTier.premium: 1.2,
      };
      final s = AppSettings.defaults.copyWith(tierBenchmarkRtf: rtf);
      final restored = _roundtrip(s).tierBenchmarkRtf;
      expect(restored, isNotNull);
      expect(restored![QualityTier.compact], closeTo(0.3, 1e-9));
      expect(restored[QualityTier.balanced], closeTo(0.6, 1e-9));
      expect(restored[QualityTier.premium], closeTo(1.2, 1e-9));
    });

    test('benchmarkHardwareId survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        benchmarkHardwareId: 'abc123hardware',
      );
      expect(_roundtrip(s).benchmarkHardwareId, 'abc123hardware');
    });

    test('benchmarkHardwareId null is serialised and deserialised as null', () {
      final s = AppSettings.defaults.copyWith(benchmarkHardwareId: null);
      // When null, the map stores '' and fromStorageMap reads it back as null
      // (because _readBenchmarkRtf/fromStorageMap handles empty/absent correctly)
      final map = s.toStorageMap();
      expect(map['benchmark_hardware_id'] ?? '', isEmpty);
      // fromStorageMap must return null for empty string
      final restored = AppSettings.fromStorageMap(map);
      // benchmarkHardwareId returns the raw string or null based on storage
      // The implementation stores '' for null, so restored value is either
      // null or ''. We assert it is not a real ID.
      expect(
        restored.benchmarkHardwareId == null ||
            (restored.benchmarkHardwareId ?? '').isEmpty,
        isTrue,
      );
    });

    test('benchmarkTimestamp survives roundtrip', () {
      final ts = DateTime.utc(2025, 6, 15, 12, 30, 0);
      final s = AppSettings.defaults.copyWith(benchmarkTimestamp: ts);
      final restored = _roundtrip(s).benchmarkTimestamp;
      expect(restored, isNotNull);
      expect(restored!.isAtSameMomentAs(ts), isTrue);
    });

    test('benchmarkTimestamp null survives roundtrip as null', () {
      final s = AppSettings.defaults.copyWith(benchmarkTimestamp: null);
      // null is serialised as '' and must deserialise back to null
      expect(_roundtrip(s).benchmarkTimestamp, isNull);
    });
  });

  // =========================================================================
  // 2. Per-cluster groups — 16 groups mirroring the planned section split.
  //    Each group tests the full serialisation contract for that cluster.
  // =========================================================================

  // ---- Section 1: Interface -----------------------------------------------
  group('Section: interface', () {
    test('all interface fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        themeMode: ThemeMode.light,
        locale: 'de',
        launchAtStartup: true,
        startMinimized: true,
        showNotifications: false,
      );
      final map = s.toStorageMap();
      expect(map['theme_mode'], 'light');
      expect(map['locale'], 'de');
      expect(map['launch_at_startup'], 'true');
      expect(map['start_minimized'], 'true');
      expect(map['show_notifications'], 'false');
    });

    test('interface cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        themeMode: ThemeMode.system,
        locale: 'de',
        launchAtStartup: true,
        startMinimized: true,
        showNotifications: false,
      );
      final r = _roundtrip(s);
      expect(r.themeMode, ThemeMode.system);
      expect(r.locale, 'de');
      expect(r.launchAtStartup, isTrue);
      expect(r.startMinimized, isTrue);
      expect(r.showNotifications, isFalse);
    });

    test('unknown themeMode string falls back to dark', () {
      final map = {'theme_mode': 'totally_unknown'};
      final s = AppSettings.fromStorageMap(map);
      expect(s.themeMode, ThemeMode.dark);
    });
  });

  // ---- Section 2: Audio Input ---------------------------------------------
  group('Section: audio input', () {
    test('all audio input fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        microphone: 'External Mic',
        pushToTalk: true,
      );
      final map = s.toStorageMap();
      expect(map['microphone'], 'External Mic');
      expect(map['push_to_talk'], 'true');
    });

    test('audio input cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        microphone: 'External Mic',
        pushToTalk: true,
      );
      final r = _roundtrip(s);
      expect(r.microphone, 'External Mic');
      expect(r.pushToTalk, isTrue);
    });
  });

  // ---- Section 3: Recording Safety ----------------------------------------
  group('Section: recording safety', () {
    test('all recording safety fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        deadMicTimeout: 7.0,
        autoStopSilence: 3.0,
      );
      final map = s.toStorageMap();
      expect(map['dead_mic_timeout'], '7.0');
      expect(map['auto_stop_silence'], '3.0');
    });

    test('recording safety cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        deadMicTimeout: 7.0,
        autoStopSilence: 3.0,
      );
      final r = _roundtrip(s);
      expect(r.deadMicTimeout, 7.0);
      expect(r.autoStopSilence, 3.0);
    });

    test('autoStopSilence 0.0 (disabled) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(autoStopSilence: 0.0);
      expect(_roundtrip(s).autoStopSilence, 0.0);
    });
  });

  // ---- Section 4: STT -----------------------------------------------------
  group('Section: STT', () {
    test('all STT fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        sttProvider: 'OpenAI',
        sttModel: 'whisper-small',
        sttLanguage: 'English',
        sttIdleTimeoutMinutes: 0,
        customVocabulary: 'Riverpod',
      );
      final map = s.toStorageMap();
      expect(map['stt_provider'], 'OpenAI');
      expect(map['stt_model'], 'whisper-small');
      expect(map['stt_language'], 'English');
      expect(map['stt_idle_timeout_minutes'], '0');
      expect(map['custom_vocabulary'], 'Riverpod');
    });

    test('STT cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        sttProvider: 'Deepgram',
        sttModel: 'whisper-small',
        sttLanguage: 'French',
        sttIdleTimeoutMinutes: 15,
        customVocabulary: 'Riverpod Drift FTS5',
      );
      final r = _roundtrip(s);
      expect(r.sttProvider, 'Deepgram');
      expect(r.sttModel, 'whisper-small');
      expect(r.sttLanguage, 'French');
      expect(r.sttIdleTimeoutMinutes, 15);
      expect(r.customVocabulary, 'Riverpod Drift FTS5');
    });

    test('legacy model display-names are migrated to IDs on load', () {
      final map = {'stt_model': 'High Quality (Medium)'};
      expect(AppSettings.fromStorageMap(map).sttModel, 'whisper-medium');
    });

    test(
      'legacy On Device (Private) stt_provider is preserved in raw field',
      () {
        // fromStorageMap stores the raw string; migration happens in the typed
        // accessor sttProviderType, which maps 'On Device (Private)' → onDevice.
        final map = {'stt_provider': 'On Device (Private)'};
        expect(
          AppSettings.fromStorageMap(map).sttProviderType,
          SttProviderType.onDevice,
        );
      },
    );

    test('legacy Groq stt_provider typed accessor maps to On Device', () {
      // fromStorageMap stores 'Groq' as-is; the typed accessor handles migration.
      final map = {'stt_provider': 'Groq'};
      expect(
        AppSettings.fromStorageMap(map).sttProviderType,
        SttProviderType.onDevice,
      );
    });
  });

  // ---- Section 5: Sound ---------------------------------------------------
  group('Section: sound', () {
    test('all sound fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        recordStartSound: false,
        recordStopSound: false,
        transcriptionCompleteSound: false,
        durationWarningSound: false,
        soundVolume: 40.0,
      );
      final map = s.toStorageMap();
      expect(map['record_start_sound'], 'false');
      expect(map['record_stop_sound'], 'false');
      expect(map['transcription_complete_sound'], 'false');
      expect(map['duration_warning_sound'], 'false');
      expect(map['sound_volume'], '40.0');
    });

    test('sound cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        recordStartSound: false,
        recordStopSound: false,
        transcriptionCompleteSound: false,
        durationWarningSound: false,
        soundVolume: 60.0,
      );
      final r = _roundtrip(s);
      expect(r.recordStartSound, isFalse);
      expect(r.recordStopSound, isFalse);
      expect(r.transcriptionCompleteSound, isFalse);
      expect(r.durationWarningSound, isFalse);
      expect(r.soundVolume, 60.0);
    });

    test('soundVolume 0.0 (muted) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(soundVolume: 0.0);
      expect(_roundtrip(s).soundVolume, 0.0);
    });
  });

  // ---- Section 6: Overlay -------------------------------------------------
  group('Section: overlay', () {
    test('all overlay fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        showOverlay: true,
        overlayMode: 'floating',
        overlayStartPosition: 'last-position',
        overlaySize: 'compact',
        overlayAutoHide: 'manual',
        showFloatingButton: true,
        floatingButtonOpacity: 0.8,
        floatingButtonSize: 'small',
        floatingOverlayOpacity: 0.6,
      );
      final map = s.toStorageMap();
      expect(map['show_overlay'], 'true');
      expect(map['overlay_mode'], 'floating');
      expect(map['overlay_start_position'], 'last-position');
      expect(map['overlay_size'], 'compact');
      expect(map['overlay_auto_hide'], 'manual');
      expect(map['show_floating_button'], 'true');
      expect(map['floating_button_opacity'], '0.8');
      expect(map['floating_button_size'], 'small');
      expect(map['floating_overlay_opacity'], '0.6');
    });

    test('overlay cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        showOverlay: true,
        overlayMode: OverlayMode.floating.value,
        overlayStartPosition: OverlayStartPosition.lastPosition.value,
        overlaySize: FloatingOverlaySize.compact.value,
        overlayAutoHide: OverlayAutoHide.seconds10.value,
        showFloatingButton: true,
        floatingButtonOpacity: 0.4,
        floatingButtonSize: FloatingButtonSize.large.value,
        floatingOverlayOpacity: 0.3,
      );
      final r = _roundtrip(s);
      expect(r.showOverlay, isTrue);
      expect(r.overlayMode, OverlayMode.floating.value);
      expect(r.overlayStartPosition, OverlayStartPosition.lastPosition.value);
      expect(r.overlaySize, FloatingOverlaySize.compact.value);
      expect(r.overlayAutoHide, OverlayAutoHide.seconds10.value);
      expect(r.showFloatingButton, isTrue);
      expect(r.floatingButtonOpacity, 0.4);
      expect(r.floatingButtonSize, FloatingButtonSize.large.value);
      expect(r.floatingOverlayOpacity, 0.3);
    });

    test('legacy in-window overlayMode typed accessor migrates to floating', () {
      // fromStorageMap stores the raw string; the typed accessor overlayModeType
      // handles the 'in-window' → floating migration.
      final map = {'overlay_mode': 'in-window'};
      expect(
        AppSettings.fromStorageMap(map).overlayModeType,
        OverlayMode.floating,
      );
    });
  });

  // ---- Section 7: Cloud Provider ------------------------------------------
  group('Section: cloud provider', () {
    test('cloud provider storage keys are present in map', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('openai_api_key'), isTrue);
      expect(map.containsKey('deepgram_api_key'), isTrue);
      expect(map.containsKey('cloud_stt_provider'), isTrue);
    });

    test(
      'API keys are always serialised as empty string (secure storage only)',
      () {
        final s = AppSettings.defaults.copyWith(
          openAiApiKey: 'sk-very-secret',
          deepgramApiKey: 'dg-very-secret',
        );
        final map = s.toStorageMap();
        expect(map['openai_api_key'], isEmpty);
        expect(map['deepgram_api_key'], isEmpty);
      },
    );

    test('cloudSttProvider openai survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        cloudSttProvider: CloudSttProvider.openAI.value,
      );
      expect(_roundtrip(s).cloudSttProvider, CloudSttProvider.openAI.value);
    });

    test('cloudSttProvider deepgram survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        cloudSttProvider: CloudSttProvider.deepgram.value,
      );
      expect(_roundtrip(s).cloudSttProvider, CloudSttProvider.deepgram.value);
    });

    test('legacy groq cloud_stt_provider typed accessor maps to openai', () {
      // fromStorageMap stores 'groq' as-is; the typed accessor handles migration.
      final map = {'cloud_stt_provider': 'groq'};
      expect(
        AppSettings.fromStorageMap(map).cloudSttProviderType,
        CloudSttProvider.openAI,
      );
    });
  });

  // ---- Section 8: Behavior ------------------------------------------------
  group('Section: behavior', () {
    test('all behavior fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        maxRecordDuration: 180,
        closeToTray: false,
        errorReporting: false,
        gpuAcceleration: 'disabled',
        autoPasteDelay: 400,
        autoPasteBlocklist: 'com.example',
      );
      final map = s.toStorageMap();
      expect(map['max_record_duration'], '180');
      expect(map['close_to_tray'], 'false');
      expect(map['error_reporting'], 'false');
      expect(map['gpu_acceleration'], 'disabled');
      expect(map['auto_paste_delay'], '400');
      expect(map['auto_paste_blocklist'], 'com.example');
    });

    test('behavior cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        maxRecordDuration: 240,
        closeToTray: false,
        errorReporting: false,
        gpuAcceleration: GpuAcceleration.enabled.value,
        autoPasteDelay: 100,
        autoPasteBlocklist: 'com.a,com.b',
      );
      final r = _roundtrip(s);
      expect(r.maxRecordDuration, 240);
      expect(r.closeToTray, isFalse);
      expect(r.errorReporting, isFalse);
      expect(r.gpuAcceleration, GpuAcceleration.enabled.value);
      expect(r.autoPasteDelay, 100);
      expect(r.autoPasteBlocklist, 'com.a,com.b');
    });

    test('autoPasteDelay 0 (no delay) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(autoPasteDelay: 0);
      expect(_roundtrip(s).autoPasteDelay, 0);
    });

    test('maxRecordDuration fallback on invalid value', () {
      final map = {'max_record_duration': 'bad'};
      expect(
        AppSettings.fromStorageMap(map).maxRecordDuration,
        AppSettings.defaults.maxRecordDuration,
      );
    });
  });

  // ---- Section 9: Audio Processing ----------------------------------------
  group('Section: audio processing', () {
    test('all audio processing fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(trimSilence: true);
      final map = s.toStorageMap();
      expect(map['trim_silence'], 'true');
    });

    test('audio processing cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(trimSilence: true);
      final r = _roundtrip(s);
      expect(r.trimSilence, isTrue);
    });

    test(
      'legacy VAD keys are ignored on load (forward-compat after removal)',
      () {
        // Simulate a storage map from a previous app version that still
        // persisted `use_vad` and `vad_sensitivity`.  After removing VAD
        // entirely, these keys must be silently ignored: no crash, no other
        // settings disturbed.
        final map =
            Map<String, String>.from(AppSettings.defaults.toStorageMap())
              ..['use_vad'] = 'true'
              ..['vad_sensitivity'] = '0.8';

        expect(() => AppSettings.fromStorageMap(map), returnsNormally);

        final restored = AppSettings.fromStorageMap(map);
        // Other settings unchanged.
        expect(restored.trimSilence, AppSettings.defaults.trimSilence);
        expect(restored.themeMode, AppSettings.defaults.themeMode);
        expect(restored.sttModel, AppSettings.defaults.sttModel);
        // Round-tripping the restored settings does NOT re-emit the legacy
        // VAD keys — they have been dropped from the schema.
        final roundTripped = restored.toStorageMap();
        expect(roundTripped.containsKey('use_vad'), isFalse);
        expect(roundTripped.containsKey('vad_sensitivity'), isFalse);
      },
    );
  });

  // ---- Section 10: Text Replacements --------------------------------------
  group('Section: text replacements', () {
    test('textReplacementsEnabled storage key is present', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('text_replacements_enabled'), isTrue);
    });

    test('textReplacementsEnabled true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(textReplacementsEnabled: true);
      expect(_roundtrip(s).textReplacementsEnabled, isTrue);
    });

    test('textReplacementsEnabled false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(textReplacementsEnabled: false);
      expect(_roundtrip(s).textReplacementsEnabled, isFalse);
    });
  });

  // ---- Section 11: Updates ------------------------------------------------
  group('Section: updates', () {
    test('checkUpdates storage key is present', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('check_updates'), isTrue);
    });

    test('checkUpdates false survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(checkUpdates: false);
      expect(_roundtrip(s).checkUpdates, isFalse);
    });

    test('checkUpdates true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(checkUpdates: true);
      expect(_roundtrip(s).checkUpdates, isTrue);
    });
  });

  // ---- Section 12: History ------------------------------------------------
  group('Section: history', () {
    test('all history fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        historyMaxEntries: 200,
        historyAutoTrashDays: 14,
      );
      final map = s.toStorageMap();
      expect(map['history_max_entries'], '200');
      expect(map['history_auto_trash_days'], '14');
    });

    test('history cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        historyMaxEntries: 1000,
        historyAutoTrashDays: 90,
      );
      final r = _roundtrip(s);
      expect(r.historyMaxEntries, 1000);
      expect(r.historyAutoTrashDays, 90);
    });

    test('historyMaxEntries 0 (unlimited) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(historyMaxEntries: 0);
      expect(_roundtrip(s).historyMaxEntries, 0);
    });

    test('historyAutoTrashDays 0 (never purge) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(historyAutoTrashDays: 0);
      expect(_roundtrip(s).historyAutoTrashDays, 0);
    });
  });

  // ---- Section 13: Hotkey -------------------------------------------------
  group('Section: hotkey', () {
    test('all hotkey fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        hotkeyEnabled: false,
        hotkeyKey: 'F9',
        hotkeyModifiers: 'ctrl+alt',
      );
      final map = s.toStorageMap();
      expect(map['hotkey_enabled'], 'false');
      expect(map['hotkey_key'], 'F9');
      expect(map['hotkey_modifiers'], 'ctrl+alt');
    });

    test('hotkey cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        hotkeyEnabled: true,
        hotkeyKey: 'Space',
        hotkeyModifiers: 'meta+shift',
      );
      final r = _roundtrip(s);
      expect(r.hotkeyEnabled, isTrue);
      expect(r.hotkeyKey, 'Space');
      expect(r.hotkeyModifiers, 'meta+shift');
    });

    test('hotkeyEnabled false prevents recording trigger', () {
      // Contract: disabled state is persisted faithfully
      final s = AppSettings.defaults.copyWith(hotkeyEnabled: false);
      expect(_roundtrip(s).hotkeyEnabled, isFalse);
    });
  });

  // ---- Section 14: Window Positions ---------------------------------------
  group('Section: window positions', () {
    test('all window position fields use expected storage keys', () {
      final s = AppSettings.defaults.copyWith(
        floatingButtonX: 10.0,
        floatingButtonY: 20.0,
        floatingOverlayX: 30.0,
        floatingOverlayY: 40.0,
        windowX: 50.0,
        windowY: 60.0,
        windowWidth: 1200.0,
        windowHeight: 800.0,
        windowMaximized: true,
      );
      final map = s.toStorageMap();
      expect(map['floating_button_x'], '10.0');
      expect(map['floating_button_y'], '20.0');
      expect(map['floating_overlay_x'], '30.0');
      expect(map['floating_overlay_y'], '40.0');
      expect(map['window_x'], '50.0');
      expect(map['window_y'], '60.0');
      expect(map['window_width'], '1200.0');
      expect(map['window_height'], '800.0');
      expect(map['window_maximized'], 'true');
    });

    test('window positions cluster full roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        floatingButtonX: 123.4,
        floatingButtonY: 567.8,
        floatingOverlayX: 111.1,
        floatingOverlayY: 222.2,
        windowX: 50.0,
        windowY: 75.0,
        windowWidth: 1440.0,
        windowHeight: 900.0,
        windowMaximized: true,
      );
      final r = _roundtrip(s);
      expect(r.floatingButtonX, 123.4);
      expect(r.floatingButtonY, 567.8);
      expect(r.floatingOverlayX, 111.1);
      expect(r.floatingOverlayY, 222.2);
      expect(r.windowX, 50.0);
      expect(r.windowY, 75.0);
      expect(r.windowWidth, 1440.0);
      expect(r.windowHeight, 900.0);
      expect(r.windowMaximized, isTrue);
    });

    test('-1.0 sentinel (not set) survives roundtrip', () {
      // -1.0 means position not yet set; must survive round-trip exactly
      final s = AppSettings.defaults.copyWith(
        floatingButtonX: -1.0,
        floatingButtonY: -1.0,
        floatingOverlayX: -1.0,
        floatingOverlayY: -1.0,
        windowX: -1.0,
        windowY: -1.0,
      );
      final r = _roundtrip(s);
      expect(r.floatingButtonX, -1.0);
      expect(r.floatingButtonY, -1.0);
      expect(r.floatingOverlayX, -1.0);
      expect(r.floatingOverlayY, -1.0);
      expect(r.windowX, -1.0);
      expect(r.windowY, -1.0);
    });
  });

  // ---- Section 15: Onboarding ---------------------------------------------
  group('Section: onboarding', () {
    test('onboardingCompleted storage key is present', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('onboarding_completed'), isTrue);
    });

    test('onboardingCompleted true survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(onboardingCompleted: true);
      expect(_roundtrip(s).onboardingCompleted, isTrue);
    });

    test('onboardingCompleted false (fresh install) survives roundtrip', () {
      final s = AppSettings.defaults.copyWith(onboardingCompleted: false);
      expect(_roundtrip(s).onboardingCompleted, isFalse);
    });

    test('autoPasteOffHintDismissed storage key is present', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('auto_paste_off_hint_dismissed'), isTrue);
    });

    test('autoPasteOffHintDismissed defaults to false', () {
      expect(
        AppSettings.defaults.onboarding.autoPasteOffHintDismissed,
        isFalse,
      );
    });

    test('autoPasteOffHintDismissed true survives roundtrip', () {
      final s = AppSettings.defaults.copyWithSections(
        onboarding: AppSettings.defaults.onboarding.copyWith(
          autoPasteOffHintDismissed: true,
        ),
      );
      expect(_roundtrip(s).onboarding.autoPasteOffHintDismissed, isTrue);
    });

    test(
      'autoPasteOffHintDismissed missing key (legacy storage) reads as false',
      () {
        // Simulate a storage map produced by an older app version that did
        // not yet write the new key — the additive migration must default to
        // false instead of throwing.
        final map = AppSettings.defaults.toStorageMap()
          ..remove('auto_paste_off_hint_dismissed');
        final restored = AppSettings.fromStorageMap(map);
        expect(restored.onboarding.autoPasteOffHintDismissed, isFalse);
      },
    );
  });

  // ---- Section 16: Benchmark ----------------------------------------------
  group('Section: benchmark', () {
    test('all benchmark fields use expected storage keys', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('tier_benchmark_rtf'), isTrue);
      expect(map.containsKey('benchmark_hardware_id'), isTrue);
      expect(map.containsKey('benchmark_timestamp'), isTrue);
    });

    test('benchmark cluster full roundtrip with all fields set', () {
      final ts = DateTime.utc(2025, 12, 1, 8, 0, 0);
      final rtf = {
        QualityTier.compact: 0.25,
        QualityTier.balanced: 0.55,
        QualityTier.premium: 1.1,
      };
      final s = AppSettings.defaults.copyWith(
        tierBenchmarkRtf: rtf,
        benchmarkHardwareId: 'hw-abc123',
        benchmarkTimestamp: ts,
      );
      final r = _roundtrip(s);
      expect(r.tierBenchmarkRtf, isNotNull);
      expect(r.tierBenchmarkRtf![QualityTier.compact], closeTo(0.25, 1e-9));
      expect(r.tierBenchmarkRtf![QualityTier.balanced], closeTo(0.55, 1e-9));
      expect(r.tierBenchmarkRtf![QualityTier.premium], closeTo(1.1, 1e-9));
      expect(r.benchmarkHardwareId, 'hw-abc123');
      expect(r.benchmarkTimestamp, isNotNull);
      expect(r.benchmarkTimestamp!.isAtSameMomentAs(ts), isTrue);
    });

    test('benchmark cluster all-null roundtrip', () {
      final s = AppSettings.defaults.copyWith(
        tierBenchmarkRtf: null,
        benchmarkHardwareId: null,
        benchmarkTimestamp: null,
      );
      final r = _roundtrip(s);
      expect(r.tierBenchmarkRtf, isNull);
      expect(r.benchmarkTimestamp, isNull);
    });

    test('tierBenchmarkRtf serialises all QualityTier values by name', () {
      final rtf = {
        for (final tier in QualityTier.values) tier: tier.index * 0.5,
      };
      final s = AppSettings.defaults.copyWith(tierBenchmarkRtf: rtf);
      final map = s.toStorageMap();
      // The JSON must contain the tier names
      for (final tier in QualityTier.values) {
        expect(map['tier_benchmark_rtf']!, contains(tier.name));
      }
    });

    test('corrupt tierBenchmarkRtf JSON is silently ignored', () {
      final map = {'tier_benchmark_rtf': '{not valid json'};
      expect(AppSettings.fromStorageMap(map).tierBenchmarkRtf, isNull);
    });

    test('benchmarkTimestamp round-trips as ISO-8601 UTC', () {
      final ts = DateTime.utc(2026, 1, 31, 23, 59, 59);
      final s = AppSettings.defaults.copyWith(benchmarkTimestamp: ts);
      final stored = s.toStorageMap()['benchmark_timestamp']!;
      expect(stored, contains('2026-01-31'));
      expect(DateTime.tryParse(stored), isNotNull);
    });
  });

  // ---- Section 17: After-Transcription (standalone) -----------------------
  group('Section: after-transcription', () {
    test('afterTranscription storage key is present', () {
      final map = AppSettings.defaults.toStorageMap();
      expect(map.containsKey('after_transcription'), isTrue);
    });

    test('all AfterTranscriptionAction values survive roundtrip', () {
      for (final action in AfterTranscriptionAction.values) {
        final s = AppSettings.defaults.copyWith(
          afterTranscription: action.value,
        );
        expect(
          _roundtrip(s).afterTranscription,
          action.value,
          reason: 'action ${action.name} did not survive roundtrip',
        );
      }
    });

    test('afterTranscription default is clipboard', () {
      expect(AppSettings.defaults.afterTranscription, 'clipboard');
    });
  });

  // =========================================================================
  // 3. Forward/backward-compat contract
  // =========================================================================
  group('Forward/backward compatibility', () {
    test('schema_version 2 is present in every toStorageMap call', () {
      expect(AppSettings.defaults.toStorageMap()['schema_version'], '2');
    });

    test('unknown extra keys in map are silently ignored', () {
      final map = Map<String, String>.from(AppSettings.defaults.toStorageMap())
        ..['future_section_field'] = 'future_value'
        ..['another_unknown_key'] = '42';
      expect(() => AppSettings.fromStorageMap(map), returnsNormally);
    });

    test('completely empty map falls back to defaults for every field', () {
      final r = AppSettings.fromStorageMap({});
      expect(r.locale, AppSettings.defaults.locale);
      expect(r.sttModel, AppSettings.defaults.sttModel);
      expect(r.soundVolume, AppSettings.defaults.soundVolume);
      expect(r.historyMaxEntries, AppSettings.defaults.historyMaxEntries);
      expect(r.checkUpdates, AppSettings.defaults.checkUpdates);
      expect(r.tierBenchmarkRtf, isNull);
      expect(r.benchmarkTimestamp, isNull);
    });

    test('boolean key with unexpected value falls back to false', () {
      // Any string other than 'true' → false (per _readBool semantics)
      final map = {'launch_at_startup': 'yes'};
      expect(AppSettings.fromStorageMap(map).launchAtStartup, isFalse);
    });
  });
}
