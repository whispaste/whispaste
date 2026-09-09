/// Local Automation API settings section (ticket 03,
/// `.scratch/local-automation-api/`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../services/automation_api/automation_api_controller.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../settings_widgets.dart';

class AutomationApiSection extends ConsumerWidget {
  const AutomationApiSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final apiState = ref.watch(automationApiControllerProvider);
    final enabled = settings.automationApi.enabled;

    return WpSection(
      title: l10n.settingsAutomationApi,
      subtitle: l10n.settingsAutomationApiSubtitle,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          SettingRow(
            icon: LucideIcons.terminal,
            label: l10n.settingsAutomationApiEnable,
            subtitle: l10n.settingsAutomationApiEnableSubtitle,
            semanticToggledValue: enabled,
            trailing: settingsToggle(
              value: enabled,
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .updateSettings(
                    (s) => s.copyWithSections(
                      automationApi: s.automationApi.copyWith(enabled: v),
                    ),
                  ),
            ),
          ),
          if (enabled) ...[
            settingsInlineBreak,
            SettingRow(
              icon: LucideIcons.activity,
              label: _statusLabel(l10n, apiState),
              trailing: const SizedBox.shrink(),
            ),
            if (apiState.token != null) ...[
              settingsInlineBreak,
              SettingRow(
                icon: LucideIcons.key,
                label: l10n.settingsAutomationApiToken,
                subtitle: l10n.settingsAutomationApiTokenSubtitle,
                trailingHugsLabel: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: SelectableText(
                        apiState.token!,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: WpColors.textMuted,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.copy, size: 16),
                      tooltip: l10n.settingsAutomationApiCopyToken,
                      onPressed: () =>
                          _copyToken(context, apiState.token!, l10n),
                    ),
                    WpButton(
                      label: l10n.settingsAutomationApiRegenerate,
                      variant: WpButtonVariant.secondary,
                      onPressed: () => _confirmRegenerate(context, ref, l10n),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _statusLabel(L10n l10n, AutomationApiState state) =>
      switch (state.runState) {
        AutomationApiRunState.running =>
          l10n.settingsAutomationApiStatusRunning(state.port ?? 0),
        AutomationApiRunState.stopped =>
          l10n.settingsAutomationApiStatusStopped,
        AutomationApiRunState.error => l10n.settingsAutomationApiStatusError(
          kAutomationApiDefaultPort,
        ),
      };

  void _copyToken(BuildContext context, String token, L10n l10n) {
    Clipboard.setData(ClipboardData(text: token));
    WpToast.show(
      context,
      message: l10n.settingsAutomationApiTokenCopied,
      type: WpToastType.success,
    );
  }

  Future<void> _confirmRegenerate(
    BuildContext context,
    WidgetRef ref,
    L10n l10n,
  ) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsAutomationApiRegenerateConfirmTitle,
      message: l10n.settingsAutomationApiRegenerateConfirmMessage,
      confirmLabel: l10n.settingsAutomationApiRegenerate,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;

    await ref.read(automationApiControllerProvider.notifier).regenerateToken();
  }
}
