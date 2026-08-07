/// Speech Recognition settings section — unified tier-based UI.
///
/// When local STT is selected, shows quality tier cards (compact/balanced/
/// premium) with one-click download. When a cloud provider is selected,
/// shows the relevant API key inline for convenience.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/config/whisper_languages.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/stt/stt_bundle.dart';
import '../../../services/stt_parakeet/parakeet_download_service.dart';
import '../../../services/stt_parakeet/parakeet_model_registry.dart';
import '../../../services/telemetry_service.dart';
import '../../../widgets/model_download_card.dart';
import '../../../widgets/section.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Speech Recognition section
// ---------------------------------------------------------------------------

class SpeechRecognitionSection extends ConsumerStatefulWidget {
  const SpeechRecognitionSection({super.key});

  @override
  ConsumerState<SpeechRecognitionSection> createState() =>
      _SpeechRecognitionSectionState();
}

class _SpeechRecognitionSectionState
    extends ConsumerState<SpeechRecognitionSection> {
  static final _log = AppLogger('SpeechRecognitionSection');

  final _apiKeyCtrl = TextEditingController();
  bool _showKey = false;

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final isLocal = settings.sttProviderType.isLocal;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Recognition-language names localised to the active UI language via CLDR
    // data; falls back to the catalog's English name for any Whisper-specific
    // code CLDR doesn't know. Sorted by the localised name so the list reads
    // naturally in every UI language.
    final localeNames = LocaleNames.of(context);
    final sttLanguages =
        whisperLanguages.keys
            .map(
              (code) => MapEntry(
                code,
                localeNames?.nameOf(code) ?? whisperLanguages[code]!,
              ),
            )
            .toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    return WpSection(
      title: l10n.settingsSpeechRecognition,
      subtitle: l10n.settingsSpeechRecognitionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Provider selector (On-device / OpenAI / Deepgram)
          SettingRow(
            icon: LucideIcons.cpu,
            label: l10n.settingsService,
            trailing: settingsDropdown(
              context: context,
              value: settings.sttProviderType.value,
              items: SttProviderType.values.map((e) => e.value).toList(),
              labels: [
                l10n.settingsServiceOnDevicePrivate,
                'OpenAI',
                'Deepgram',
              ],
              onChanged: (v) {
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(sttProvider: v!));
                try {
                  ref
                      .read(telemetryProvider)
                      .trackSettingChange('stt_provider');
                } catch (e) {
                  _log.debug('telemetry failed: $e');
                }
              },
            ),
          ),

          // ----- Local mode: engine selector + tier cards / model management --
          if (isLocal) ...[
            const SizedBox(height: WpSpacing.xs),
            // On-device engine selector (Whisper / Parakeet). See
            // `.scratch/whisper-ffi-engine/PRD.md` — Parakeet chapter.
            SettingRow(
              icon: LucideIcons.gauge,
              label: l10n.settingsSttEngine,
              trailing: settingsDropdown(
                context: context,
                value: settings.onDeviceEngine.value,
                items: OnDeviceEngine.values.map((e) => e.value).toList(),
                labels: [
                  l10n.settingsSttEngineWhisper,
                  l10n.settingsSttEngineParakeet,
                ],
                onChanged: (v) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateSettings((s) => s.copyWith(sttEngine: v!));
                  try {
                    ref
                        .read(telemetryProvider)
                        .trackSettingChange('stt_engine');
                  } catch (e) {
                    _log.debug('telemetry failed: $e');
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WpSpacing.sm,
                vertical: WpSpacing.xs,
              ),
              child: Text(
                l10n.settingsSttEngineSubtitle,
                style: TextStyle(
                  fontSize: WpTypography.small,
                  color: isDark
                      ? WpColorsDark.textMuted
                      : WpColorsLight.textMuted,
                ),
              ),
            ),
            const SizedBox(height: WpSpacing.xs),
            if (settings.onDeviceEngine == OnDeviceEngine.parakeet)
              _ParakeetModelRow(l10n: l10n)
            else
              const SttModelManager(),
            const SizedBox(height: WpSpacing.xs),
            // Re-run benchmark button — whisper only (Parakeet has no tiers
            // to benchmark yet, see plan risk #1 in the PRD chapter above).
            if (settings.onDeviceEngine == OnDeviceEngine.whisper)
              _BenchmarkButton(l10n: l10n, ref: ref),
            // GPU acceleration — whisper only. Parakeet has no GPU backend
            // yet (see plan risk #1), so this setting would have no effect.
            if (settings.onDeviceEngine == OnDeviceEngine.whisper)
              SettingRow(
                icon: LucideIcons.zap,
                label: l10n.settingsGpuAcceleration,
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
            settingsInlineDivider(context),
          ],

          // ----- Cloud mode: inline API key + sub-provider ------------------
          if (!isLocal) ...[
            _CloudSttInlineKey(
              provider: settings.sttProviderType,
              apiKeyCtrl: _apiKeyCtrl,
              showKey: _showKey,
              onToggleVisibility: () => setState(() => _showKey = !_showKey),
              ref: ref,
              settings: settings,
            ),
          ],

          // Language selector — Whisper only. Values are short codes
          // ('auto', 'en', 'ru', …); `sttLanguageCode` normalizes legacy
          // persisted display values ('German') so they keep selecting
          // correctly. Hidden entirely for Parakeet: the sherpa_onnx
          // NeMo-transducer binding used here has no per-request language
          // override — it always auto-detects among its supported
          // languages — so a picker would look functional but silently do
          // nothing, the same "looks available but isn't" trap as the
          // GPU-acceleration row above.
          if (!isLocal || settings.onDeviceEngine == OnDeviceEngine.whisper)
            SettingRow(
              icon: LucideIcons.languages,
              label: l10n.settingsRecognitionLanguage,
              trailing: settingsDropdown(
                context: context,
                value: settings.sttLanguageCode,
                items: ['auto', ...sttLanguages.map((e) => e.key)],
                labels: [
                  l10n.settingsLanguageAutoDetect,
                  ...sttLanguages.map((e) => e.value),
                ],
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(sttLanguage: v!)),
              ),
            ),

          // Both punctuation-related toggles are grouped directly together
          // (Strip Punctuation, then Punctuation Priming right below it) so
          // they read as a pair, even though Punctuation Priming is
          // local-Whisper-only and Custom Vocabulary (below both) has a
          // different, wider visibility condition.

          // Strip punctuation — engine/provider-independent. Unlike
          // punctuationPriming below (a Whisper-only prompt nudge), this is
          // a deterministic post-processing step applied to the final
          // transcript in RecordingOrchestrator regardless of which STT
          // engine or provider produced it, so it works identically for
          // on-device Whisper, Parakeet, and every cloud provider.
          SettingRow(
            icon: LucideIcons.eraser,
            label: l10n.settingsStripPunctuation,
            subtitle: l10n.settingsStripPunctuationSubtitle,
            semanticToggledValue: settings.stt.stripPunctuation,
            trailing: settingsToggle(
              value: settings.stt.stripPunctuation,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      stt: s.stt.copyWith(stripPunctuation: v),
                    ),
                  ),
            ),
          ),

          // Punctuation priming — local Whisper only (a prompt nudge fed
          // into whisper.cpp's initial-prompt mechanism; no equivalent
          // exists for the cloud providers or Parakeet). For a toggle that
          // reliably removes punctuation regardless of engine/provider, see
          // "Strip punctuation" directly above.
          if (isLocal && settings.onDeviceEngine == OnDeviceEngine.whisper)
            SettingRow(
              icon: LucideIcons.pilcrow,
              label: l10n.settingsPunctuationPriming,
              subtitle: l10n.settingsPunctuationPrimingSubtitle,
              semanticToggledValue: settings.stt.punctuationPriming,
              trailing: settingsToggle(
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
            SettingRow(
              icon: LucideIcons.scissors,
              label: l10n.settingsVadEnabled,
              subtitle: l10n.settingsVadEnabledSubtitle,
              semanticToggledValue: settings.stt.vadEnabled,
              trailing: settingsToggle(
                value: settings.stt.vadEnabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        stt: s.stt.copyWith(vadEnabled: v),
                      ),
                    ),
              ),
            ),

          // Custom vocabulary — local Whisper (initial-prompt, see
          // stt_server_state_notifier.dart) OR OpenAI cloud (the equivalent
          // `prompt` field on /v1/audio/transcriptions, see
          // openai_transcriber.dart). Deepgram has no free-text prompt
          // mechanism (it uses per-term `keywords` boosting instead — a
          // different feature, not built yet) and Parakeet's transducer
          // architecture has no prompt-conditioning at all, so both stay
          // excluded — showing the field there would be the same "looks
          // available but isn't" trap as the language picker above.
          if (isLocal && settings.onDeviceEngine == OnDeviceEngine.whisper ||
              settings.sttProviderType == SttProviderType.openAI)
            _CustomVocabularyField(initialValue: settings.customVocabulary),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inline cloud API key — shows the key field for the currently selected
