/// Editor for the clipboard history's per-app exclusion list (issue #593),
/// opened from the side panel rows of the appearance settings.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../services/app_profiles/app_profile.dart'
    show normalizeAppIdentifier;
import '../../../services/clipboard_history/clipboard_app_exclusion.dart';
import '../../../services/clipboard_history/running_apps.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_app_icon.dart';
import '../../../widgets/wp_app_row.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_icon_button.dart';
import '../../../widgets/wp_text_field.dart';

/// Stable test id fragment for an app: its normalised key, kebab-case.
String _idPart(String identifier) =>
    (normalizeAppIdentifier(identifier) ?? identifier).replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );

/// The list currently in effect (stored, or the platform defaults).
List<String> clipboardExclusionsOf(AppSettings settings) =>
    parseClipboardExcludedApps(
      settings.interface_.clipboardExcludedApps,
      defaultTargetPlatform,
    );

Future<void> showClipboardExclusionEditor(BuildContext context) {
  final l10n = L10n.of(context);
  return showWpDialog<void>(
    context: context,
    title: l10n.settingsClipboardExclusionsTitle,
    content: const ClipboardExclusionEditor(),
    actions: [
      WpDialogAction<void>(
        label: l10n.actionClose,
        testId: 'clipboard-exclusions-close',
        role: WpDialogActionRole.primary,
      ),
    ],
  );
}

class ClipboardExclusionEditor extends ConsumerStatefulWidget {
  const ClipboardExclusionEditor({super.key});

  @override
  ConsumerState<ClipboardExclusionEditor> createState() =>
      _ClipboardExclusionEditorState();
}

class _ClipboardExclusionEditorState
    extends ConsumerState<ClipboardExclusionEditor> {
  final _input = TextEditingController();
  List<RunningApp> _running = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (clipboardSourceAppDetectable(defaultTargetPlatform)) _loadRunning();
  }

  Future<void> _loadRunning() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final apps = await listRunningApps();
      if (mounted) setState(() => _running = apps);
    } on Object {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save(List<String> apps) {
    ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            interface_: s.interface_.copyWith(
              clipboardExcludedApps: encodeClipboardExcludedApps(
                normalizeClipboardExcludedApps(apps),
              ),
            ),
          ),
        );
  }

  void _add(String id, List<String> current) {
    if (id.trim().isEmpty) return;
    _save([...current, id]);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final apps = clipboardExclusionsOf(settings);
    final detectable = clipboardSourceAppDetectable(defaultTargetPlatform);
    final pickable = _running
        .where((r) => !isClipboardSourceExcluded(r.id, apps))
        .toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          detectable
              ? l10n.settingsClipboardExclusionsHint
              : l10n.settingsClipboardExclusionsHintLinux,
          style: TextStyle(
            color: WpColors.textMuted,
            fontSize: WpTypography.body,
          ),
        ),
        const SizedBox(height: WpSpacing.md),
        if (detectable) ...[
          Row(
            children: [
              Expanded(
                child: WpTextField(
                  controller: _input,
                  variant: WpTextFieldVariant.form,
                  semanticsLabel: l10n.settingsClipboardExclusionsAddLabel,
                  hintText: l10n.settingsClipboardExclusionsAddHint,
                  onSubmitted: (v) => _add(v, apps),
                ),
              ),
              const SizedBox(width: WpSpacing.xs),
              WpButton(
                testId: 'clipboard-exclusions-add',
                label: l10n.settingsClipboardExclusionsAdd,
                variant: WpButtonVariant.secondary,
                onPressed: () => _add(_input.text, apps),
              ),
            ],
          ),
          const SizedBox(height: WpSpacing.md),
          Text(
            l10n.settingsClipboardExclusionsRunning,
            style: TextStyle(
              color: WpColors.textMuted,
              fontSize: WpTypography.body,
            ),
          ),
          const SizedBox(height: WpSpacing.xxs),
          if (_loading)
            Row(
              key: const ValueKey('clipboard-exclusions-running-loading'),
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: WpSpacing.xs),
                Text(
                  l10n.settingsClipboardExclusionsRunningLoading,
                  style: TextStyle(color: WpColors.textMuted),
                ),
              ],
            )
          else if (_failed)
            Row(
              key: const ValueKey('clipboard-exclusions-running-error'),
              children: [
                Flexible(
                  child: Text(
                    l10n.settingsClipboardExclusionsRunningError,
                    style: TextStyle(color: WpColors.textMuted),
                  ),
                ),
                const SizedBox(width: WpSpacing.xs),
                WpButton(
                  testId: 'clipboard-exclusions-running-retry',
                  label: l10n.settingsClipboardExclusionsRunningRetry,
                  variant: WpButtonVariant.ghost,
                  size: WpButtonSize.dense,
                  onPressed: _loadRunning,
                ),
              ],
            )
          else
            Wrap(
              spacing: WpSpacing.xs,
              children: [
                for (final app in pickable)
                  WpButton(
                    testId: 'clipboard-exclusions-pick-${_idPart(app.id)}',
                    label: app.name,
                    variant: WpButtonVariant.ghost,
                    size: WpButtonSize.dense,
                    icon: LucideIcons.plus,
                    onPressed: () => _add(app.id, apps),
                  ),
              ],
            ),
          const SizedBox(height: WpSpacing.md),
        ],
        if (apps.isEmpty)
          Text(
            l10n.settingsClipboardExclusionsEmpty,
            style: TextStyle(color: WpColors.textMuted),
          ),
        for (final id in apps)
          WpAppRow(
            testId: 'clipboard-exclusions-row-${_idPart(id)}',
            identifier: id,
            name: watchAppName(ref, id),
            leading: WpAppIcon(identifier: id),
            trailing: WpIconButton.ghost(
              testId: 'clipboard-exclusions-remove-${_idPart(id)}',
              icon: LucideIcons.x,
              tooltip: l10n.settingsClipboardExclusionsRemove(
                watchAppName(ref, id),
              ),
              onPressed: () => _save(apps.where((a) => a != id).toList()),
            ),
          ),
        if (detectable) ...[
          const SizedBox(height: WpSpacing.xs),
          WpButton(
            testId: 'clipboard-exclusions-defaults',
            label: l10n.settingsClipboardExclusionsDefaults,
            variant: WpButtonVariant.ghost,
            size: WpButtonSize.dense,
            onPressed: () =>
                _save(defaultClipboardExcludedApps(defaultTargetPlatform)),
          ),
        ],
      ],
    );
  }
}
