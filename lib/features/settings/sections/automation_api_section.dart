/// Local Automation API settings section.
library;

import 'dart:async';

import '../../../widgets/external_link.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/app_urls.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../services/automation_api/automation_api_controller.dart';
import '../../../services/automation_api/automation_write_jobs.dart';
import '../../../widgets/recording_behavior.dart' show localizeRecordingError;
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_text_field.dart';
import '../settings_widgets.dart';
import '../widgets/automation_integrations.dart';
import '../widgets/wp_settings_group.dart';
import '../../../../widgets/wp_copy_feedback.dart';
import '../../../widgets/wp_icon_button.dart';

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

    // The integrations are a group of their own on page level, next to the
    // API group, never a card inside it (#1498).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WpSettingsGroup(
          heading: l10n.settingsAutomationApi,
          children: [
            WpSettingsRow(
              rowId: 'advanced-automation-api',
              title: l10n.settingsAutomationApiEnable,
              subtitle: l10n.settingsAutomationApiEnableSubtitle,
              switchNamesRow: true,
              trailing: settingsToggle(
                label: l10n.settingsAutomationApiEnable,
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
                _TokenRow(
                  rowId: 'advanced-automation-token',
                  title: l10n.settingsAutomationApiToken,
                  subtitle: l10n.settingsAutomationApiTokenSubtitle,
                  token: apiState.token!,
                  copyTarget: 'automation-token',
                  onRegenerate: () => _confirmRegenerate(context, ref, l10n),
                ),
              ],
              // Writing (#255, ADR 0015 D17/D22): its own switch and token,
              // nested under the API switch because it needs the server.
              settingsInlineBreak,
              WpSettingsRow(
                rowId: 'advanced-automation-write',
                title: l10n.settingsAutomationWriteEnable,
                subtitle: l10n.settingsAutomationWriteEnableSubtitle,
                switchNamesRow: true,
                trailing: settingsToggle(
                  label: l10n.settingsAutomationWriteEnable,
                  value: settings.automationApi.writeEnabled,
                  onChanged: (v) {
                    _log.info('user toggled automationApi.writeEnabled=$v');
                    ref
                        .read(settingsProvider.notifier)
                        .updateSettings(
                          (s) => s.copyWithSections(
                            automationApi: s.automationApi.copyWith(
                              writeEnabled: v,
                            ),
                          ),
                        );
                  },
                ),
              ),
              if (settings.automationApi.writeEnabled) ...[
                if (apiState.writeToken != null) ...[
                  settingsInlineBreak,
                  _TokenRow(
                    rowId: 'advanced-automation-write-token',
                    title: l10n.settingsAutomationWriteToken,
                    subtitle: l10n.settingsAutomationWriteTokenSubtitle,
                    token: apiState.writeToken!,
                    copyTarget: 'automation-write-token',
                    onRegenerate: () =>
                        _confirmRegenerateWrite(context, ref, l10n),
                  ),
                ],
                settingsInlineBreak,
                const _WriteProtocol(),
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
          ],
        ),
        settingsSectionBreak,
        const AutomationIntegrationsGroup(),
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

  Future<void> _confirmRegenerateWrite(
    BuildContext context,
    WidgetRef ref,
    L10n l10n,
  ) async {
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.settingsAutomationWriteRegenerateConfirmTitle,
      message: l10n.settingsAutomationWriteRegenerateConfirmMessage,
      confirmLabel: l10n.settingsAutomationApiRegenerate,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    await ref
        .read(automationApiControllerProvider.notifier)
        .regenerateWriteToken();
  }
}

/// A token with copy and regenerate, as the API token row shows it.
class _TokenRow extends StatelessWidget {
  const _TokenRow({
    required this.rowId,
    required this.title,
    required this.subtitle,
    required this.token,
    required this.copyTarget,
    required this.onRegenerate,
  });

  final String rowId;
  final String title;
  final String subtitle;
  final String token;
  final String copyTarget;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return WpSettingsRow(
      rowId: rowId,
      title: title,
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: SelectableText(
              token,
              maxLines: 1,
              style: TextStyle(
                fontFamily: 'monospace',
                color: WpColors.textMuted,
              ),
            ),
          ),
          WpCopyAnchor(
            target: copyTarget,
            child: WpIconButton.ghost(
              icon: LucideIcons.copy,
              tooltip: l10n.settingsAutomationApiCopyToken,
              onPressed: () => unawaited(
                copyWithFeedback(context, text: token, target: copyTarget),
              ),
            ),
          ),
          WpButton(
            label: l10n.settingsAutomationApiRegenerate,
            variant: WpButtonVariant.secondary,
            onPressed: onRegenerate,
          ),
        ],
      ),
    );
  }
}

/// The in-memory log of API write jobs (D22): time, status and sizes, never
/// text. Gone when the app quits.
class _WriteProtocol extends ConsumerWidget {
  const _WriteProtocol();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final records = ref.watch(automationWriteJobsProvider);
    final localizations = MaterialLocalizations.of(context);
    return WpSettingsRow(
      rowId: 'advanced-automation-write-protocol',
      title: l10n.settingsAutomationWriteProtocol,
      subtitle: records.isEmpty
          ? l10n.settingsAutomationWriteProtocolEmpty
          : [for (final r in records) _line(l10n, localizations, r)].join('\n'),
      trailing: const SizedBox.shrink(),
    );
  }

  static String _line(
    L10n l10n,
    MaterialLocalizations localizations,
    AutomationWriteRecord r,
  ) {
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(r.startedAt),
    );
    final title = l10n.automationWriteEntryTitle(time, _status(l10n, r));
    final size = l10n.automationWriteEntryInstruction(r.instructionChars);
    return '$title · $size';
  }

  static String _status(L10n l10n, AutomationWriteRecord r) {
    final status = switch (r.status) {
      AutomationWriteStatus.running => l10n.automationWriteStatusRunning,
      AutomationWriteStatus.inserted => l10n.automationWriteStatusInserted(
        r.resultChars ?? 0,
      ),
      AutomationWriteStatus.failed =>
        '${l10n.automationWriteStatusFailed}: ${_reason(l10n, r.errorCode)}',
    };
    return r.targetChecked || r.status == AutomationWriteStatus.running
        ? status
        : '$status · ${l10n.automationWriteTargetUnchecked}';
  }

  static String _reason(L10n l10n, String? code) => switch (code) {
    'automation_write_target_changed' => l10n.automationWriteErrorTargetChanged,
    'automation_write_target_unknown' => l10n.automationWriteErrorTargetUnknown,
    'automation_write_paste_failed' => l10n.automationWriteErrorPasteFailed,
    'automation_write_dictation_busy' => l10n.automationWriteErrorDictationBusy,
    'revoked' => l10n.automationWriteErrorRevoked,
    null => l10n.errorGeneric,
    _ => localizeRecordingError(l10n, code),
  };
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
          // Same surface as the dropdowns on this page, not a grey box.
          variant: WpTextFieldVariant.control,
          semanticsLabel: l10n.settingsAutomationApiCustomPortLabel,
          hintText: l10n.settingsAutomationApiCustomPortHint,
          onChanged: _onChanged,
          onSubmitted: (_) => _commit(),
        ),
      ),
    );
  }
}
