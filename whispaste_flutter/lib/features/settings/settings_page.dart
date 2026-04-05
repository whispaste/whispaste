import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/section.dart';

/// Settings page — organized sections with clean setting rows.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: WpSpacing.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WpSection(
            title: 'Audio',
            subtitle: 'Microphone and input settings',
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.mic,
                  label: 'Microphone',
                  value: 'Default',
                ),
                _SettingRow(
                  icon: LucideIcons.gauge,
                  label: 'Input Gain',
                  value: '100%',
                ),
              ],
            ),
          ),
          _sectionDivider(context),
          const WpSection(
            title: 'Recording Safety',
            subtitle: 'Auto-detection and auto-stop',
            collapsible: true,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.shieldAlert,
                  label: 'Dead Mic Timeout',
                  value: '3s',
                ),
                _SettingRow(
                  icon: LucideIcons.timerOff,
                  label: 'Auto-Stop on Silence',
                  value: 'Off',
                ),
              ],
            ),
          ),
          _sectionDivider(context),
          WpSection(
            title: 'Post-Processing',
            subtitle: 'AI text enhancement after transcription',
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.sparkles,
                  label: 'Enabled',
                  value: 'On',
                  trailing: Switch(value: true, onChanged: (_) {}),
                ),
                const _SettingRow(
                  icon: LucideIcons.wand2,
                  label: 'Preset',
                  value: 'Clean up',
                ),
              ],
            ),
          ),
          _sectionDivider(context),
          const WpSection(
            title: 'Speech Recognition',
            subtitle: 'STT engine and model selection',
            collapsible: true,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.cpu,
                  label: 'Provider',
                  value: 'Local',
                ),
                _SettingRow(
                  icon: LucideIcons.brain,
                  label: 'Model',
                  value: 'Whisper Medium',
                ),
              ],
            ),
          ),
          _sectionDivider(context),
          const WpSection(
            title: 'Cloud Providers',
            subtitle: 'API keys for online services',
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              children: [
                _SettingRow(
                  icon: LucideIcons.cloud,
                  label: 'OpenAI',
                  value: 'Not configured',
                  valueColor: true,
                ),
                _SettingRow(
                  icon: LucideIcons.cloud,
                  label: 'Groq',
                  value: 'Not configured',
                  valueColor: true,
                ),
                _SettingRow(
                  icon: LucideIcons.cloud,
                  label: 'Deepgram',
                  value: 'Not configured',
                  valueColor: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionDivider(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: WpSpacing.xl),
      child: Divider(
        color: isDark ? WpColorsDark.borderSubtle : WpColorsLight.borderSubtle,
      ),
    );
  }
}

/// A single setting row — icon, label, value, optional trailing widget.
class _SettingRow extends StatefulWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.valueColor = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final bool valueColor;

  @override
  State<_SettingRow> createState() => _SettingRowState();
}

class _SettingRowState extends State<_SettingRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: WpMotion.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: WpSpacing.sm,
          vertical: WpSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: _isHovered
              ? (isDark ? WpColorsDark.hover : WpColorsLight.hover)
              : Colors.transparent,
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
              child: Text(
                widget.label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (widget.trailing != null)
              widget.trailing!
            else
              Text(
                widget.value,
                style: TextStyle(
                  color: widget.valueColor
                      ? (isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted)
                      : cs.secondary,
                  fontSize: 13,
                ),
              ),
            const SizedBox(width: WpSpacing.xxs),
            Icon(
              LucideIcons.chevronRight,
              size: WpIconSize.xs,
              color: isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
