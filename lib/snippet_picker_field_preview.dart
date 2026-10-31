/// The field preview of "In einem Satz" and the key hints of the snippet
/// picker panel — both render inside the picker engine
/// (`snippet_picker_render_entrypoint.dart`).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'core/l10n/generated/app_localizations.dart';
import 'core/theme/colors.dart';
import 'core/theme/tokens.dart';
import 'services/snippet_picker/snippet_picker_protocol.dart';
import 'services/snippet_picker/snippet_picker_render_channel.dart';
import 'services/snippets/interactive_snippet_composer.dart';
import 'widgets/wp_text_field.dart';
import 'core/accessibility/announce.dart';

/// Label of the "In einem Satz" key: ⌘↩ on macOS, Strg+↩ elsewhere.
String snippetPickerSentenceKeyLabel(L10n l10n) =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? '⌘↩'
    : '${l10n.modifierCtrl}+↩';

/// Shows what one spoken sentence filled into each field, lets the user fix
/// any value, and previews the finished text. Enter inserts; with an empty
/// field the first Enter only marks the gaps and a second one inserts.
/// Escape cancels (handled by the panel's shortcuts).
class SnippetFieldPreview extends StatefulWidget {
  const SnippetFieldPreview({
    super.key,
    required this.head,
    required this.fields,
    required this.l10n,
    required this.onConfirm,
  });

  /// Title = snippet title, body = template, hint = model hint.
  final SnippetPickerRenderItem head;
  final List<SnippetPickerRenderItem> fields;
  final L10n l10n;

  /// Receives the selection id ([fillSelectionId]) to send to the shell.
  final ValueChanged<String> onConfirm;

  @override
  State<SnippetFieldPreview> createState() => SnippetFieldPreviewState();
}

