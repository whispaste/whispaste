/// Local Automation API settings section (ticket 03,
/// `.scratch/local-automation-api/`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../services/automation_api/automation_api_controller.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/section.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_text_field.dart';
import '../settings_widgets.dart';

final _log = AppLogger('AutomationApiSection');

/// GitHub blob URL of `AUTOMATION_API.md` — the full endpoint reference
/// this section's "Documentation" link opens.
const String kAutomationApiDocsUrl =
    '$kGitHubRepoUrl/blob/main/AUTOMATION_API.md';

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
              onChanged: (v) {
                _log.info('user toggled automationApi.enabled=$v');
                ref
                    .read(settingsProvider.notifier)
                    .updateSettings(
                      (s) => s.copyWithSections(
                        automationApi: s.automationApi.copyWith(enabled: v),
                      ),
                    );
              },
            ),
          ),
          settingsInlineBreak,
          _CustomPortField(initialValue: settings.automationApi.customPort),
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
          settingsInlineBreak,
          SettingRow(
            icon: LucideIcons.bookOpen,
            label: l10n.settingsAutomationApiDocumentation,
            subtitle: l10n.settingsAutomationApiDocumentationSubtitle,
            trailing: WpButton(
              label: l10n.settingsAutomationApiDocumentationAction,
              variant: WpButtonVariant.secondary,
              onPressed: _openDocumentation,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDocumentation() async {
    final uri = Uri.parse(kAutomationApiDocsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _statusLabel(L10n l10n, AutomationApiState state) =>
      switch (state.runState) {
        AutomationApiRunState.running =>
          state.port != null && state.port != state.requestedPort
              ? l10n.settingsAutomationApiStatusRunningFallback(
                  state.port!,
                  state.requestedPort ?? state.port!,
                )
              : l10n.settingsAutomationApiStatusRunning(state.port ?? 0),
        AutomationApiRunState.stopped =>
          l10n.settingsAutomationApiStatusStopped,
        AutomationApiRunState.error => l10n.settingsAutomationApiStatusError(
          state.requestedPort ?? kAutomationApiDefaultPort,
          (state.requestedPort ?? kAutomationApiDefaultPort) +
              kAutomationApiPortFallbackAttempts -
              1,
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

/// Lowest/highest port [AutomationApiSettings.customPort] accepts — ports
/// below 1024 are privileged and locally meaningless anyway.
const kAutomationApiCustomPortMin = 1024;
const kAutomationApiCustomPortMax = 65535;

/// Validates raw text-field input for [AutomationApiSettings.customPort].
/// Empty input is valid (→ "automatic" / `null`); otherwise the value must
/// be a plain integer within [kAutomationApiCustomPortMin]–
/// [kAutomationApiCustomPortMax]. Exposed standalone so it can be unit
/// tested without mounting the widget.
bool isValidAutomationApiCustomPortInput(String value) {
  if (value.isEmpty) return true;
  final parsed = int.tryParse(value);
  return parsed != null &&
      parsed >= kAutomationApiCustomPortMin &&
      parsed <= kAutomationApiCustomPortMax;
}

// ---------------------------------------------------------------------------
// Custom port text field
// ---------------------------------------------------------------------------

class _CustomPortField extends ConsumerStatefulWidget {
  const _CustomPortField({required this.initialValue});

  final int? initialValue;

  @override
  ConsumerState<_CustomPortField> createState() => _CustomPortFieldState();
}

class _CustomPortFieldState extends ConsumerState<_CustomPortField> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue?.toString() ?? '');
  }

  @override
  void didUpdateWidget(covariant _CustomPortField old) {
    super.didUpdateWidget(old);
    final text = widget.initialValue?.toString() ?? '';
    if (old.initialValue != widget.initialValue && _ctrl.text != text) {
      _ctrl.text = text;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    if (!isValidAutomationApiCustomPortInput(value)) {
      setState(
        () => _error = L10n.of(context).settingsAutomationApiCustomPortInvalid,
      );
      return;
    }
    setState(() => _error = null);
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            automationApi: s.automationApi.copyWith(
              customPort: value.isEmpty ? null : int.parse(value),
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingRow(
      icon: LucideIcons.hash,
      label: l10n.settingsAutomationApiCustomPortLabel,
      subtitle: _error ?? l10n.settingsAutomationApiCustomPortSubtitle,
      trailing: SizedBox(
        width: 120,
        child: WpTextField(
          controller: _ctrl,
          variant: WpTextFieldVariant.form,
          semanticsLabel: l10n.settingsAutomationApiCustomPortLabel,
          hintText: l10n.settingsAutomationApiCustomPortHint,
          onChanged: _onChanged,
        ),
      ),
    );
  }
}
