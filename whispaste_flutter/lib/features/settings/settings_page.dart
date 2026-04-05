import 'package:flutter/material.dart';
import '../../widgets/section.dart';

/// Settings page — flat sections for audio, STT, post-processing, cloud, UI.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WpSection(
            title: 'Audio',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingRow(context, 'Microphone', 'Default'),
                _settingRow(context, 'Input Gain', '100%'),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          WpSection(
            title: 'Recording Safety',
            collapsible: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingRow(context, 'Dead Mic Timeout', '3s'),
                _settingRow(context, 'Auto-Stop on Silence', 'Off'),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          WpSection(
            title: 'Post-Processing',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingRow(context, 'Enabled', 'On'),
                _settingRow(context, 'Preset', 'Clean up'),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          WpSection(
            title: 'Speech Recognition',
            collapsible: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingRow(context, 'Provider', 'Local'),
                _settingRow(context, 'Model', 'Whisper Medium'),
              ],
            ),
          ),
          const Divider(indent: 20, endIndent: 20),
          WpSection(
            title: 'Cloud Providers',
            collapsible: true,
            initiallyExpanded: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _settingRow(context, 'OpenAI', 'Not configured'),
                _settingRow(context, 'Groq', 'Not configured'),
                _settingRow(context, 'Deepgram', 'Not configured'),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _settingRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(value, style: TextStyle(color: cs.secondary, fontSize: 14)),
        ],
      ),
    );
  }
}
