/// Speech Recognition settings section — unified tier-based UI.
///
/// When local STT is selected, shows quality tier cards (compact/balanced/
/// premium) with one-click download. When a cloud provider is selected,
/// shows whether its API key is stored and links to the API keys area, the
/// one place where keys are entered (#208).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/language_favorites_provider.dart';
import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/stt_choice.dart' show applyEngineChoice;
import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/download_error_text.dart';
import '../../../core/l10n/locale_native_name.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/navigation/page_state.dart'
    show settingsLanguageDialogRequestProvider;
import '../../../core/theme/colors.dart';
import '../../../widgets/wp_progress_bar.dart';
import '../../../widgets/model_ram_precheck_dialog.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/engine_recommendation.dart';
import '../../../services/speech_recommendation.dart'
    show systemLanguageCodesProvider;
import '../../../services/model_download_service.dart'
    show modelDownloadProvider, sttModels;
import '../../../services/stt/whisper/cuda_pack.dart';
import '../../../services/stt/whisper/vram_gate.dart';
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../services/system_speech/system_speech_channel.dart';
import '../../../services/system_speech/system_speech_status.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/wp_stt_model_manager.dart';
import '../../../widgets/wp_button.dart';
import '../../../services/stt/stt_bundle.dart' show localSttBundleProvider;
import '../../../widgets/wp_banner.dart';
import 'gpu_probe_row.dart';
import '../../../widgets/dialog.dart';
import '../settings_widgets.dart';
import '../widgets/wp_language_dialog.dart';
import '../../../services/stt_parakeet/parakeet_language_support.dart';
import '../../../widgets/parakeet_language_notice.dart';
import 'api_keys_section.dart' show ApiKeyProvider, ApiKeyStatusLinkRow;
import 'benchmark_row.dart';
import 'cuda_pack_row.dart';
import 'stt_keep_loaded_rows.dart';
import '../widgets/custom_endpoint_rows.dart';
import '../widgets/wp_settings_group.dart';

// ---------------------------------------------------------------------------
// Speech Recognition section
// ---------------------------------------------------------------------------

/// Labels of the engine dropdown, in [OnDeviceEngine] order (Whisper, then
/// Parakeet). The recommended engine carries the badge, so for a Parakeet
/// language exactly this one entry says "Empfohlen" (UIA-RT-03).
List<String> sttEngineDropdownLabels(
  L10n l10n, {
  required bool parakeetRecommended,
  bool systemAvailable = false,
}) => [
  l10n.settingsSttEngineWhisper,
  parakeetRecommended
      ? '${l10n.settingsSttEngineParakeet} · ${l10n.settingsSttEngineRecommended}'
      : l10n.settingsSttEngineParakeet,
  if (systemAvailable) l10n.settingsSttEngineSystem,
];

/// The engines the dropdown offers, in the same order as
/// [sttEngineDropdownLabels]. Apple's engine appears only on macOS 26+.
List<OnDeviceEngine> sttEngineChoices({required bool systemAvailable}) => [
  OnDeviceEngine.whisper,
  OnDeviceEngine.parakeet,
  if (systemAvailable) OnDeviceEngine.system,
];

/// The engine the dropdown shows: the stored one when it is offered, else
/// Whisper (for example Apple's engine on a Mac older than macOS 26).
OnDeviceEngine shownOnDeviceEngine(
  AppSettings settings,
  List<OnDeviceEngine> choices,
) => choices.contains(settings.onDeviceEngine)
    ? settings.onDeviceEngine
    : OnDeviceEngine.whisper;

class SpeechRecognitionSection extends ConsumerStatefulWidget {
  const SpeechRecognitionSection({super.key});

  @override
  ConsumerState<SpeechRecognitionSection> createState() =>
      _SpeechRecognitionSectionState();
}

