/// Modal picker that lets the user choose an [ExportFormat].
///
/// Pure UI — performs no filesystem or service side effects. Wiring into the
/// history export flow lives elsewhere.
///
/// Use [showWpExportFormatPicker] to display it. The returned future resolves
/// with the selected [ExportFormat] or `null` if dismissed (Cancel, Escape or
/// a tap outside).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/logging/app_logger.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../features/history/data/export_service.dart';
import 'dialog.dart';

final _log = AppLogger('ExportFormatPicker');

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows the export-format picker as a WhisPaste dialog: the formats as rows,
/// one Cancel action.
///
/// Resolves with the chosen [ExportFormat] when the user taps an option or
/// confirms the highlighted option with Enter. Resolves with `null` on Cancel,
/// Escape or a tap outside.
///
/// [formats] narrows the offered options; defaults to all five formats.
Future<ExportFormat?> showWpExportFormatPicker(
  BuildContext context, {
  List<ExportFormat> formats = _orderedFormats,
}) {
  final l10n = L10n.of(context);
  return showWpDialog<ExportFormat>(
    context: context,
    title: l10n.exportFormatPickerTitle,
    content: _ExportFormatList(formats: formats),
    actions: [
      WpDialogAction(
        label: l10n.actionCancel,
        testId: 'export-format-cancel',
        role: WpDialogActionRole.cancel,
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Stable option order — TXT → MD → CSV → JSON → DOCX
// ---------------------------------------------------------------------------

const List<ExportFormat> _orderedFormats = [
  ExportFormat.txt,
  ExportFormat.md,
  ExportFormat.csv,
  ExportFormat.json,
  ExportFormat.docx,
];

String _labelFor(ExportFormat format, L10n l10n) => switch (format) {
  ExportFormat.txt => l10n.exportFormatText,
  ExportFormat.md => l10n.exportFormatMarkdown,
  ExportFormat.csv => l10n.exportFormatCsv,
  ExportFormat.json => l10n.exportFormatJson,
  ExportFormat.docx => l10n.exportFormatWord,
};

String _extensionFor(ExportFormat format) => switch (format) {
  ExportFormat.txt => '.txt',
  ExportFormat.md => '.md',
  ExportFormat.csv => '.csv',
  ExportFormat.json => '.json',
  ExportFormat.docx => '.docx',
};

IconData _iconFor(ExportFormat format) => switch (format) {
  ExportFormat.txt => LucideIcons.file,
  ExportFormat.md => LucideIcons.fileText,
  ExportFormat.csv => LucideIcons.fileSpreadsheet,
  ExportFormat.json => LucideIcons.fileJson,
  ExportFormat.docx => LucideIcons.fileType,
};

// ---------------------------------------------------------------------------
// Content — the format rows, with keyboard navigation
// ---------------------------------------------------------------------------

/// The rows of the picker. The dialog around it supplies the title, the card
/// and the Cancel action; this widget owns the highlight and the keys.
class _ExportFormatList extends StatefulWidget {
  const _ExportFormatList({required this.formats});

  final List<ExportFormat> formats;

  @override
  State<_ExportFormatList> createState() => _ExportFormatListState();
}

class _ExportFormatListState extends State<_ExportFormatList> {
  static const _prefsKey = 'last_export_format_index';
  int _highlightedIndex = 0;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ExportFormatPicker');
    _loadLastFormat();
  }

  Future<void> _loadLastFormat() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt(_prefsKey);
      if (idx != null && idx >= 0 && idx < widget.formats.length && mounted) {
        setState(() => _highlightedIndex = idx);
      }
    } on Exception catch (e) {
      // No prefs plugin registered (e.g. golden/screenshot harnesses that
      // never mock it) — fail closed: keep the default first-option highlight.
      _log.debug('Failed to load last export format (non-fatal): $e');
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _select(ExportFormat format) {
    // Fire-and-forget save so the dialog closes instantly
    SharedPreferences.getInstance()
        .then((prefs) {
          final idx = widget.formats.indexOf(format);
          if (idx >= 0) {
            prefs.setInt(_prefsKey, idx);
          }
        })
        .catchError((Object e) {
          // Non-fatal — the choice just won't be remembered this run.
          _log.debug('Failed to persist last export format (non-fatal): $e');
        });

    Navigator.of(context).pop<ExportFormat>(format);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _highlightedIndex = (_highlightedIndex + 1).clamp(
          0,
          widget.formats.length - 1,
        );
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1).clamp(
          0,
          widget.formats.length - 1,
        );
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _select(widget.formats[_highlightedIndex]);
      return KeyEventResult.handled;
    }
    // Escape is handled by the route's barrier-dismiss logic, but we forward
    // explicitly so the dialog is reliably closed with a null result.
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop<ExportFormat>();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.formats.length; i++)
            // loam-ignore: a11y-interactive-semantics – semantics provided in _FormatOption.build
            _FormatOption(
              format: widget.formats[i],
              label: _labelFor(widget.formats[i], l10n),
              extension: _extensionFor(widget.formats[i]),
              icon: _iconFor(widget.formats[i]),
              highlighted: i == _highlightedIndex,
              onTap: () => _select(widget.formats[i]),
              onHover: () {
                if (_highlightedIndex != i) {
                  setState(() => _highlightedIndex = i);
                }
              },
            ),
        ],
      ),
    );
  }
}

class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    required this.label,
    required this.extension,
    required this.icon,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final ExportFormat format;
  final String label;
  final String extension;
  final IconData icon;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final highlightColor = WpColors.surfaceVariant;

    final mutedText = WpColors.textMuted;

    // Same construction as the snippet picker, and for the same two reasons.
    // House idiom (`section.dart`): MergeSemantics + a *label-less*
    // Semantics, because a `label:` is prepended to the subtree's text
    // instead of replacing it — the `Text(label)` below made every row
    // announce its format twice. The merged name now reads "PDF-Dokument,
    // .pdf", which is strictly more than the old label carried.
    //
    // `selected: highlighted` is the load-bearing half: this dialog keeps a
    // single `Focus` node (autofocus, line ~233) and moves a purely visual
    // highlight with the arrow keys. Without the flag the rows a screen
    // reader reports never change while the user arrows through them, so
    // there is no way to know what Enter would export.
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: highlighted,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs / 2),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => onHover(),
            child: InkWell(
              key: ValueKey('export-format-${format.name}'),
              borderRadius: WpRadius.borderMd,
              onTap: onTap,
              child: AnimatedContainer(
                duration: WpMotion.durationFor(context, WpMotion.hoverOut),
                padding: const EdgeInsets.symmetric(
                  horizontal: WpSpacing.md,
                  vertical: WpSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: highlighted ? highlightColor : Colors.transparent,
                  borderRadius: WpRadius.borderMd,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: WpIconSize.lg,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: WpSpacing.md),
                    Expanded(
                      child: Text(label, style: theme.textTheme.bodyLarge),
                    ),
                    Text(
                      extension,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: mutedText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
