/// "Einstellungen für dieses Modell" (#2204): the sampling choice of one
/// local text model, opened from its row in Settings › Modelle (settings
/// bound to an object live at the object).
///
/// The preset is said in plain words first; the single values sit in a
/// collapsed "Feineinstellung" so writers who never need them never see them.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/accessibility/announce.dart';
import '../../../core/config/model_sampling.dart';
import '../../../core/config/settings_provider.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/tokens.dart';
import '../../../widgets/dialog.dart';
import '../../../widgets/wp_button.dart';
import '../../../widgets/wp_dropdown.dart';
import '../../../widgets/wp_text_field.dart';

/// Opens the settings of the text model [modelId] (file at [modelPath]).
Future<void> showModelSamplingDialog(
  BuildContext context, {
  required String modelId,
  required String modelName,
  required String modelPath,
}) {
  final l10n = L10n.of(context);
  return showWpDialog<void>(
    context: context,
    title: l10n.modelSamplingTitle,
    content: ModelSamplingPanel(
      modelId: modelId,
      modelName: modelName,
      modelPath: modelPath,
    ),
    actions: [
      WpDialogAction<void>(
        label: l10n.actionClose,
        testId: 'model-sampling-close',
      ),
    ],
  );
}

/// The block itself; reads and writes `smartMode.modelSampling[modelId]`.
class ModelSamplingPanel extends ConsumerStatefulWidget {
  const ModelSamplingPanel({
    super.key,
    required this.modelId,
    required this.modelName,
    required this.modelPath,
  });

  final String modelId;
  final String modelName;
  final String modelPath;

  @override
  ConsumerState<ModelSamplingPanel> createState() => _ModelSamplingPanelState();
}

class _ModelSamplingPanelState extends ConsumerState<ModelSamplingPanel> {
  SamplingRecommendation? _vendor;
  bool _vendorRead = false;
  bool _fineOpen = false;

  @override
  void initState() {
    super.initState();
    final path = widget.modelPath;
    // The header of a large GGUF holds the whole vocabulary: read it off the
    // UI isolate, then share the result with the engine's cache.
    unawaited(
      Isolate.run(() => readGgufSampling(path)).then(
        (rec) {
          rememberGgufSampling(path, rec);
          if (mounted) {
            setState(() {
              _vendor = rec;
              _vendorRead = true;
            });
          }
        },
        onError: (Object _) {
          if (mounted) setState(() => _vendorRead = true);
        },
      ),
    );
  }

  Future<void> _store(ModelSamplingChoice? choice) =>
      ref.read(settingsProvider.notifier).updateSettings((s) {
        final map = {...s.smartMode.modelSampling};
        if (choice == null) {
          map.remove(widget.modelId);
        } else {
          map[widget.modelId] = choice;
        }
        return s.copyWithSections(
          smartMode: s.smartMode.copyWith(modelSampling: map),
        );
      });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final choice = ref.watch(
      settingsProvider.select(
        (s) => s.value?.smartMode.modelSampling[widget.modelId],
      ),
    );
    final preset = choice?.preset ?? SamplingPreset.whispaste;
    final values = effectiveSampling(choice, _vendor);
    final caption = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    String presetLabel(SamplingPreset p) => switch (p) {
      SamplingPreset.whispaste => l10n.modelSamplingPresetWhispaste,
      SamplingPreset.vendor => l10n.modelSamplingPresetVendor,
      SamplingPreset.custom => l10n.modelSamplingPresetCustom,
    };
    final hint = switch (preset) {
      SamplingPreset.whispaste => l10n.modelSamplingHintWhispaste,
      SamplingPreset.vendor => l10n.modelSamplingHintVendor,
      SamplingPreset.custom => l10n.modelSamplingHintCustom,
    };
    final vendorMissing = _vendorRead && _vendor == null;