class _SpeechRecognitionSectionState
    extends ConsumerState<SpeechRecognitionSection> {
  static final _log = AppLogger('SpeechRecognitionSection');

  @override
  void initState() {
    super.initState();
    // Settings opened by "More languages…": the request is already pending.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _takeLanguageDialogRequest(),
    );
  }

  /// Opens the language dialog for a pending "More languages…" request, when
  /// the engine lets the user pick a language at all.
  void _takeLanguageDialogRequest() {
    if (!mounted) return;
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final picksLanguage =
        !settings.sttProviderType.isLocal ||
        settings.onDeviceEngine == OnDeviceEngine.whisper;
    if (!ref.read(settingsLanguageDialogRequestProvider.notifier).take()) {
      return;
    }
    if (picksLanguage) unawaited(_openLanguageDialog());
  }

  /// Recognition-language names localised to the active UI language via CLDR
  /// data; falls back to the catalog's English name for any Whisper-specific
  /// code CLDR doesn't know. Sorted by the localised name so the list reads
  /// naturally in every UI language.
  List<MapEntry<String, String>> _sttLanguages(BuildContext context) {
    final localeNames = LocaleNames.of(context);
    return whisperLanguages.keys
        .map(
          (code) => MapEntry(
            code,
            localeNames?.nameOf(code) ?? whisperLanguages[code]!,
          ),
        )
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
  }

  /// The full recognition-language selection, with the favorite stars.
  Future<void> _openLanguageDialog() async {
    final settings = ref.read(settingsProvider).value ?? AppSettings.defaults;
    final sttLanguages = _sttLanguages(context);
    final selection = await showWpLanguageDialog(
      context: context,
      options: [
        for (final e in sttLanguages)
          WpLanguageOption(
            code: e.key,
            name: e.value,
            endonym: localeNativeName(Locale(e.key)),
          ),
      ],
      initial: WpLanguageSelection(
        autoDetect: settings.sttLanguageCode == 'auto',
        codes: settings.sttLanguageCode == 'auto'
            ? const []
            : [settings.sttLanguageCode],
      ),
      favorites: settings.stt.favoriteLanguages,
      // Stars persist at once, not on Save: they are a standing
      // list, not part of this one pick.
      onFavoritesChanged: (favorites) =>
          ref.read(languageFavoritesProvider.notifier).replaceAll(favorites),
    );
    if (selection == null) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings((s) => s.copyWith(sttLanguage: selection.sttCode));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isLocal = settings.sttProviderType.isLocal;
    final engineChoices = sttEngineChoices(
      systemAvailable: systemSpeechOsSupported(),
    );

    final sttLanguages = _sttLanguages(context);
    // "More languages…" in the tray or the floating button's menu asks for
    // the full selection while Settings is already open.
    ref.listen<bool>(settingsLanguageDialogRequestProvider, (_, pending) {
      if (pending) _takeLanguageDialogRequest();
    });

    return WpSettingsGroup(
      heading: l10n.settingsSpeechRecognition,
      children: [
        // Provider selector (On-device / OpenAI / Deepgram)
        WpSettingsRow(
          rowId: 'speech-provider',
          title: l10n.settingsService,
          trailing: settingsDropdown(
            context: context,
            value: settings.sttProviderType.value,
            items: SttProviderType.values.map((e) => e.value).toList(),
            labels: [
              l10n.settingsServiceOnDevicePrivate,
              'OpenAI',
              'Deepgram',
              l10n.settingsSttCustomEndpoint,
            ],
            onChanged: (v) {
              ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(sttProvider: v!));
              try {
                ref.read(telemetryProvider).trackSettingChange('stt_provider');
              } catch (e) {
                _log.debug('telemetry failed: $e');
              }
            },
          ),
        ),

        // ----- Local mode: engine selector + tier cards / model management --
        if (isLocal) ...[
          const SizedBox(height: WpSpacing.xs),
          // On-device engine selector (Whisper / Parakeet).
          WpSettingsRow(
            rowId: 'stt-model',
            title: l10n.settingsSttEngine,
            trailing: settingsDropdown(
              context: context,
              value: shownOnDeviceEngine(settings, engineChoices).value,
              items: engineChoices.map((e) => e.value).toList(),
              labels: sttEngineDropdownLabels(
                l10n,
                parakeetRecommended: parakeetRecommendedFor(
                  recommendationLanguages(
                    sttLanguageCode: settings.sttLanguageCode,
                    systemLanguages: ref.watch(systemLanguageCodesProvider),
                    uiLocale: settings.interface_.locale,
                  ),
                ),
                systemAvailable: systemSpeechOsSupported(),
              ),
              onChanged: (v) async {
                final current = ref.read(settingsProvider).value;
                final downloaded = ref
                    .read(modelDownloadProvider)
                    .downloadedModels;
                if (current != null) {
                  final next = applyEngineChoice(
                    current,
                    v!,
                    downloaded: downloaded,
                    models: sttModels,
                  );
                  // Nothing loads while the target is not on disk yet.
                  final installed =
                      next.onDeviceEngine == OnDeviceEngine.parakeet
                      ? ref.read(parakeetDownloadProvider).installed
                      : downloaded.contains(next.effectiveModelId);
                  if (!context.mounted ||
                      !await confirmSttSettingsRam(
                        context: context,
                        settings: next,
                        loads: installed,
                      )) {
                    return;
                  }
                }
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => applyEngineChoice(
                        s,
                        v!,
                        downloaded: downloaded,
                        models: sttModels,
                      ),
                    );
                try {
                  ref.read(telemetryProvider).trackSettingChange('stt_engine');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),
          // Deliberately outside the row's `subtitle:` slot, unlike every
          // other explanatory line in Settings. This one is a two-clause
          // comparison of both engines (languages, GPU backends, CPU speed);
          // in the label column it would wrap to four or five lines beside
          // the dropdown and turn the row into a paragraph with a control
          // stuck to its side. Full width is the readable shape here, and
          // the choice it explains is the most consequential one on the
          // page. It starts on kSettingRowInset, so it still shares the
          // reading edge with the section title and the row icons above it.
          //
          // Style matches SettingRow's own subtitle (bodySmall in textMuted)
          // rather than a hand-mixed pair, so it reads as the same kind of
          // text it would have been in the slot.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kSettingRowInset,
              vertical: WpSpacing.xs,
            ),
            child: Text(
              l10n.settingsSttEngineSubtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: WpColors.textMuted),
            ),
          ),
          const SizedBox(height: WpSpacing.xs),
          if (settings.onDeviceEngine == OnDeviceEngine.system)
            _SystemSpeechModelRow(l10n: l10n)
          else if (settings.onDeviceEngine == OnDeviceEngine.parakeet)
            _ParakeetModelRow(l10n: l10n)
          else
            SettingsRowFrame(
              rowId: 'speech-quality',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
                    child: Text(
                      l10n.settingsQuality,
                      style: TextStyle(
                        fontSize: WpTypography.rowTitle,
                        fontWeight: FontWeight.w500,
                        color: WpColors.textPrimary,
                      ),
                    ),
                  ),
                  const WpSttModelManager(),
                  const _SttVramGateNotice(),
                ],
              ),
            ),
          const SizedBox(height: WpSpacing.xs),
          const SttKeepLoadedRows(),
          const SizedBox(height: WpSpacing.xs),
          // Re-run benchmark button — whisper only (Parakeet has no tiers
          // to benchmark yet, see plan risk #1 in the PRD chapter above).
          if (settings.onDeviceEngine == OnDeviceEngine.whisper)
            const SttBenchmarkRow(),
          // GPU acceleration — whisper only. Parakeet has no GPU backend
          // yet (see plan risk #1), so this setting would have no effect.
          if (settings.onDeviceEngine == OnDeviceEngine.whisper)
            WpSettingsRow(
              rowId: 'speech-gpu',
              title: l10n.settingsGpuAcceleration,
              trailing: settingsDropdown(
                context: context,
                value: settings.behavior.gpuAcceleration,
                items: GpuAcceleration.values.map((e) => e.value).toList(),
                labels: [
                  l10n.settingsGpuAccelerationAuto,
                  l10n.settingsGpuAccelerationEnabled,
                  l10n.settingsGpuAccelerationDisabled,
                ],
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        behavior: s.behavior.copyWith(gpuAcceleration: v!),
                      ),
                    ),
              ),
            ),
          // Optional NVIDIA CUDA pack — only for Turing+ NVIDIA cards
          // outside the Store build, and moot when "CPU only" is chosen.
          // The row renders nothing without a pack state, so the group only
          // gets it as a child when it has something to show (see the divider
          // note in WpSettingsGroup).
          if (settings.onDeviceEngine == OnDeviceEngine.whisper &&
              settings.behavior.gpuAcceleration !=
                  GpuAcceleration.disabled.value &&
              ref.watch(cudaPackOfferedProvider) &&
              ref.watch(cudaPackProvider).pack != null)
            const CudaPackRow(),
          // GPU check result and a retry (see gpu_probe_row.dart); shown only
          // where the GPU setting itself applies.
          if (settings.onDeviceEngine == OnDeviceEngine.whisper &&
              settings.behavior.gpuAcceleration !=
                  GpuAcceleration.disabled.value)
            const SttGpuProbeRow(),
          // The fallback also stands here for good: the overlay card that
          // told the user about it closes after a while (#453).
          if (settings.onDeviceEngine == OnDeviceEngine.whisper &&
              ref.watch(localSttBundleProvider).cpuFallbackActive)
            Padding(
              padding: const EdgeInsets.only(top: WpSpacing.sm),
              child: Semantics(
                identifier: 'settings-cpu-fallback-notice',
                child: WpBanner(
                  tone: WpBannerTone.info,
                  message:
                      '${l10n.errorNoticeCpuCause} ${l10n.errorNoticeCpuNext}',
                ),
              ),
            ),
          settingsInlineBreak,
        ],

        // ----- Cloud mode: key status + link, sub-provider ---------------
        if (!isLocal) ...[
          if (switch (settings.sttProviderType) {
                SttProviderType.openAI => ApiKeyProvider.openAi,
                SttProviderType.deepgram => ApiKeyProvider.deepgram,
                _ => null,
              }
              case final keyProvider?)
            ApiKeyStatusLinkRow(
              rowId: 'speech-api-key',
              provider: keyProvider,
              linkTestId: 'settings-stt-api-keys-link',
            ),
          if (settings.sttProviderType == SttProviderType.customEndpoint)
            const CustomEndpointRows(scope: CustomEndpointScope.speech),
        ],

        // Parakeet ignores the recognition language. Name the gap here, where
        // the language is chosen, and offer Whisper instead of failing silently.
        if (parakeetUnsupportedLanguage(settings) case final gap?)
          WpParakeetLanguageBanner(
            languageCode: gap,
            onSwitch: () => ref
                .read(settingsProvider.notifier)
                .updateSettings(
                  (s) => s.copyWithSections(
                    stt: s.stt.copyWith(engine: OnDeviceEngine.whisper.value),
                  ),
                ),
          ),

        // Language selector — Whisper only. Values are short codes
        // ('auto', 'en', 'ru', …); `sttLanguageCode` normalizes legacy
        // persisted display values ('German') so they keep selecting
        // correctly. Hidden entirely for Parakeet: the sherpa_onnx
        // NeMo-transducer binding used here has no per-request language
        // override — it always auto-detects among its supported
        // languages — so a picker would look functional but silently do
        // nothing, the same "looks available but isn't" trap as the
        // GPU-acceleration row above.
        if (!isLocal || settings.onDeviceEngine == OnDeviceEngine.whisper) ...[
          WpSettingsRow(
            rowId: 'speech-language',
            title: l10n.settingsRecognitionLanguage,
            subtitle: l10n.settingsRecognitionLanguageSubtitle,
            key: const ValueKey('settings-stt-language'),
            trailing: _LanguageSummary(
              current: settings.sttLanguageCode == 'auto'
                  ? l10n.settingsLanguageAutoDetect
                  : sttLanguages
                            .where((e) => e.key == settings.sttLanguageCode)
                            .map((e) => e.value)
                            .firstOrNull ??
                        settings.sttLanguageCode,
              onChange: _openLanguageDialog,
            ),
          ),
        ],

        // Both punctuation-related toggles are grouped directly together
        // (Strip Punctuation, then Punctuation Priming right below it) so
        // they read as a pair, even though Punctuation Priming is
        // local-Whisper-only and Custom Vocabulary (below both) has a
        // different, wider visibility condition.

        // Punctuation priming — local Whisper only (a prompt nudge fed
        // into whisper.cpp's initial-prompt mechanism; no equivalent
        // exists for the cloud providers or Parakeet). For a toggle that
        // reliably removes punctuation regardless of engine/provider, see
        // "Strip punctuation" directly above.
        if (isLocal && settings.onDeviceEngine == OnDeviceEngine.whisper)
          WpSettingsRow(
            rowId: 'speech-punctuation-priming',
            title: l10n.settingsPunctuationPriming,
            subtitle: l10n.settingsPunctuationPrimingSubtitle,
            switchNamesRow: true,
            trailing: settingsToggle(
              label: l10n.settingsPunctuationPriming,
              value: settings.stt.punctuationPriming,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      stt: s.stt.copyWith(punctuationPriming: v),
                    ),
                  ),
            ),
          ),

        // VAD trailing-silence trim — local Whisper only (whisper.cpp's
        // built-in Voice Activity Detection pre-pass; no equivalent for
        // cloud providers or Parakeet). Mitigates Whisper's documented
        // trailing-silence hallucination class (fabricated closing
        // sentences, e.g. "Vielen Dank" — see the 2026-07-29
        // investigation). Default on; no-op if the platform build hasn't
        // bundled the VAD model yet (assets/models/vad/NOTICE.md).
        if (isLocal && settings.onDeviceEngine == OnDeviceEngine.whisper)
          WpSettingsRow(
            rowId: 'speech-vad',
            title: l10n.settingsVadEnabled,
            subtitle: l10n.settingsVadEnabledSubtitle,
            switchNamesRow: true,
            trailing: settingsToggle(
              label: l10n.settingsVadEnabled,
              value: settings.stt.vadEnabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) =>
                        s.copyWithSections(stt: s.stt.copyWith(vadEnabled: v)),
                  ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Parakeet model row — single-bundle download (no tiers, unlike whisper).
// ---------------------------------------------------------------------------

/// Apple's engine has no model to pick or size: the system keeps the language
/// asset. This row shows whether it is there and offers the download.
class _SystemSpeechModelRow extends ConsumerWidget {
  const _SystemSpeechModelRow({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(systemSpeechProvider);
    final String text;
    Widget? action;
    if (s.installing) {
      text = '${l10n.settingsSttSystemInstalling} ${s.percent} %';
    } else if (s.installed) {
      text = l10n.settingsSttSystemInstalled;
    } else if (s.localeUnsupported) {
      text = l10n.settingsSttSystemLanguageUnsupported;
    } else {
      text = s.failed ? l10n.settingsSttSystemFailed : '';
      action = WpButton(
        key: const ValueKey('settings-stt-system-install'),
        label: l10n.settingsSttSystemInstall,
        variant: WpButtonVariant.secondary,
        onPressed: () => ref.read(systemSpeechProvider.notifier).install(),
      );
    }
    return SettingsRowFrame(
      key: const ValueKey('settings-stt-system-row'),
      rowId: 'speech-system',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
            child: Text(
              text.isEmpty
                  ? l10n.settingsSttSystemHint
                  : '$text\n${l10n.settingsSttSystemHint}',
              key: const ValueKey('settings-stt-system-notice'),
              style: TextStyle(color: WpColors.textMuted),
            ),
          ),
          if (s.installing)
            WpProgressBar(
              key: const ValueKey('settings-stt-system-progress'),
              value: s.fraction,
            ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action),
        ],
      ),
    );
  }
}