// cloud STT provider, right in the STT section for convenience.
// ---------------------------------------------------------------------------

class _CloudSttInlineKey extends StatelessWidget {
  const _CloudSttInlineKey({
    required this.provider,
    required this.apiKeyCtrl,
    required this.showKey,
    required this.onToggleVisibility,
    required this.ref,
    required this.settings,
  });

  final SttProviderType provider;
  final TextEditingController apiKeyCtrl;
  final bool showKey;
  final VoidCallback onToggleVisibility;
  final WidgetRef ref;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    // Map provider → key value and label
    final (
      String label,
      String keyValue,
      void Function(String) onChanged,
    ) = switch (provider) {
      SttProviderType.openAI => (
        l10n.settingsOpenAiApiKey,
        settings.openAiApiKey,
        (String v) => ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(openAiApiKey: v)),
      ),
      SttProviderType.deepgram => (
        l10n.settingsDeepgramApiKey,
        settings.deepgramApiKey,
        (String v) => ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(deepgramApiKey: v)),
      ),
      _ => ('', '', (String _) {}),
    };

    if (label.isEmpty) return const SizedBox.shrink();

    syncController(apiKeyCtrl, keyValue);

    return SettingRow(
      icon: LucideIcons.keyRound,
      label: label,
      trailing: settingsApiKeyField(
        context: context,
        controller: apiKeyCtrl,
        obscure: !showKey,
        onToggle: onToggleVisibility,
        onChanged: onChanged,
        semanticLabel: label,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Re-run benchmark button — appears below the model manager in local mode
// ---------------------------------------------------------------------------

class _BenchmarkButton extends ConsumerWidget {
  const _BenchmarkButton({required this.l10n, required this.ref});

  final L10n l10n;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sttStatus = ref.watch(localSttBundleProvider);
    final isBenchmarking = sttStatus.isBenchmarking;

    return SettingRow(
      icon: LucideIcons.timer,
      label: isBenchmarking
          ? l10n.qualityTierInfoBenchmarking
          : l10n.qualityTierBenchmarkReRun,
      trailing: isBenchmarking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(LucideIcons.refreshCw, size: WpIconSize.sm),
              onPressed: () {
                ref.read(localSttBundleProvider.notifier).runBenchmark();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.qualityTierInfoBenchmarking),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              tooltip: l10n.qualityTierBenchmarkReRun,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Parakeet model row — single-bundle download (no tiers, unlike whisper).
// ---------------------------------------------------------------------------

class _ParakeetModelRow extends ConsumerWidget {
  const _ParakeetModelRow({required this.l10n});

  final L10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(parakeetDownloadProvider);
    final sizeLabel = '${(parakeetModelTotalBytes / (1024 * 1024)).round()} MB';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget trailing;
    if (dl.installed && !dl.isBusy) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.parakeetModelInstalled),
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: WpIconSize.sm),
            tooltip: l10n.parakeetModelDelete,
            onPressed: () =>
                ref.read(parakeetDownloadProvider.notifier).deleteBundle(),
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
                Text('${l10n.parakeetModelDownloading} ${dl.progressPercent}%'),
                IconButton(
                  icon: const Icon(LucideIcons.x, size: WpIconSize.xs),
                  tooltip: l10n.parakeetModelCancel,
                  onPressed: () => ref
                      .read(parakeetDownloadProvider.notifier)
                      .cancelDownload(),
                ),
              ],
            ),
            LinearProgressIndicator(value: dl.progressPercent / 100),
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
                dl.errorMessage!,
                style: TextStyle(
                  fontSize: WpTypography.caption,
                  color: isDark ? WpColorsDark.error : WpColorsLight.error,
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

    return SettingRow(
      icon: LucideIcons.cpu,
      label: '${l10n.parakeetModelTitle} ($sizeLabel)',
      trailing: trailing,
    );
  }
}

