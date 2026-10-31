/// Integrations block of the automation settings (ticket / 8.2, 8.3, 8.4).
///
/// Two rows in a settings group: event hooks, which open a dialog to add and
/// remove loopback hook URLs, and an informational row for the CLI and MCP
/// server. Rows carry no leading icons (see `wp_settings_group.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/automation_hooks.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/ltr_isolate.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_row_checkbox.dart';
import '../../../widgets/wp_text_field.dart';
import 'wp_settings_group.dart';

/// Event order in the editor, matching [kAutomationHookEvents].
const _eventOrder = ['transcript.finished', 'note.changed'];

List<AutomationHook> _hooksOf(WidgetRef ref) =>
    ref.watch(settingsProvider).value?.automationApi.hooks ??
    const <AutomationHook>[];

class AutomationIntegrationsGroup extends ConsumerWidget {
  const AutomationIntegrationsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final hookCount = _hooksOf(ref).length;

    return WpSettingsGroup(
      heading: l10n.automationIntegrationsHeading,
      children: [
        WpSettingsRow(
          rowId: 'automation-event-hooks',
          title: l10n.automationIntegrationsHooksTitle,
          subtitle: l10n.automationIntegrationsHooksSubtitle,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The count gives way first: the trailing column is capped at
              // 280 px and the button must always stay whole.
              Flexible(
                child: Text(
                  l10n.automationIntegrationsHooksCount(hookCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: WpColors.textMuted),
                ),
              ),
              const SizedBox(width: WpSpacing.sm),
              WpButton(
                key: const ValueKey('automation-event-hooks-manage'),
                label: l10n.automationIntegrationsHooksManage,
                variant: WpButtonVariant.secondary,
                onPressed: () => _openHooksDialog(context),
              ),
            ],
          ),
        ),
        WpSettingsRow(
          rowId: 'automation-cli-mcp',
          title: l10n.automationIntegrationsCliTitle,
          subtitle: l10n.automationIntegrationsCliSubtitle(
            ltrIsolate('tool/whispaste.dart'),
            ltrIsolate('WHISPASTE_API_TOKEN'),
            ltrIsolate('mcp'),
          ),
          trailing: const SizedBox.shrink(),
        ),
      ],
    );
  }

  void _openHooksDialog(BuildContext context) {
    final l10n = L10n.of(context);
    showWpDialog<void>(
      context: context,
      title: l10n.automationIntegrationsHooksTitle,
      content: const _AutomationHooksEditor(),
      actions: [
        WpDialogAction<void>(
          label: l10n.automationHooksDone,
          testId: 'automation-hooks-done',
          role: WpDialogActionRole.primary,
        ),
      ],
    );
  }
}

class _AutomationHooksEditor extends ConsumerStatefulWidget {
  const _AutomationHooksEditor();

  @override
  ConsumerState<_AutomationHooksEditor> createState() =>
      _AutomationHooksEditorState();
}

class _AutomationHooksEditorState
    extends ConsumerState<_AutomationHooksEditor> {
  final _url = TextEditingController();
  final Set<String> _events = {'transcript.finished'};
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _add() {
    final l10n = L10n.of(context);
    final url = _url.text.trim();
    final current = _hooksOf(ref);
    final result = validateAutomationHook(
      url,
      _events,
      existingCount: current.length,
    );
    if (result != AutomationHookValidation.ok) {
      setState(() => _error = _messageFor(result, l10n));
      return;
    }
    _save([...current, AutomationHook(url: url, events: Set.of(_events))]);
    setState(() {
      _url.clear();
      _error = null;
    });
  }

  Future<void> _remove(int index) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.automationHooksRemoveConfirm,
      message: l10n.automationHooksRemoveConfirmMessage,
      confirmLabel: l10n.automationHooksRemove,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final current = [..._hooksOf(ref)]..removeAt(index);
    _save(current);
  }

  void _save(List<AutomationHook> hooks) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            automationApi: s.automationApi.copyWith(hooks: hooks),
          ),
        );
  }

  String _messageFor(AutomationHookValidation result, L10n l10n) =>
      switch (result) {
        AutomationHookValidation.invalidUrl => l10n.automationHooksInvalidUrl(
          ltrIsolate('http://127.0.0.1'),
          ltrIsolate('http://[::1]'),
          ltrIsolate('http://localhost'),
          ltrIsolate('http://127.0.0.1:9000/hook'),
        ),
        AutomationHookValidation.tooMany => l10n.automationHooksTooMany(
          kAutomationHookMaxCount,
        ),
        AutomationHookValidation.noEvents ||
        AutomationHookValidation.unknownEvent ||
        AutomationHookValidation.ok => l10n.automationHooksNoEvents,
      };

  String _eventLabel(String event, L10n l10n) => switch (event) {
    'transcript.finished' => l10n.automationHooksEventTranscript,
    _ => l10n.automationHooksEventNote,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final hooks = _hooksOf(ref);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.automationHooksIntro,
          style: TextStyle(color: WpColors.textMuted),
        ),
        const SizedBox(height: WpSpacing.sm),
        // Long lists scroll inside the dialog so the add controls below stay
        // reachable with eight hooks.
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hooks.isEmpty)
                  Text(
                    l10n.automationHooksEmpty,
                    key: const ValueKey('automation-hooks-empty'),
                    style: TextStyle(color: WpColors.textMuted),
                  )
                else
                  for (var i = 0; i < hooks.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: WpSpacing.xxs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hooks[i].url,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                Text(
                                  [
                                    for (final e in _eventOrder)
                                      if (hooks[i].events.contains(e))
                                        _eventLabel(e, l10n),
                                  ].join(', '),
                                  style: TextStyle(color: WpColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            key: ValueKey('automation-hook-remove-$i'),
                            tooltip: l10n.automationHooksRemove,
                            onPressed: () => _remove(i),
                            icon: const Icon(
                              LucideIcons.trash2,
                              size: WpIconSize.sm,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        WpTextField(
          key: const ValueKey('automation-hook-url'),
          controller: _url,
          variant: WpTextFieldVariant.form,
          semanticsLabel: l10n.automationHooksUrlLabel,
          hintText: l10n.automationHooksUrlLabel,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(
          l10n.automationHooksEventsLabel,
          style: TextStyle(color: WpColors.textMuted),
        ),
        for (final event in _eventOrder)
          InkWell(
            key: ValueKey(
              'automation-hook-event-${event.replaceAll('.', '-')}',
            ),
            onTap: () => setState(() {
              if (!_events.remove(event)) _events.add(event);
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs),
              child: Row(
                children: [
                  WpRowCheckbox(
                    value: _events.contains(event),
                    semanticsLabel: _eventLabel(event, l10n),
                    onChanged: () => setState(() {
                      if (!_events.remove(event)) _events.add(event);
                    }),
                  ),
                  const SizedBox(width: WpSpacing.xs),
                  Text(_eventLabel(event, l10n)),
                ],
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: WpSpacing.xs),
            child: Text(
              _error!,
              key: const ValueKey('automation-hook-error'),
              style: TextStyle(color: WpColors.error),
            ),
          ),
        const SizedBox(height: WpSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: WpButton(
            key: const ValueKey('automation-hook-add'),
            label: l10n.automationHooksAdd,
            variant: WpButtonVariant.secondary,
            onPressed: _add,
          ),
        ),
      ],
    );
  }
}