    return Column(
      key: const ValueKey('model-sampling-panel'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.modelName,
          style: TextStyle(
            fontSize: WpTypography.body,
            fontWeight: FontWeight.w600,
            color: WpColors.textPrimary,
          ),
        ),
        const SizedBox(height: WpSpacing.sm),
        WpDropdown<SamplingPreset>(
          testId: 'model-sampling-preset',
          expanded: true,
          value: preset,
          items: [
            WpDropdownItem(
              value: SamplingPreset.whispaste,
              label: presetLabel(SamplingPreset.whispaste),
            ),
            WpDropdownItem(
              value: SamplingPreset.vendor,
              label: presetLabel(SamplingPreset.vendor),
              enabled: _vendor != null,
              disabledTooltip: _vendorRead
                  ? l10n.modelSamplingVendorMissing
                  : null,
            ),
            WpDropdownItem(
              value: SamplingPreset.custom,
              label: presetLabel(SamplingPreset.custom),
            ),
          ],
          onChanged: (p) {
            if (p == null) return;
            unawaited(
              _store(
                ModelSamplingChoice(
                  preset: p,
                  custom:
                      choice?.custom ??
                      (p == SamplingPreset.custom ? values : null),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: WpSpacing.xs),
        Text(hint, key: const ValueKey('model-sampling-hint'), style: caption),
        if (vendorMissing)
          Padding(
            padding: const EdgeInsets.only(top: WpSpacing.xxs),
            child: Text(l10n.modelSamplingVendorMissing, style: caption),
          ),
        const SizedBox(height: WpSpacing.sm),
        WpButton(
          testId: 'model-sampling-fine-toggle',
          label: l10n.modelSamplingFineTune,
          variant: WpButtonVariant.ghost,
          icon: _fineOpen ? LucideIcons.chevronDown : LucideIcons.chevronRight,
          onPressed: () => setState(() => _fineOpen = !_fineOpen),
        ),
        if (_fineOpen) ...[
          const SizedBox(height: WpSpacing.xs),
          for (final field in _SamplingField.values)
            _ValueRow(
              key: ValueKey('model-sampling-${field.name}-$preset-$values'),
              field: field,
              values: values,
              onValid: (next) => unawaited(
                _store(
                  ModelSamplingChoice(
                    preset: SamplingPreset.custom,
                    custom: next,
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: WpSpacing.sm),
        WpButton(
          testId: 'model-sampling-reset',
          label: l10n.modelSamplingReset,
          variant: WpButtonVariant.ghost,
          onPressed: choice == null
              ? null
              : () async {
                  await _store(null);
                  if (!context.mounted) return;
                  announce(
                    View.of(context),
                    l10n.modelSamplingResetDone(widget.modelName),
                    Directionality.of(context),
                  );
                },
        ),
      ],
    );
  }
}

enum _SamplingField { temperature, topK, topP, minP, repeatPenalty }

extension on _SamplingField {
  SamplingRange get range => switch (this) {
    _SamplingField.temperature => SamplingRange.temperature,
    _SamplingField.topK => SamplingRange.topK,
    _SamplingField.topP => SamplingRange.topP,
    _SamplingField.minP => SamplingRange.minP,
    _SamplingField.repeatPenalty => SamplingRange.repeatPenalty,
  };

  num read(SmartModeSampling v) => switch (this) {
    _SamplingField.temperature => v.temperature,
    _SamplingField.topK => v.topK,
    _SamplingField.topP => v.topP,
    _SamplingField.minP => v.minP,
    _SamplingField.repeatPenalty => v.repeatPenalty,
  };

  SmartModeSampling write(SmartModeSampling v, double x) => switch (this) {
    _SamplingField.temperature => v.copyWith(temperature: x),
    _SamplingField.topK => v.copyWith(topK: x.round()),
    _SamplingField.topP => v.copyWith(topP: x),
    _SamplingField.minP => v.copyWith(minP: x),
    _SamplingField.repeatPenalty => v.copyWith(repeatPenalty: x),
  };

  (String, String) labels(L10n l10n) => switch (this) {
    _SamplingField.temperature => (
      l10n.modelSamplingTemperature,
      l10n.modelSamplingTemperatureHelp,
    ),
    _SamplingField.topK => (l10n.modelSamplingTopK, l10n.modelSamplingTopKHelp),
    _SamplingField.topP => (l10n.modelSamplingTopP, l10n.modelSamplingTopPHelp),
    _SamplingField.minP => (l10n.modelSamplingMinP, l10n.modelSamplingMinPHelp),
    _SamplingField.repeatPenalty => (
      l10n.modelSamplingRepeat,
      l10n.modelSamplingRepeatHelp,
    ),
  };
}

/// Parses a typed value (comma or point); null when it is not a number in
/// [range] or, for whole-number fields, not whole.
double? parseSamplingInput(
  String text,
  SamplingRange range, {
  bool whole = false,
}) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || !range.contains(v)) return null;
  if (whole && v != v.roundToDouble()) return null;
  return v;
}

String _format(num v) {
  if (v is int) return '$v';
  final s = v.toStringAsFixed(2);
  return s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}

class _ValueRow extends StatefulWidget {
  const _ValueRow({
    super.key,
    required this.field,
    required this.values,
    required this.onValid,
  });

  final _SamplingField field;
  final SmartModeSampling values;
  final ValueChanged<SmartModeSampling> onValid;

  @override
  State<_ValueRow> createState() => _ValueRowState();
}

class _ValueRowState extends State<_ValueRow> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.field.read(widget.values)),
  );
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit(String text) {
    final field = widget.field;
    final v = parseSamplingInput(
      text,
      field.range,
      whole: field == _SamplingField.topK,
    );
    setState(() => _invalid = v == null);
    if (v == null || v == field.read(widget.values).toDouble()) return;
    widget.onValid(field.write(widget.values, v));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final (label, help) = widget.field.labels(l10n);
    final range = widget.field.range;
    final caption = TextStyle(
      fontSize: WpTypography.caption,
      color: WpColors.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: WpSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: WpTypography.body,
                    color: WpColors.textPrimary,
                  ),
                ),
                Text(help, style: caption),
                if (_invalid)
                  Text(
                    l10n.modelSamplingRange(
                      _format(range.min),
                      _format(range.max),
                    ),
                    key: ValueKey('model-sampling-${widget.field.name}-error'),
                    style: caption.copyWith(color: WpColors.error),
                  ),
              ],
            ),
          ),
          const SizedBox(width: WpSpacing.sm),
          SizedBox(
            width: 88,
            child: Focus(
              onFocusChange: (focused) {
                if (!focused) _commit(_controller.text);
              },
              child: WpTextField(
                controller: _controller,
                variant: WpTextFieldVariant.form,
                testId: 'model-sampling-${widget.field.name}',
                semanticsLabel: label,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onSubmitted: _commit,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
