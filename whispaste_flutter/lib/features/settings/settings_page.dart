import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/config/settings_provider.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../services/model_download_service.dart';
import '../../widgets/model_download_card.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/section.dart';
import '../../widgets/toast.dart';

/// Settings page — organized sections with interactive controls.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // -- Cloud Provider key visibility (UI-only state) --
  final _openAiKeyCtrl = TextEditingController();
  final _groqKeyCtrl = TextEditingController();
  final _deepgramKeyCtrl = TextEditingController();
  final _anthropicKeyCtrl = TextEditingController();
  bool _showOpenAiKey = false;
  bool _showGroqKey = false;
  bool _showDeepgramKey = false;
  bool _showAnthropicKey = false;
  bool _showAdvancedModels = false;

  @override
  void dispose() {
    _openAiKeyCtrl.dispose();
    _groqKeyCtrl.dispose();
    _deepgramKeyCtrl.dispose();
    _anthropicKeyCtrl.dispose();
    super.dispose();
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = controller.value.copyWith(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
      composing: TextRange.empty,
    );
  }

  // ---------------------------------------------------------------------------
  // Control builders
  // ---------------------------------------------------------------------------

  Widget _dropdown({
    required String value,
    required List<String> items,
    List<String>? labels,
    required ValueChanged<String?> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? WpColorsDark.surfaceVariant
            : WpColorsLight.surfaceVariant,
        borderRadius: WpRadius.borderSm,
        border: Border.all(
          color: isDark
              ? WpColorsDark.borderSubtle
              : WpColorsLight.borderSubtle,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items
              .asMap()
              .entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.value,
                  child: Text(labels != null ? labels[e.key] : e.value),
                ),
              )
              .toList(),
          onChanged: onChanged,
          isDense: true,
          style: TextStyle(
            fontSize: 13,
            color: isDark
                ? WpColorsDark.textPrimary
                : WpColorsLight.textPrimary,
          ),
          dropdownColor: isDark
              ? WpColorsDark.surfaceElevated
              : WpColorsLight.surfaceElevated,
          borderRadius: WpRadius.borderSm,
          icon: Padding(
            padding: const EdgeInsets.only(left: WpSpacing.xs),
            child: Icon(
              LucideIcons.chevronDown,
              size: WpIconSize.xs,
              color: isDark
                  ? WpColorsDark.textMuted
                  : WpColorsLight.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String valueLabel,
    required ValueChanged<double> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? WpColorsDark.accent : WpColorsLight.accent;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: isDark
                  ? WpColorsDark.surfaceVariant
                  : WpColorsLight.surfaceVariant,
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.12),
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.xs),
        SizedBox(
          width: 52,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? WpColorsDark.textSecondary
                  : WpColorsLight.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _toggle({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Switch(value: value, onChanged: onChanged);
  }

  Widget _apiKeyField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 280,
      height: 34,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 13,
          color: isDark
              ? WpColorsDark.textPrimary
              : WpColorsLight.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: 'sk-...',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.xs,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? LucideIcons.eye : LucideIcons.eyeOff,
              size: WpIconSize.sm,
              color: isDark
                  ? WpColorsDark.textMuted
                  : WpColorsLight.textMuted,
            ),
            onPressed: onToggle,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
      ),
    );
  }

  Widget _sectionDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WpSpacing.xs),
      child: Divider(
        color: isDark
            ? WpColorsDark.borderSubtle
            : WpColorsLight.borderSubtle,
      ),
    );
  }

  String _fmtSeconds(double v) {
    if (v == 0) return L10n.of(context).settingsOff;
    return '${v.round()}s';
  }

  // ---------------------------------------------------------------------------
  // Quality tier helpers — user-friendly labels for STT models
  // ---------------------------------------------------------------------------

  /// All model IDs in display order.
  static const _qualityModelIds = [
    'whisper-tiny',
    'whisper-base',
    'whisper-small',
    'whisper-medium',
    'whisper-large-v3-turbo',
    'whisper-large-v3',
  ];

  /// User-friendly labels (localized) for each model ID.
  List<String> _qualityLabels(L10n l10n) => [
        l10n.settingsQualityFast,
        l10n.settingsQualityBasic,
        l10n.settingsQualityBalanced,
        '${l10n.settingsQualityHigh}  ${l10n.settingsQualityRecommended}',
        l10n.settingsQualityBest,
        l10n.settingsQualityMaximum,
      ];

  /// Description for the currently selected quality tier.
  String _qualityDescription(String modelId, L10n l10n) {
    final model = findSttModel(modelId);
    if (model == null) return '';
    return switch (modelId) {
      'whisper-tiny' => '${l10n.modelSizeTiny} (${model.sizeLabel})',
      'whisper-base' => '${l10n.modelSizeBase} (${model.sizeLabel})',
      'whisper-small' => '${l10n.modelSizeSmall} (${model.sizeLabel})',
      'whisper-medium' => '${l10n.modelSizeMedium} (${model.sizeLabel})',
      'whisper-large-v3-turbo' =>
        '${l10n.modelSizeLargeTurbo} (${model.sizeLabel})',
      'whisper-large-v3' => '${l10n.modelSizeLarge} (${model.sizeLabel})',
      _ => '',
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? AppSettings.defaults;

    _syncController(_openAiKeyCtrl, settings.openAiApiKey);
    _syncController(_groqKeyCtrl, settings.groqApiKey);
    _syncController(_deepgramKeyCtrl, settings.deepgramApiKey);
    _syncController(_anthropicKeyCtrl, settings.anthropicApiKey);

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Privacy Note ──
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: WpSpacing.md,
              vertical: WpSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? WpColorsDark.accentSubtle
                  : WpColorsLight.accentSubtle,
              borderRadius: WpRadius.borderSm,
              border: Border.all(
                color: isDark
                    ? WpColorsDark.accent.withValues(alpha: 0.15)
                    : WpColorsLight.accent.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.shieldCheck,
                  size: WpIconSize.sm,
                  color: isDark ? WpColorsDark.accent : WpColorsLight.accent,
                ),
                const SizedBox(width: WpSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.settingsPrivacyNote,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? WpColorsDark.textSecondary
                          : WpColorsLight.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: WpSpacing.md),

          // ═══════════════════════════════════════════════════════
          //  RECORDING PIPELINE — ordered by workflow:
          //  record → safety guard → transcribe → enhance
          // ═══════════════════════════════════════════════════════

          // ── 1. Audio & Recording ──
          WpSection(
            title: l10n.settingsAudio,
            subtitle: l10n.settingsAudioSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.mic,
                  label: l10n.settingsMicrophone,
                  trailing: _dropdown(
                    value: settings.microphone,
                    items: const ['Default', 'Headset Mic', 'USB Mic'],
                    labels: [
                      l10n.settingsMicrophoneDefault,
                      l10n.settingsMicrophoneHeadset,
                      l10n.settingsMicrophoneUsb,
                    ],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(microphone: v!)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.gauge,
                  label: l10n.settingsGain,
                  trailing: _slider(
                    value: settings.inputGain,
                    min: 0,
                    max: 300,
                    divisions: 60,
                    valueLabel: '${settings.inputGain.round()}%',
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(inputGain: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.hand,
                  label: l10n.settingsHoldToRecord,
                  trailing: _toggle(
                    value: settings.pushToTalk,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(pushToTalk: v)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 2. Recording Safety ──
          WpSection(
            title: l10n.settingsRecordingSafety,
            subtitle: l10n.settingsRecordingSafetySubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.shieldAlert,
                  label: l10n.settingsDeadMicTimeout,
                  trailing: _slider(
                    value: settings.deadMicTimeout,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    valueLabel: _fmtSeconds(settings.deadMicTimeout),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(deadMicTimeout: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.timerOff,
                  label: l10n.settingsAutoStopSilence,
                  trailing: _slider(
                    value: settings.autoStopSilence,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    valueLabel: _fmtSeconds(settings.autoStopSilence),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(autoStopSilence: v)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 3. Speech Recognition ──
          WpSection(
            title: l10n.settingsSpeechRecognition,
            subtitle: l10n.settingsSpeechRecognitionSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.cpu,
                  label: l10n.settingsService,
                  trailing: _dropdown(
                    value: settings.sttProvider,
                    items: const [
                      'On Device (Private)',
                      'OpenAI',
                      'Groq',
                      'Deepgram',
                    ],
                    labels: [
                      l10n.settingsServiceOnDevicePrivate,
                      'OpenAI',
                      'Groq',
                      'Deepgram',
                    ],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(sttProvider: v!)),
                  ),
                ),
                // Privacy hint for on-device mode
                if (settings.sttProvider == 'On Device (Private)')
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 52,
                      right: WpSpacing.md,
                      bottom: WpSpacing.xs,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          LucideIcons.shieldCheck,
                          size: 12,
                          color: isDark
                              ? WpColorsDark.success
                              : WpColorsLight.success,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.settingsPrivacyHintLocal,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? WpColorsDark.success
                                : WpColorsLight.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                _SettingRow(
                  icon: LucideIcons.brain,
                  label: l10n.settingsQuality,
                  trailing: _dropdown(
                    value: _qualityModelIds.contains(settings.sttModel)
                        ? settings.sttModel
                        : 'whisper-medium',
                    items: _qualityModelIds,
                    labels: _qualityLabels(l10n),
                    onChanged: (v) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateSettings((s) => s.copyWith(sttModel: v!));
                      // Auto-download if model not present
                      final dlState = ref.read(modelDownloadProvider);
                      if (!dlState.downloadedModels.contains(v) &&
                          !dlState.isBusy) {
                        ref
                            .read(modelDownloadProvider.notifier)
                            .downloadModel(v!);
                      }
                    },
                  ),
                ),
                // Quality description + download status row
                Builder(builder: (context) {
                  final dlState = ref.watch(modelDownloadProvider);
                  final isDownloaded =
                      dlState.downloadedModels.contains(settings.sttModel);
                  final isDownloading = dlState.isBusy &&
                      dlState.activeModelId == settings.sttModel;
                  final accent =
                      isDark ? WpColorsDark.accent : WpColorsLight.accent;
                  final success =
                      isDark ? WpColorsDark.success : WpColorsLight.success;
                  final textSec = isDark
                      ? WpColorsDark.textSecondary
                      : WpColorsLight.textSecondary;

                  return Padding(
                    padding: const EdgeInsets.only(
                      left: 52,
                      right: WpSpacing.md,
                      bottom: WpSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Quality description
                        Text(
                          _qualityDescription(settings.sttModel, l10n),
                          style: TextStyle(fontSize: 11, color: textSec),
                        ),
                        const SizedBox(height: 4),
                        // Download status
                        Row(
                          children: [
                            Icon(
                              isDownloaded
                                  ? LucideIcons.circleCheck
                                  : isDownloading
                                      ? LucideIcons.loader
                                      : LucideIcons.download,
                              size: 12,
                              color: isDownloaded
                                  ? success
                                  : isDownloading
                                      ? accent
                                      : textSec,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                isDownloaded
                                    ? l10n.settingsModelStatusReady
                                    : isDownloading
                                        ? '${l10n.settingsModelStatusDownloading} ${dlState.progressPercent}%'
                                        : l10n.settingsModelStatusNeeded,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDownloaded
                                      ? success
                                      : isDownloading
                                          ? accent
                                          : textSec,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Progress bar during download
                        if (isDownloading &&
                            dlState.phase == DownloadPhase.downloading)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(WpRadius.full),
                              child: LinearProgressIndicator(
                                value: dlState.progressPercent / 100,
                                minHeight: 2,
                                backgroundColor: isDark
                                    ? WpColorsDark.borderSubtle
                                    : WpColorsLight.borderSubtle,
                                valueColor: AlwaysStoppedAnimation(accent),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                _SettingRow(
                  icon: LucideIcons.languages,
                  label: l10n.settingsLanguage,
                  trailing: _dropdown(
                    value: settings.sttLanguage,
                    items: const [
                      'Auto-detect',
                      'English',
                      'German',
                      'French',
                      'Spanish',
                    ],
                    labels: [
                      l10n.settingsLanguageAutoDetect,
                      l10n.settingsLanguageEnglish,
                      l10n.settingsLanguageGerman,
                      l10n.settingsLanguageFrench,
                      l10n.settingsLanguageSpanish,
                    ],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(sttLanguage: v!)),
                  ),
                ),
              ],
            ),
          ),

          // ── 3b. Advanced Model Management (collapsed) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
            child: InkWell(
              onTap: () =>
                  setState(() => _showAdvancedModels = !_showAdvancedModels),
              borderRadius: WpRadius.borderSm,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: WpSpacing.sm,
                  horizontal: WpSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      _showAdvancedModels
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 14,
                      color: isDark
                          ? WpColorsDark.textMuted
                          : WpColorsLight.textMuted,
                    ),
                    const SizedBox(width: WpSpacing.xs),
                    Text(
                      l10n.settingsAdvancedModelManagement,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? WpColorsDark.textMuted
                            : WpColorsLight.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showAdvancedModels)
            WpSection(
              title: l10n.settingsSttModels,
              padding: EdgeInsets.zero,
              child: const SttModelManager(),
            ),
          _sectionDivider(),
          WpSection(
            title: l10n.settingsPostProcessing,
            subtitle: l10n.settingsTextEnhancementSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.sparkles,
                  label: l10n.settingsEnabled,
                  trailing: _toggle(
                    value: settings.postProcessEnabled,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(postProcessEnabled: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.wandSparkles,
                  label: l10n.settingsStyle,
                  trailing: _dropdown(
                    value: settings.postProcessPreset,
                    items: const ['Clean up', 'Concise', 'Translate'],
                    labels: [l10n.settingsPresetCleanup, l10n.settingsPresetConcise, l10n.settingsPresetTranslate],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(postProcessPreset: v!)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.server,
                  label: l10n.settingsService,
                  trailing: _dropdown(
                    value: settings.postProcessProvider,
                    items: const [
                      'Local',
                      'OpenAI',
                      'Anthropic',
                      'Groq',
                    ],
                    labels: [
                      l10n.statusLocal,
                      'OpenAI',
                      'Anthropic',
                      'Groq',
                    ],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(postProcessProvider: v!)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ═══════════════════════════════════════════════════════
          //  DISPLAY & FEEDBACK — sensory output settings
          // ═══════════════════════════════════════════════════════

          // ── 5. Sound & Feedback ──
          WpSection(
            title: l10n.settingsSoundFeedback,
            subtitle: l10n.settingsSoundFeedbackSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.volume2,
                  label: l10n.settingsRecordStartSound,
                  trailing: _toggle(
                    value: settings.recordStartSound,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(recordStartSound: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.volumeX,
                  label: l10n.settingsRecordStopSound,
                  trailing: _toggle(
                    value: settings.recordStopSound,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(recordStopSound: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.bellRing,
                  label: l10n.settingsTranscriptionCompleteSound,
                  trailing: _toggle(
                    value: settings.transcriptionCompleteSound,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) =>
                            s.copyWith(transcriptionCompleteSound: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.volume1,
                  label: l10n.settingsSoundVolume,
                  trailing: _slider(
                    value: settings.soundVolume,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    valueLabel: '${settings.soundVolume.round()}%',
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(soundVolume: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.clipboardCheck,
                  label: l10n.settingsAfterTranscription,
                  subtitle: l10n.settingsAfterTranscriptionSubtitle,
                  trailing: _dropdown(
                    value: settings.afterTranscription,
                    items: const ['clipboard', 'paste', 'clipboard_and_paste', 'nothing'],
                    labels: [
                      l10n.settingsAfterTranscriptionClipboard,
                      l10n.settingsAfterTranscriptionPaste,
                      l10n.settingsAfterTranscriptionBoth,
                      l10n.settingsAfterTranscriptionNothing,
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref
                          .read(settingsProvider.notifier)
                          .updateSettings(
                              (s) => s.copyWith(afterTranscription: v));
                    },
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 6. Overlay & Floating Button ──
          WpSection(
            title: l10n.settingsOverlayFloatingButton,
            subtitle: l10n.settingsOverlayFloatingButtonSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.layers,
                  label: l10n.settingsShowOverlay,
                  trailing: _toggle(
                    value: settings.showOverlay,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(showOverlay: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.move,
                  label: l10n.settingsShowFloatingButton,
                  trailing: _toggle(
                    value: settings.showFloatingButton,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(showFloatingButton: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.circleDot,
                  label: l10n.settingsFloatingButtonOpacity,
                  trailing: _slider(
                    value: settings.floatingButtonOpacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    valueLabel:
                        '${(settings.floatingButtonOpacity * 100).round()}%',
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                            (s) => s.copyWith(floatingButtonOpacity: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.maximize2,
                  label: l10n.settingsFloatingButtonSize,
                  trailing: _dropdown(
                    value: settings.floatingButtonSize,
                    items: const ['Small', 'Normal', 'Large'],
                    labels: [l10n.settingsSizeSmall, l10n.settingsSizeNormal, l10n.settingsSizeLarge],
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                            (s) => s.copyWith(floatingButtonSize: v!)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ═══════════════════════════════════════════════════════
          //  GENERAL — app-wide preferences
          // ═══════════════════════════════════════════════════════

          // ── 7. Interface ──
          WpSection(
            title: l10n.settingsInterface,
            subtitle: l10n.settingsInterfaceSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.palette,
                  label: l10n.settingsTheme,
                  trailing: _dropdown(
                    value: switch (settings.themeMode) {
                      ThemeMode.dark => 'dark',
                      ThemeMode.light => 'light',
                      ThemeMode.system => 'system',
                    },
                    items: const ['dark', 'light', 'system'],
                    labels: [
                      l10n.settingsThemeDark,
                      l10n.settingsThemeLight,
                      l10n.settingsThemeSystem,
                    ],
                    onChanged: (v) {
                      final mode = switch (v) {
                        'light' => ThemeMode.light,
                        'system' => ThemeMode.system,
                        _ => ThemeMode.dark,
                      };
                      ref.read(settingsProvider.notifier).updateSettings(
                        (s) => s.copyWith(themeMode: mode),
                      );
                    },
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.globe,
                  label: l10n.settingsLanguage,
                  trailing: _dropdown(
                    value: settings.locale == 'de' ? 'de' : 'en',
                    items: const ['en', 'de'],
                    labels: [
                      l10n.settingsLanguageEnglish,
                      l10n.settingsLanguageGerman,
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(settingsProvider.notifier).updateSettings(
                          (s) => s.copyWith(locale: v),
                        );
                      }
                    },
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.power,
                  label: l10n.settingsLaunchAtStartup,
                  trailing: _toggle(
                    value: settings.launchAtStartup,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(launchAtStartup: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.bell,
                  label: l10n.settingsShowNotifications,
                  trailing: _toggle(
                    value: settings.showNotifications,
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                            (s) => s.copyWith(showNotifications: v)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 8. Cloud Providers (advanced — at bottom) ──
          WpSection(
            title: l10n.settingsCloudProviders,
            subtitle: l10n.settingsCloudProvidersSubtitle,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.keyRound,
                  label: l10n.settingsOpenAiApiKey,
                  trailing: _apiKeyField(
                    controller: _openAiKeyCtrl,
                    obscure: !_showOpenAiKey,
                    onToggle: () => setState(
                      () => _showOpenAiKey = !_showOpenAiKey,
                    ),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(openAiApiKey: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.keyRound,
                  label: l10n.settingsGroqApiKey,
                  trailing: _apiKeyField(
                    controller: _groqKeyCtrl,
                    obscure: !_showGroqKey,
                    onToggle: () => setState(
                      () => _showGroqKey = !_showGroqKey,
                    ),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(groqApiKey: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.keyRound,
                  label: l10n.settingsDeepgramApiKey,
                  trailing: _apiKeyField(
                    controller: _deepgramKeyCtrl,
                    obscure: !_showDeepgramKey,
                    onToggle: () => setState(
                      () => _showDeepgramKey = !_showDeepgramKey,
                    ),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(deepgramApiKey: v)),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.keyRound,
                  label: l10n.settingsAnthropicApiKey,
                  trailing: _apiKeyField(
                    controller: _anthropicKeyCtrl,
                    obscure: !_showAnthropicKey,
                    onToggle: () => setState(
                      () => _showAnthropicKey = !_showAnthropicKey,
                    ),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .updateSettings((s) => s.copyWith(anthropicApiKey: v)),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 9. Advanced — Factory Reset ──
          WpSection(
            title: l10n.settingsAdvanced,
            padding: EdgeInsets.zero,
            child: _SettingRow(
              icon: LucideIcons.rotateCcw,
              label: l10n.settingsResetToDefaults,
              trailing: OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(l10n.settingsResetDialogTitle),
                      content: Text(l10n.settingsResetConfirmMessage),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: Text(l10n.actionCancel),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: Text(l10n.settingsResetConfirm),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) {
                    return;
                  }

                  await ref
                      .read(settingsProvider.notifier)
                      .resetToDefaults();
                  if (!context.mounted) return;
                  final resetSuccessText = L10n.of(context).settingsResetSuccess;

                  setState(() {
                    _showOpenAiKey = false;
                    _showGroqKey = false;
                    _showDeepgramKey = false;
                    _showAnthropicKey = false;
                  });
                  if (context.mounted) {
                    WpToast.show(
                      context,
                      message: resetSuccessText,
                      type: WpToastType.success,
                    );
                  }
                },
                child: Text(l10n.settingsResetConfirm),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single setting row — icon, label, and trailing control widget.
class _SettingRow extends StatefulWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.trailing,
    // ignore: unused_element_parameter
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final Widget trailing;
  final String? subtitle;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      label: widget.label,
      hint: widget.subtitle,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: WpMotion.hoverIn,
          curve: WpMotion.defaultCurve,
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.sm,
            vertical: WpSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _isHovered
                ? (isDark ? WpColorsDark.hover : WpColorsLight.hover)
                : (isDark ? WpColorsDark.hoverTransparent : WpColorsLight.hoverTransparent),
            borderRadius: WpRadius.borderSm,
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
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
                      widget.label,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (widget.subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.subtitle!,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? WpColorsDark.textMuted
                                : WpColorsLight.textMuted,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              widget.trailing,
            ],
          ),
        ),
      ),
    );
  }
}
