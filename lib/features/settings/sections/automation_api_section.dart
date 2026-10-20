/// Local Automation API settings section (ticket 03,
/// `.scratch/local-automation-api/`).
library;

import '../../../widgets/external_link.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/automation_api/automation_api_controller.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/toast.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_text_field.dart';
import '../settings_widgets.dart';
import '../widgets/automation_integrations.dart';
import '../widgets/wp_settings_group.dart';

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

    return WpSettingsGroup(
      heading: l10n.settingsAutomationApi,
      children: [
        WpSettingsRow(
          rowId: 'advanced-automation-api',
          title: l10n.settingsAutomationApiEnable,
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
          WpSettingsRow(
            rowId: 'advanced-automation-status',
            title: _statusLabel(l10n, apiState),
            trailing: const SizedBox.shrink(),
          ),
          if (apiState.token != null) ...[
            settingsInlineBreak,
            WpSettingsRow(
              rowId: 'advanced-automation-token',
              title: l10n.settingsAutomationApiToken,
              subtitle: l10n.settingsAutomationApiTokenSubtitle,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: SelectableText(
                      apiState.token!,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: WpColors.textMuted,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.copy, size: WpIconSize.sm),
                    tooltip: l10n.settingsAutomationApiCopyToken,
                    onPressed: () => _copyToken(context, apiState.token!, l10n),
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
        WpSettingsRow(
          rowId: 'advanced-automation-docs',
          title: l10n.settingsAutomationApiDocumentation,
          subtitle: l10n.settingsAutomationApiDocumentationSubtitle,
          trailing: WpButton(
            label: l10n.settingsAutomationApiDocumentationAction,
            variant: WpButtonVariant.secondary,
            onPressed: () => _openDocumentation(context),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            WpSpacing.lg,
            0,
            WpSpacing.lg,
            WpSpacing.lg,
          ),
          child: AutomationIntegrationsGroup(),
        ),
      ],
    );
  }

  Future<void> _openDocumentation(BuildContext context) async {
    await openExternalUrl(context, kAutomationApiDocsUrl);
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
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue?.toString() ?? '');
    // Saved when the field is left, not on every digit: a port that is valid
    // mid-typing (1, 10, 100 …) would otherwise restart the server each time
    // (UIA-SET-08).
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
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
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final valid = isValidAutomationApiCustomPortInput(value);
    setState(
      () => _error = valid
          ? null
          : L10n.of(context).settingsAutomationApiCustomPortInvalid,
    );
  }

  /// Persists the typed port once it is valid; an invalid entry stays in the
  /// field with its error and is not saved.
  void _commit() {
    final value = _ctrl.text;
    if (!isValidAutomationApiCustomPortInput(value)) return;
    final port = value.isEmpty ? null : int.parse(value);
    if (port == widget.initialValue) return;
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            automationApi: s.automationApi.copyWith(customPort: port),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: 'advanced-automation-port',
      title: l10n.settingsAutomationApiCustomPortLabel,
      subtitle: _error ?? l10n.settingsAutomationApiCustomPortSubtitle,
      trailing: SizedBox(
        width: 120,
        child: WpTextField(
          controller: _ctrl,
          focusNode: _focus,
          variant: WpTextFieldVariant.form,
          semanticsLabel: l10n.settingsAutomationApiCustomPortLabel,
          hintText: l10n.settingsAutomationApiCustomPortHint,
          onChanged: _onChanged,
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}
