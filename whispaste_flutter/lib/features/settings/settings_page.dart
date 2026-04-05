import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/l10n/locale_provider.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/theme_provider.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/section.dart';

/// Settings page — organized sections with interactive controls.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  // -- Interface --
  bool _launchAtStartup = false;
  bool _showNotifications = true;

  // -- Audio --
  String _microphone = 'Default';
  double _inputGain = 100;
  bool _pushToTalk = false;

  // -- Speech Recognition --
  String _sttProvider = 'On Device (Private)';
  String _sttModel = 'High Quality (Medium)';
  String _sttLanguage = 'Auto-detect';

  // -- Text Enhancement (Post-Processing) --
  bool _postProcessEnabled = true;
  String _postProcessPreset = 'Clean up';
  String _postProcessProvider = 'Local';

  // -- Recording Safety --
  double _deadMicTimeout = 3;
  double _autoStopSilence = 0;

  // -- Sound & Feedback --
  bool _recordStartSound = true;
  bool _recordStopSound = true;
  bool _transcriptionCompleteSound = true;

  // -- Overlay & Floating Button --
  bool _showOverlay = true;
  bool _showFloatingButton = true;
  double _floatingButtonOpacity = 0.9;
  String _floatingButtonSize = 'Normal';

  // -- Cloud Providers --
  final _openAiKeyCtrl = TextEditingController();
  final _groqKeyCtrl = TextEditingController();
  final _deepgramKeyCtrl = TextEditingController();
  final _anthropicKeyCtrl = TextEditingController();
  bool _showOpenAiKey = false;
  bool _showGroqKey = false;
  bool _showDeepgramKey = false;
  bool _showAnthropicKey = false;

  @override
  void dispose() {
    _openAiKeyCtrl.dispose();
    _groqKeyCtrl.dispose();
    _deepgramKeyCtrl.dispose();
    _anthropicKeyCtrl.dispose();
    super.dispose();
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
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 280,
      height: 34,
      child: TextField(
        controller: controller,
        obscureText: obscure,
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
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = L10n.of(context);

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
                    value: _microphone,
                    items: const ['Default', 'Headset Mic', 'USB Mic'],
                    onChanged: (v) =>
                        setState(() => _microphone = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.gauge,
                  label: l10n.settingsGain,
                  trailing: _slider(
                    value: _inputGain,
                    min: 0,
                    max: 300,
                    divisions: 60,
                    valueLabel: '${_inputGain.round()}%',
                    onChanged: (v) =>
                        setState(() => _inputGain = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.hand,
                  label: l10n.settingsHoldToRecord,
                  trailing: _toggle(
                    value: _pushToTalk,
                    onChanged: (v) =>
                        setState(() => _pushToTalk = v),
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
                    value: _deadMicTimeout,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    valueLabel: _fmtSeconds(_deadMicTimeout),
                    onChanged: (v) =>
                        setState(() => _deadMicTimeout = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.timerOff,
                  label: l10n.settingsAutoStopSilence,
                  trailing: _slider(
                    value: _autoStopSilence,
                    min: 0,
                    max: 10,
                    divisions: 10,
                    valueLabel: _fmtSeconds(_autoStopSilence),
                    onChanged: (v) =>
                        setState(() => _autoStopSilence = v),
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
                    value: _sttProvider,
                    items: const [
                      'On Device (Private)',
                      'OpenAI',
                      'Groq',
                      'Deepgram',
                    ],
                    onChanged: (v) =>
                        setState(() => _sttProvider = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.brain,
                  label: l10n.settingsQuality,
                  trailing: _dropdown(
                    value: _sttModel,
                    items: const [
                      'Fast (Tiny)',
                      'Balanced (Small)',
                      'High Quality (Medium)',
                      'Best Quality (Large)',
                    ],
                    onChanged: (v) =>
                        setState(() => _sttModel = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.languages,
                  label: l10n.settingsLanguage,
                  trailing: _dropdown(
                    value: _sttLanguage,
                    items: const [
                      'Auto-detect',
                      'English',
                      'German',
                      'French',
                      'Spanish',
                    ],
                    onChanged: (v) =>
                        setState(() => _sttLanguage = v!),
                  ),
                ),
              ],
            ),
          ),
          _sectionDivider(),

          // ── 4. Text Enhancement ──
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
                    value: _postProcessEnabled,
                    onChanged: (v) =>
                        setState(() => _postProcessEnabled = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.wandSparkles,
                  label: l10n.settingsStyle,
                  trailing: _dropdown(
                    value: _postProcessPreset,
                    items: const ['Clean up', 'Concise', 'Translate'],
                    labels: [l10n.settingsPresetCleanup, l10n.settingsPresetConcise, l10n.settingsPresetTranslate],
                    onChanged: (v) =>
                        setState(() => _postProcessPreset = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.server,
                  label: l10n.settingsService,
                  trailing: _dropdown(
                    value: _postProcessProvider,
                    items: const [
                      'Local',
                      'OpenAI',
                      'Anthropic',
                      'Groq',
                    ],
                    onChanged: (v) =>
                        setState(() => _postProcessProvider = v!),
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
                    value: _recordStartSound,
                    onChanged: (v) =>
                        setState(() => _recordStartSound = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.volumeX,
                  label: l10n.settingsRecordStopSound,
                  trailing: _toggle(
                    value: _recordStopSound,
                    onChanged: (v) =>
                        setState(() => _recordStopSound = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.bellRing,
                  label: l10n.settingsTranscriptionCompleteSound,
                  trailing: _toggle(
                    value: _transcriptionCompleteSound,
                    onChanged: (v) =>
                        setState(() => _transcriptionCompleteSound = v),
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
                    value: _showOverlay,
                    onChanged: (v) =>
                        setState(() => _showOverlay = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.move,
                  label: l10n.settingsShowFloatingButton,
                  trailing: _toggle(
                    value: _showFloatingButton,
                    onChanged: (v) =>
                        setState(() => _showFloatingButton = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.circleDot,
                  label: l10n.settingsFloatingButtonOpacity,
                  trailing: _slider(
                    value: _floatingButtonOpacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    valueLabel:
                        '${(_floatingButtonOpacity * 100).round()}%',
                    onChanged: (v) =>
                        setState(() => _floatingButtonOpacity = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.maximize2,
                  label: l10n.settingsFloatingButtonSize,
                  trailing: _dropdown(
                    value: _floatingButtonSize,
                    items: const ['Small', 'Normal', 'Large'],
                    labels: [l10n.settingsSizeSmall, l10n.settingsSizeNormal, l10n.settingsSizeLarge],
                    onChanged: (v) =>
                        setState(() => _floatingButtonSize = v!),
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
                    value: switch (ref.watch(themeModeProvider)) {
                      ThemeMode.dark => 'Dark',
                      ThemeMode.light => 'Light',
                      ThemeMode.system => 'System',
                    },
                    items: const ['Dark', 'Light', 'System'],
                    labels: [l10n.settingsThemeDark, l10n.settingsThemeLight, l10n.settingsThemeSystem],
                    onChanged: (v) {
                      final mode = switch (v) {
                        'Light' => ThemeMode.light,
                        'System' => ThemeMode.system,
                        _ => ThemeMode.dark,
                      };
                      ref.read(themeModeProvider.notifier).setTheme(mode);
                    },
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.globe,
                  label: l10n.settingsLanguage,
                  trailing: _dropdown(
                    value: ref.watch(localeProvider).languageCode == 'de'
                        ? 'Deutsch'
                        : 'English',
                    items: const ['English', 'Deutsch'],
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(localeProvider.notifier).setFromDisplayName(v);
                      }
                    },
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.power,
                  label: l10n.settingsLaunchAtStartup,
                  trailing: _toggle(
                    value: _launchAtStartup,
                    onChanged: (v) =>
                        setState(() => _launchAtStartup = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.bell,
                  label: l10n.settingsShowNotifications,
                  trailing: _toggle(
                    value: _showNotifications,
                    onChanged: (v) =>
                        setState(() => _showNotifications = v),
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
                  ),
                ),
              ],
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
          duration: _isHovered ? WpMotion.hoverIn : WpMotion.hoverOut,
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