// ---------------------------------------------------------------------------
// Custom Vocabulary text field (debounced save)
// ---------------------------------------------------------------------------

class _CustomVocabularyField extends ConsumerStatefulWidget {
  const _CustomVocabularyField({required this.initialValue});

  final String initialValue;

  @override
  ConsumerState<_CustomVocabularyField> createState() =>
      _CustomVocabularyFieldState();
}

class _CustomVocabularyFieldState
    extends ConsumerState<_CustomVocabularyField> {
  late final TextEditingController _ctrl;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _CustomVocabularyField old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue &&
        _ctrl.text != widget.initialValue) {
      _ctrl.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _save(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      ref
          .read(settingsProvider.notifier)
          .updateSettings((s) => s.copyWith(customVocabulary: value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WpSpacing.sm,
        vertical: WpSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.bookType,
                size: WpIconSize.sm,
                color: cs.secondary,
              ),
              const SizedBox(width: WpSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.settingsCustomVocabulary,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    Padding(
                      // 2px title-subtitle gap: tighter than WpSpacing.xxs so
                      // the pair reads as one unit.
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.settingsCustomVocabularyHint,
                        style: TextStyle(
                          fontSize: WpTypography.small,
                          color: isDark
                              ? WpColorsDark.textMuted
                              : WpColorsLight.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.sm),
          Semantics(
            label: l10n.settingsCustomVocabulary,
            textField: true,
            child: TextField(
              controller: _ctrl,
              minLines: 2,
              maxLines: 5,
              onChanged: _save,
              style: TextStyle(
                fontSize: WpTypography.body,
                color: isDark
                    ? WpColorsDark.textPrimary
                    : WpColorsLight.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: l10n.settingsCustomVocabularyPlaceholder,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.sm,
                  vertical: WpSpacing.sm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
