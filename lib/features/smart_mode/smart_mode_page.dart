/// The Smart Mode page (#891): Smart Mode used to be a section of Settings
/// that the sidebar entry scrolled to. It is a page of its own now, holding the
/// standard preset, the engine, the hotkey block and the user's own named
/// presets.
///
/// Settings search still finds its rows: a hit sets
/// [settingsScrollTargetProvider] and switches here, and this page scrolls to
/// and highlights the row the same way Settings does.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/settings_provider.dart';
import '../../core/config/settings_sections.dart'
    show
        SmartModeCustomPreset,
        SmartModeSettings,
        kSmartModeCustomInstructionMaxChars,
        smartModeCustomInstructionLength,
        smartModeCustomPresetCanSave;
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/navigation/page_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/dialog.dart';
import '../../widgets/page_shell.dart';
import '../../widgets/wp_banner.dart';
import '../../widgets/wp_button.dart';
import '../../widgets/wp_button_group.dart';
import '../../widgets/wp_icon_button.dart';
import '../../widgets/wp_text_field.dart';
import '../settings/search/settings_search_entry.dart'
    show SettingsRowArea, settingsRowAnchorFor;
import '../settings/sections/smart_mode_section.dart';
import '../settings/widgets/wp_settings_group.dart';

class SmartModePage extends ConsumerStatefulWidget {
  const SmartModePage({super.key});

  @override
  ConsumerState<SmartModePage> createState() => _SmartModePageState();
}

class _SmartModePageState extends ConsumerState<SmartModePage> {
  Timer? _highlightClearTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyScrollTarget());
  }

  @override
  void dispose() {
    _highlightClearTimer?.cancel();
    super.dispose();
  }

  /// Consumes a pending deep link to one of the Smart Mode rows. Targets of
  /// other areas stay for the Settings page.
  void _applyScrollTarget() {
    if (!mounted) return;
    final target = ref.read(settingsScrollTargetProvider);
    if (target == null) return;
    final entry = settingsRowAnchorFor(target);
    if (entry == null || entry.area != SettingsRowArea.smartMode) return;
    ref.read(settingsScrollTargetProvider.notifier).set(null);
    ref.read(settingsHighlightTargetProvider.notifier).set(entry.rowId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = settingsRowContext(entry.rowId);
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: WpMotion.durationFor(ctx, WpMotion.smooth),
        curve: Curves.easeInOut,
        alignment: 0.2,
      );
    });
  }

  void _startHighlightClearTimer() {
    _highlightClearTimer?.cancel();
    _highlightClearTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        ref.read(settingsHighlightTargetProvider.notifier).set(null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsScrollTargetProvider, (_, target) {
      if (target != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _applyScrollTarget(),
        );
      }
    });
    ref.listen(settingsHighlightTargetProvider, (_, target) {
      if (target != null) _startHighlightClearTimer();
    });
    final highlightTarget = ref.watch(settingsHighlightTargetProvider);

    return Semantics(
      identifier: 'smart-mode-page',
      container: true,
      child: WpPageShell(
        child: SettingsRowHighlight(
          rowId: highlightTarget,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [SmartModeSection(), SmartModeCustomPresetsGroup()],
          ),
        ),
      ),
    );
  }
}

/// The user's own named presets: list, add, rename/edit, delete. Each one
/// shows up in the preset dropdown here, in the dock and in the overlay.
class SmartModeCustomPresetsGroup extends ConsumerWidget {
  const SmartModeCustomPresetsGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = L10n.of(context);
    final settings = ref.watch(settingsProvider).value ?? AppSettings.defaults;
    final presets = settings.smartMode.customPresets;

