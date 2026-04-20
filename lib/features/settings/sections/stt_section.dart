/// Speech Recognition settings section — unified tier-based UI.
///
/// When local STT is selected, shows quality tier cards (compact/balanced/
/// premium) with one-click download. When a cloud provider is selected,
/// shows the relevant API key inline for convenience.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/stt_service.dart';
import '../../../widgets/model_download_card.dart';
import '../../../widgets/section.dart';
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

    return WpSection(
      title: l10n.settingsSpeechRecognition,
      subtitle: l10n.settingsSpeechRecognitionSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          // Provider selector (On-device / OpenAI / Groq / Deepgram)
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
                'Groq',
                'Deepgram',
              ],
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(sttProvider: v!)),
            ),
          ),

          // ----- Local mode: tier cards + model management ------------------
          if (isLocal) ...[
            const SizedBox(height: WpSpacing.xs),
            const SttModelManager(),
            const SizedBox(height: WpSpacing.xs),
            // Re-run benchmark button
            _BenchmarkButton(l10n: l10n, ref: ref),
            const Divider(height: 24),
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

          // Language selector (shared)
          SettingRow(
            icon: LucideIcons.languages,
            label: l10n.settingsRecognitionLanguage,
            trailing: settingsDropdown(
              context: context,
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
      SttProviderType.groq => (
        l10n.settingsGroqApiKey,
        settings.groqApiKey,
        (String v) => ref
            .read(settingsProvider.notifier)
            .updateSettings((s) => s.copyWith(groqApiKey: v)),
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
    final sttStatus = ref.watch(sttServiceProvider);
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
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              onPressed: () {
                ref.read(sttServiceProvider.notifier).runBenchmark();
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