class _ParakeetModelRow extends ConsumerWidget {
  const _ParakeetModelRow({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(parakeetDownloadProvider);
    final gpuWanted = parakeetGpuWantedForSetting(
      ref.watch(settingsProvider).value?.behavior.gpuAcceleration,
    );
    final sizeLabel = parakeetDownloadSizeLabel(gpuWanted: gpuWanted);

    Widget trailing;
    if (dl.installed && !dl.isBusy) {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          // A failed delete leaves the model installed; say why right here
          // instead of only in the not-installed branch (UIA-SET-04).
          if (dl.phase == ParakeetDownloadPhase.error &&
              dl.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
              child: Text(
                downloadFailureText(
                  l10n,
                  message: dl.errorMessage,
                  kind: dl.errorKind,
                ),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.error,
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.parakeetModelInstalled),
              Semantics(
                label: l10n.parakeetModelDelete,
                button: true,
                child: IconButton(
                  icon: const Icon(LucideIcons.trash2, size: WpIconSize.sm),
                  tooltip: l10n.parakeetModelDelete,
                  onPressed: () async {
                    final deleter = ref.read(parakeetDownloadProvider.notifier);
                    final confirmed = await showWpConfirmDialog(
                      context: context,
                      title: l10n.modelDeleteConfirm,
                      message: l10n.modelDeleteConfirmMessage,
                      confirmLabel: l10n.actionDelete,
                      cancelLabel: l10n.actionCancel,
                      destructive: true,
                    );
                    if (confirmed) deleter.deleteBundle();
                  },
                ),
              ),
            ],
          ),
        ],
      );
    } else if (dl.isBusy) {
      trailing = SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Flexible so a long translation or a narrow window ellipsizes
                // instead of overflowing the fixed-width slot (#1152).
                Flexible(
                  child: Text(
                    '${l10n.parakeetModelDownloading} ${dl.progressPercent}%',
                    key: const ValueKey('speech-parakeet-download-status'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Semantics(
                  label: l10n.parakeetModelCancel,
                  button: true,
                  child: IconButton(
                    key: const ValueKey('speech-parakeet-download-cancel'),
                    icon: const Icon(LucideIcons.x, size: WpIconSize.xs),
                    tooltip: l10n.parakeetModelCancel,
                    onPressed: () => ref
                        .read(parakeetDownloadProvider.notifier)
                        .cancelDownload(),
                  ),
                ),
              ],
            ),
            WpProgressBar(value: dl.progressPercent / 100),
          ],
        ),
      );
    } else {
      trailing = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dl.phase == ParakeetDownloadPhase.error &&
              dl.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: WpSpacing.xxs),
              child: Text(
                downloadFailureText(
                  l10n,
                  message: dl.errorMessage,
                  kind: dl.errorKind,
                ),
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: WpColors.error,
                ),
              ),
            ),
          WpButton(
            label: l10n.parakeetModelDownload,
            variant: WpButtonVariant.ghost,
            icon: LucideIcons.download,
            onPressed: () =>
                ref.read(parakeetDownloadProvider.notifier).downloadBundle(),
          ),
        ],
      );
    }

    return WpSettingsRow(
      rowId: 'speech-parakeet',
      title: l10n.parakeetModelTitle,
      subtitle: l10n.parakeetModelSubtitle(sizeLabel),
      trailing: trailing,
    );
  }
}

/// Trailing slot of the recognition-language row: the current choice and the
/// "Ändern" button that opens the language dialog (ticket wiring).
class _LanguageSummary extends StatelessWidget {
  const _LanguageSummary({required this.current, required this.onChange});

  final String current;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            current,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: WpColors.textSecondary),
          ),
        ),
        const SizedBox(width: WpSpacing.sm),
        WpButton(
          key: const ValueKey('settings-stt-language-change'),
          label: l10n.settingsLanguageChange,
          variant: WpButtonVariant.secondary,
          onPressed: onChange,
        ),
      ],
    );
  }
}

/// Tells the user why the selected model runs on the CPU although GPU
/// acceleration is on: its weights do not fit the detected VRAM.
class _SttVramGateNotice extends ConsumerWidget {
  const _SttVramGateNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(sttVramGateNoticeProvider);
    if (notice == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return Padding(
      key: const ValueKey('speech-vram-notice'),
      padding: const EdgeInsets.only(top: WpSpacing.sm),
      child: Text(
        l10n.settingsSttVramGateNotice(notice.vramMb, notice.requiredMb),
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: WpColors.textMuted),
      ),
    );
  }
}
