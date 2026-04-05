import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
  // -- Audio --
  String _microphone = 'Default';
  double _inputGain = 100;
  bool _pushToTalk = false;

  // -- Recording Safety --
  double _deadMicTimeout = 3;
  double _autoStopSilence = 0;

  // -- Post-Processing --
  bool _postProcessEnabled = true;
  String _postProcessPreset = 'Clean up';
  String _postProcessProvider = 'Local';

  // -- Speech Recognition --
  String _sttProvider = 'On Device (Private)';
  String _sttModel = 'High Quality (Medium)';
  String _sttLanguage = 'Auto-detect';

  // -- Interface --
  String _uiLanguage = 'English';
  bool _launchAtStartup = false;
  bool _showNotifications = true;

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
              .map(
                (e) => DropdownMenuItem(value: e, child: Text(e)),
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
    if (v == 0) return 'Off';
    return '${v.round()}s';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WpPageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Privacy note
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
                    'Your recordings and text stay on your device by default. '
                    'Cloud services are only used when you explicitly enable them.',
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

          // — Audio —
          WpSection(
            title: 'Audio',
            subtitle: 'Microphone and recording',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.mic,
                  label: 'Microphone',
                  trailing: _dropdown(
                    value: _microphone,
                    items: const ['Default', 'Headset Mic', 'USB Mic'],
                    onChanged: (v) =>
                        setState(() => _microphone = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.gauge,
                  label: 'Microphone Volume',
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
                  label: 'Hold to Record',
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

          // — Recording Safety —
          WpSection(
            title: 'Recording Safety',
            subtitle: 'Automatic checks and safeguards',
            padding: EdgeInsets.zero,
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.shieldAlert,
                  label: 'Silent Mic Detection',
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
                  label: 'Auto-Stop After Silence',
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

          // — Text Enhancement (Post-Processing) —
          WpSection(
            title: 'Text Enhancement',
            subtitle: 'Improve your dictated text automatically',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.sparkles,
                  label: 'Enabled',
                  trailing: _toggle(
                    value: _postProcessEnabled,
                    onChanged: (v) =>
                        setState(() => _postProcessEnabled = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.wandSparkles,
                  label: 'Style',
                  trailing: _dropdown(
                    value: _postProcessPreset,
                    items: const ['Clean up', 'Concise', 'Translate'],
                    onChanged: (v) =>
                        setState(() => _postProcessPreset = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.server,
                  label: 'Service',
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

          // — Speech Recognition —
          WpSection(
            title: 'Speech Recognition',
            subtitle: 'Voice recognition quality and service',
            padding: EdgeInsets.zero,
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.cpu,
                  label: 'Service',
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
                  label: 'Quality',
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
                  label: 'Language',
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

          // — Interface —
          WpSection(
            title: 'Interface',
            subtitle: 'Appearance and behavior',
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.palette,
                  label: 'Theme',
                  trailing: _dropdown(
                    value: switch (ref.watch(themeModeProvider)) {
                      ThemeMode.dark => 'Dark',
                      ThemeMode.light => 'Light',
                      ThemeMode.system => 'System',
                    },
                    items: const ['Dark', 'Light', 'System'],
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
                  label: 'Language',
                  trailing: _dropdown(
                    value: _uiLanguage,
                    items: const ['English', 'Deutsch'],
                    onChanged: (v) =>
                        setState(() => _uiLanguage = v!),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.power,
                  label: 'Launch at Startup',
                  trailing: _toggle(
                    value: _launchAtStartup,
                    onChanged: (v) =>
                        setState(() => _launchAtStartup = v),
                  ),
                ),
                _SettingRow(
                  icon: LucideIcons.bell,
                  label: 'Show Notifications',
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

          // — Cloud Providers —
          WpSection(
            title: 'Cloud Providers',
            subtitle: 'API keys for online services',
            padding: EdgeInsets.zero,
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.keyRound,
                  label: 'OpenAI API Key',
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
                  label: 'Groq API Key',
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
                  label: 'Deepgram API Key',
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
                  label: 'Anthropic API Key',
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
          duration: _isHovered ? WpMotion.fast : WpMotion.hoverOut,
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