    return WpSettingsGroup(
      heading: l10n.smartModeCustomPresetsHeading,
      children: [
        WpSettingsDetail(
          child: Text(
            presets.isEmpty
                ? l10n.smartModeCustomPresetsEmpty
                : l10n.smartModeCustomPresetsHint,
            style: TextStyle(
              fontSize: WpTypography.small,
              color: WpColors.textMuted,
            ),
          ),
        ),
        for (final preset in presets)
          _CustomPresetTile(
            preset: preset,
            onEdit: () => _edit(context, ref, preset),
            onDelete: () => _delete(context, ref, preset),
          ),
        WpSettingsDetail(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: WpButton(
              testId: 'smart-mode-custom-add',
              label: l10n.smartModeCustomPresetAdd,
              icon: LucideIcons.plus,
              variant: WpButtonVariant.secondary,
              onPressed: () => _edit(context, ref, null),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    SmartModeCustomPreset? existing,
  ) async {
    final result = await showSmartModeCustomPresetDialog(
      context: context,
      existing: existing,
    );
    if (result == null) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            smartMode: s.smartMode.copyWith(
              customPresets: upsertSmartModeCustomPreset(
                s.smartMode.customPresets,
                result,
              ),
            ),
          ),
        );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    SmartModeCustomPreset preset,
  ) async {
    final l10n = L10n.of(context);
    final confirmed = await showWpConfirmDialog(
      context: context,
      title: l10n.smartModeCustomPresetDeleteTitle,
      message: l10n.smartModeCustomPresetDeleteMessage(preset.name),
      confirmLabel: l10n.smartModeCustomPresetDelete,
      cancelLabel: l10n.actionCancel,
      destructive: true,
    );
    if (!confirmed) return;
    await ref
        .read(settingsProvider.notifier)
        .updateSettings(
          (s) => s.copyWithSections(
            smartMode: removeSmartModeCustomPreset(s.smartMode, preset.id),
          ),
        );
  }
}

/// Replaces the preset with [preset]'s id in [list], or appends it.
@visibleForTesting
List<SmartModeCustomPreset> upsertSmartModeCustomPreset(
  List<SmartModeCustomPreset> list,
  SmartModeCustomPreset preset,
) {
  final index = list.indexWhere((p) => p.id == preset.id);
  if (index < 0) return [...list, preset];
  return [...list]..[index] = preset;
}

/// Drops the preset [id]. When it was the standard preset, dictation falls
/// back to `off` rather than keep a value that no longer resolves.
@visibleForTesting
SmartModeSettings removeSmartModeCustomPreset(
  SmartModeSettings settings,
  String id,
) {
  final wasActive = settings.activeCustomPreset?.id == id;
  return settings.copyWith(
    customPresets: [
      for (final p in settings.customPresets)
        if (p.id != id) p,
    ],
    standardPreset: wasActive ? 'off' : null,
  );
}

class _CustomPresetTile extends StatelessWidget {
  const _CustomPresetTile({
    required this.preset,
    required this.onEdit,
    required this.onDelete,
  });