/// Public so the panel can forward Enter and arrow keys ([confirm],
/// [moveFocus]) that the native shells deliver outside the focus chain.
class SnippetFieldPreviewState extends State<SnippetFieldPreview> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  /// Set by the first Enter while a field is empty: the next Enter inserts.
  bool _armed = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  /// Runs once per preview: the panel gives every show a fresh key, so a
  /// new preview always gets a new state.
  void _build() {
    _armed = false;
    _controllers = [
      for (final f in widget.fields) TextEditingController(text: f.body),
    ];
    _focusNodes = [for (final _ in widget.fields) FocusNode()];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusNodes.isEmpty) return;
      final firstEmpty = _values.indexWhere((v) => v.isEmpty);
      _focusNodes[firstEmpty < 0 ? 0 : firstEmpty].requestFocus();
      _announce(
        widget.l10n.snippetFieldPreviewAnnounce(
          _values.where((v) => v.isNotEmpty).length,
          _values.length,
        ),
      );
    });
  }

  void _dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  List<String> get _values => [for (final c in _controllers) c.text.trim()];

  void _announce(String message) =>
      announce(View.of(context), message, Directionality.of(context));

  /// Enter: inserts, or first marks empty fields (see the class doc).
  void confirm() {
    final values = _values;
    final empty = values.where((v) => v.isEmpty).length;
    if (empty > 0 && !_armed) {
      setState(() => _armed = true);
      _focusNodes[values.indexWhere((v) => v.isEmpty)].requestFocus();
      _announce(widget.l10n.snippetFieldPreviewConfirmEmpty(empty));
      return;
    }
    widget.onConfirm(fillSelectionId(values));
  }

  /// Arrow keys move between the fields.
  void moveFocus(int delta) {
    if (_focusNodes.isEmpty) return;
    final current = _focusNodes.indexWhere((f) => f.hasFocus);
    final next = ((current < 0 ? 0 : current) + delta).clamp(
      0,
      _focusNodes.length - 1,
    );
    _focusNodes[next].requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final values = _values;
    final empty = values.where((v) => v.isEmpty).length;
    final composed = composeInteractiveSnippetText(
      template: widget.head.body,
      fieldNames: [for (final f in widget.fields) f.title],
      fieldTranscripts: values,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            WpSpacing.md,
            WpSpacing.md,
            WpSpacing.md,
            WpSpacing.xs,
          ),
          child: Text(
            widget.head.title,
            style: TextStyle(
              color: WpColors.textPrimary,
              fontSize: WpTypography.body,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.head.hint == kSnippetPickerHintSpeakFieldNames)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: WpSpacing.md),
            child: Text(
              l10n.snippetFieldPreviewNoModelHint(
                [for (final f in widget.fields) '${f.title} …'].join(', '),
              ),
              key: const ValueKey('snippet-preview-no-model-hint'),
              style: TextStyle(
                color: WpColors.textMuted,
                fontSize: WpTypography.small,
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(WpSpacing.md),
            children: [
              for (var i = 0; i < widget.fields.length; i++) ...[
                _FieldLabel(
                  name: widget.fields[i].title,
                  emptyLabel: values[i].isEmpty
                      ? l10n.snippetFieldPreviewEmpty
                      : null,
                ),
                const SizedBox(height: WpSpacing.xxs),
                Semantics(
                  identifier: 'snippet-preview-field-$i',
                  child: WpTextField(
                    controller: _controllers[i],
                    focusNode: _focusNodes[i],
                    variant: WpTextFieldVariant.form,
                    maxLines: 1,
                    semanticsLabel: widget.fields[i].title,
                    onChanged: (_) => setState(() => _armed = false),
                    onSubmitted: (_) => confirm(),
                  ),
                ),
                const SizedBox(height: WpSpacing.sm),
              ],
              Text(
                l10n.snippetFieldPreviewResult,
                style: TextStyle(
                  color: WpColors.textMuted,
                  fontSize: WpTypography.caption,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: WpSpacing.xxs),
              Text(
                composed,
                style: TextStyle(
                  color: WpColors.textSecondary,
                  fontSize: WpTypography.small,
                ),
              ),
            ],
          ),
        ),
        Container(height: 1, color: WpColors.borderSubtle),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WpSpacing.md,
            vertical: WpSpacing.xs,
          ),
          child: Wrap(
            spacing: WpSpacing.md,
            runSpacing: WpSpacing.xxs,
            children: [
              SnippetPickerKeyHint(
                keyLabel: '↩',
                label: _armed && empty > 0
                    ? l10n.snippetFieldPreviewConfirmEmpty(empty)
                    : l10n.snippetsPickerInsertAction,
              ),
              SnippetPickerKeyHint(
                keyLabel: 'tab',
                label: l10n.snippetFieldPreviewNextField,
              ),
              SnippetPickerKeyHint(keyLabel: 'esc', label: l10n.actionCancel),
            ],
          ),
        ),
      ],
    );
  }
}

/// Field name above its input, with a marker while the field is empty.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.name, required this.emptyLabel});

  final String name;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            name,
            style: TextStyle(
              color: WpColors.textSecondary,
              fontSize: WpTypography.small,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (emptyLabel case final label?) ...[
          const SizedBox(width: WpSpacing.xs),
          Icon(
            LucideIcons.circleAlert,
            size: WpIconSize.xs,
            color: WpColors.warning,
          ),
          const SizedBox(width: WpSpacing.xxs),
          Text(
            label,
            style: TextStyle(
              color: WpColors.warning,
              fontSize: WpTypography.caption,
            ),
          ),
        ],
      ],
    );
  }
}

/// Footer affordance: a small key-cap chip plus a muted action label.
class SnippetPickerKeyHint extends StatelessWidget {
  const SnippetPickerKeyHint({
    super.key,
    required this.keyLabel,
    required this.label,
  });

  final String keyLabel;
  final String label;

  @override
  Widget build(BuildContext context) {
    final textMuted = WpColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: WpColors.surfaceMutedFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: WpColors.borderSubtle),
          ),
          child: Text(
            keyLabel,
            style: TextStyle(
              color: WpColors.textSecondary,
              fontSize: WpTypography.micro,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: WpSpacing.xxs),
        Text(
          label,
          style: TextStyle(color: textMuted, fontSize: WpTypography.caption),
        ),
      ],
    );
  }
}
