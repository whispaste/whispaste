/// Cloud Providers & Advanced settings sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_enums.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/data/analytics_provider.dart';
import '../../../core/data/history_providers.dart';
import '../../../app.dart' show activePageProvider;
import '../../../services/hardware_info_service.dart';
import '../../../services/model_download_service.dart';
import '../../../services/stt_service.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../settings_widgets.dart';

// ---------------------------------------------------------------------------
// Cloud Providers section (stateful — needs TextEditingControllers)
// ---------------------------------------------------------------------------

class CloudProvidersSection extends ConsumerStatefulWidget {
  const CloudProvidersSection({super.key});

  @override
  ConsumerState<CloudProvidersSection> createState() =>
      _CloudProvidersSectionState();
}

class _CloudProvidersSectionState extends ConsumerState<CloudProvidersSection> {
  final _openAiKeyCtrl = TextEditingController();
  final _groqKeyCtrl = TextEditingController();
  final _deepgramKeyCtrl = TextEditingController();

  bool _showOpenAiKey = false;
  bool _showGroqKey = false;
  bool _showDeepgramKey = false;

  @override
  void dispose() {
    _openAiKeyCtrl.dispose();
    _groqKeyCtrl.dispose();
    _deepgramKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    syncController(_openAiKeyCtrl, settings.openAiApiKey);
    syncController(_groqKeyCtrl, settings.groqApiKey);
    syncController(_deepgramKeyCtrl, settings.deepgramApiKey);

    return WpSection(
      title: l10n.settingsCloudProviders,
      subtitle: l10n.settingsCloudProvidersSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.keyRound,
            label: l10n.settingsOpenAiApiKey,
            trailing: settingsApiKeyField(
              context: context,
              controller: _openAiKeyCtrl,
              obscure: !_showOpenAiKey,
              onToggle: () => setState(() => _showOpenAiKey = !_showOpenAiKey),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(openAiApiKey: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.keyRound,
            label: l10n.settingsGroqApiKey,
            trailing: settingsApiKeyField(
              context: context,
              controller: _groqKeyCtrl,
              obscure: !_showGroqKey,
              onToggle: () => setState(() => _showGroqKey = !_showGroqKey),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(groqApiKey: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.keyRound,
            label: l10n.settingsDeepgramApiKey,
            trailing: settingsApiKeyField(
              context: context,
              controller: _deepgramKeyCtrl,
              obscure: !_showDeepgramKey,
              onToggle: () =>
                  setState(() => _showDeepgramKey = !_showDeepgramKey),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(deepgramApiKey: v)),
            ),
          ),
          if (!settings.sttProviderType.isLocal)
            SettingRow(
              icon: LucideIcons.audioLines,
              label: l10n.settingsDefaultSttProvider,
              subtitle: l10n.settingsDefaultSttProviderSubtitle,
              trailing: settingsDropdown(
                context: context,
                value: settings.cloudSttProvider,
                items: CloudSttProvider.values.map((e) => e.value).toList(),
                labels: const ['OpenAI', 'Groq', 'Deepgram'],
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateSettings((s) => s.copyWith(cloudSttProvider: v!)),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Advanced section
// ---------------------------------------------------------------------------

class AdvancedSection extends ConsumerWidget {
  const AdvancedSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;

    return WpSection(
      title: l10n.settingsAdvanced,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.shieldCheck,
            label: l10n.settingsErrorReporting,
            subtitle: l10n.settingsErrorReportingSubtitle,
            trailing: settingsToggle(
              value: settings.errorReporting,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings((s) => s.copyWith(errorReporting: v)),
            ),
          ),
          SettingRow(
            icon: LucideIcons.rotateCcw,
            label: l10n.settingsResetToDefaults,
            trailing: OutlinedButton(
              onPressed: () => _confirmReset(context, ref),
              child: Text(l10n.settingsResetConfirm),
            ),
          ),
          SettingRow(
            icon: LucideIcons.trash2,
            label: l10n.settingsFactoryReset,
            trailing: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
              onPressed: () => _confirmFactoryReset(context, ref),
              child: Text(l10n.settingsFactoryResetConfirm),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsResetTitle,
      message: l10n.settingsResetMessage,
      confirmLabel: l10n.settingsResetConfirm,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;

    await ref.read(settingsProvider.notifier).resetToDefaults();
    if (!context.mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).settingsResetSuccess,
      type: WpToastType.success,
    );
  }

  Future<void> _confirmFactoryReset(BuildContext context, WidgetRef ref) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsFactoryResetTitle,
      message: l10n.settingsFactoryResetMessage,
      confirmLabel: l10n.settingsFactoryResetConfirm,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;

    // Stop whisper-server subprocess and wait for exit before deleting files.
    try {
      ref.read(sttServiceProvider.notifier).stop();
      // Give the process time to release file handles on Windows.
      await Future<void>.delayed(const Duration(milliseconds: 800));
    } catch (_) {}

    // Clear GPU detection cache.
    clearGpuCache();

    await ref.read(settingsProvider.notifier).factoryReset();

    // Invalidate all data-backed providers so UI reflects the empty state.
    ref.invalidate(historyEntriesProvider);
    ref.invalidate(archivedEntriesProvider);
    ref.invalidate(trashEntriesProvider);
    ref.invalidate(analyticsProvider);
    ref.invalidate(modelDownloadProvider);

    // Navigate back to history page so the onboarding overlay is visible.
    ref.read(activePageProvider.notifier).setPage('history');

    if (!context.mounted) return;
    WpToast.show(
      context,
      message: L10n.of(context).settingsFactoryResetSuccess,
      type: WpToastType.success,
    );
  }
}