  final SmartModeCustomPreset preset;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = preset.name.trim().isEmpty
        ? l10n.smartModeCustomPresetUntitled
        : preset.name;
    return Semantics(
      identifier: 'smart-mode-custom-${preset.id}',
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: WpTypography.body,
                      fontWeight: FontWeight.w600,
                      color: WpColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: WpSpacing.xxs),
                  Text(
                    preset.instruction,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: WpTypography.small,
                      color: WpColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: WpSpacing.sm),
            WpButtonGroup(
              children: [
                WpIconButton(
                  icon: LucideIcons.pencil,
                  tooltip: l10n.smartModeCustomPresetEdit,
                  testId: 'smart-mode-custom-${preset.id}-edit',
                  onPressed: onEdit,
                ),
                WpIconButton(
                  icon: LucideIcons.trash2,
                  tooltip: l10n.smartModeCustomPresetDelete,
                  testId: 'smart-mode-custom-${preset.id}-delete',
                  danger: true,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for name and instruction of a new preset, or edits [existing].
/// Returns null on cancel.
Future<SmartModeCustomPreset?> showSmartModeCustomPresetDialog({
  required BuildContext context,
  SmartModeCustomPreset? existing,
}) async {
  final l10n = L10n.of(context);
  final draft = _PresetDraft(existing);
  // The draft is disposed by the content widget, not here: the route's exit
  // animation still builds the fields after showWpDialog has returned.
  final saved = await showWpDialog<bool>(
    context: context,
    title: existing == null
        ? l10n.smartModeCustomPresetAddTitle
        : l10n.smartModeCustomPresetEditTitle,
    content: _PresetDialogContent(draft: draft),
    actions: [
      WpDialogAction(
        label: l10n.actionCancel,
        testId: 'smart-mode-custom-dialog-cancel',
        role: WpDialogActionRole.cancel,
        value: false,
      ),
      WpDialogAction(
        label: l10n.smartModeCustomPresetSave,
        testId: 'smart-mode-custom-dialog-save',
        role: WpDialogActionRole.primary,
        value: true,
        enabledWhen: draft.valid,
      ),
    ],
  );
  if (saved != true) return null;
  return SmartModeCustomPreset(
    id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    name: draft.name.text.trim(),
    instruction: draft.instruction.text.trim(),
  );
}

/// Controllers and validity of the preset dialog. Owned and disposed by
/// [_PresetDialogContent], so they live exactly as long as the fields do.
class _PresetDraft {
  _PresetDraft(SmartModeCustomPreset? existing)
    : name = TextEditingController(text: existing?.name ?? ''),
      instruction = TextEditingController(text: existing?.instruction ?? ''),
      // A preset saved before the limit (#1685) opens in full: with the
      // limiter on, Flutter would cut it to the limit on the first keystroke.
      enforceLimit =
          smartModeCustomInstructionLength(existing?.instruction ?? '') <=
          kSmartModeCustomInstructionMaxChars {
    _validate();
    name.addListener(_validate);
    instruction.addListener(_validate);
  }

  final TextEditingController name;
  final TextEditingController instruction;
  final bool enforceLimit;
  final ValueNotifier<bool> valid = ValueNotifier<bool>(false);
  final ValueNotifier<bool> overLimit = ValueNotifier<bool>(false);

  void _validate() {
    valid.value = smartModeCustomPresetCanSave(
      name: name.text,
      instruction: instruction.text,
    );
    overLimit.value =
        smartModeCustomInstructionLength(instruction.text) >
        kSmartModeCustomInstructionMaxChars;
  }

  void dispose() {
    name.dispose();
    instruction.dispose();
    valid.dispose();
    overLimit.dispose();
  }
}

/// The tap-to-insert example instructions (#1685): short label, full text.
List<({String label, String instruction})> _presetExamples(L10n l10n) => [
  (
    label: l10n.smartModeCustomPresetExampleMailLabel,
    instruction: l10n.smartModeCustomPresetExampleMail,
  ),
  (
    label: l10n.smartModeCustomPresetExampleBulletsLabel,
    instruction: l10n.smartModeCustomPresetExampleBullets,
  ),
  (
    label: l10n.smartModeCustomPresetExampleChatLabel,
    instruction: l10n.smartModeCustomPresetExampleChat,
  ),
];

class _PresetDialogContent extends StatefulWidget {
  const _PresetDialogContent({required this.draft});

  final _PresetDraft draft;

  @override
  State<_PresetDialogContent> createState() => _PresetDialogContentState();
}

class _PresetDialogContentState extends State<_PresetDialogContent> {
  @override
  void dispose() {
    widget.draft.dispose();
    super.dispose();
  }

  void _insertExample(String instruction) {
    widget.draft.instruction.value = TextEditingValue(
      text: instruction,
      selection: TextSelection.collapsed(offset: instruction.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final draft = widget.draft;
    final muted = TextStyle(
      fontSize: WpTypography.small,
      color: WpColors.textMuted,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.smartModeCustomPresetName),
        const SizedBox(height: WpSpacing.xxs),
        WpTextField(
          key: const ValueKey('smart-mode-custom-dialog-name'),
          controller: draft.name,
          variant: WpTextFieldVariant.form,
          semanticsLabel: l10n.smartModeCustomPresetName,
          autofocus: true,
          maxLength: 40,
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.smartModeCustomPresetInstruction),
        const SizedBox(height: WpSpacing.xxs),
        ValueListenableBuilder<bool>(
          valueListenable: draft.overLimit,
          builder: (context, over, _) => over
              ? Padding(
                  padding: const EdgeInsets.only(bottom: WpSpacing.xs),
                  child: Semantics(
                    identifier: 'smart-mode-custom-dialog-too-long',
                    liveRegion: true,
                    child: WpBanner(
                      tone: WpBannerTone.warning,
                      message: l10n.smartModeCustomPresetInstructionTooLong(
                        kSmartModeCustomInstructionMaxChars,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        WpTextField(
          key: const ValueKey('smart-mode-custom-dialog-instruction'),
          controller: draft.instruction,
          variant: WpTextFieldVariant.form,
          semanticsLabel: l10n.smartModeCustomPresetInstruction,
          hintText: l10n.smartModeCustomPresetInstructionHint,
          minLines: 3,
          maxLines: 8,
          maxLength: kSmartModeCustomInstructionMaxChars,
          enforceMaxLength: draft.enforceLimit,
        ),
        // Examples only while the field is empty: once the user writes, they
        // would replace that text, and they are no use any more.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: draft.instruction,
          builder: (context, value, _) {
            if (value.text.trim().isNotEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: WpSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.smartModeCustomPresetExamplesLabel, style: muted),
                  const SizedBox(height: WpSpacing.xxs),
                  Wrap(
                    spacing: WpSpacing.xs,
                    runSpacing: WpSpacing.xs,
                    children: [
                      for (final (i, example) in _presetExamples(l10n).indexed)
                        WpButton(
                          testId: 'smart-mode-custom-dialog-example-$i',
                          label: example.label,
                          icon: LucideIcons.plus,
                          variant: WpButtonVariant.secondary,
                          size: WpButtonSize.dense,
                          onPressed: () => _insertExample(example.instruction),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: WpSpacing.sm),
        Text(l10n.smartModeCustomPresetInstructionTips, style: muted),
      ],
    );
  }
}
