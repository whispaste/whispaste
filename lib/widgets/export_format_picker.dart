/// Modal picker that lets the user choose an [ExportFormat].
///
/// Pure UI — performs no filesystem or service side effects. Wiring into the
/// history export flow lives elsewhere.
///
/// Use [showExportFormatPicker] to display it. The returned future resolves
/// with the selected [ExportFormat] or `null` if dismissed (barrier tap or
/// Escape).
library;

import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/colors.dart';
import '../core/theme/tokens.dart';
import '../features/history/data/export_service.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Shows the export-format picker as a modal dialog.
///
/// Resolves with the chosen [ExportFormat] when the user taps an option or
/// confirms the highlighted option with Enter. Resolves with `null` if the
/// user taps the barrier or presses Escape.
Future<ExportFormat?> showExportFormatPicker(BuildContext context) {
  return showGeneralDialog<ExportFormat>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent, // painted by the transition builder
    transitionDuration: WpMotion.smooth,
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      return _PickerBarrier(
        animation: animation,
        child: _ExportFormatPickerDialog(animation: animation),
      );
    },
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
  ExportFormat.txt => Icons.description_outlined,
  ExportFormat.md => Icons.notes_outlined,
  ExportFormat.csv => Icons.table_chart_outlined,
  ExportFormat.json => Icons.data_object_outlined,
  ExportFormat.docx => Icons.article_outlined,
};

// ---------------------------------------------------------------------------
// Barrier — mirrors WpDialog frosted-glass treatment
// ---------------------------------------------------------------------------

class _PickerBarrier extends StatelessWidget {
  const _PickerBarrier({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final opacity = CurvedAnimation(parent: animation, curve: Curves.easeOut);

    final bool useBlur = !Platform.isWindows;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final barrierColor = isDark
        ? WpColorsDark.background.withValues(alpha: 0.92)
        : WpColorsLight.background.withValues(alpha: 0.88);

    return FadeTransition(
      opacity: opacity,
      child: Stack(
        children: [
          // Painted barrier — also acts as dismiss target so a tap anywhere
          // outside the dialog panel pops the route with `null`.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop<ExportFormat>(),
              child: useBlur
                  ? BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: ColoredBox(
                        color:
                            (isDark
                                    ? const Color(0xFF000000)
                                    : const Color(0xFFFFFFFF))
                                .withValues(alpha: isDark ? 0.45 : 0.35),
                      ),
                    )
                  : ColoredBox(color: barrierColor),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dialog — list of selectable formats with keyboard navigation
// ---------------------------------------------------------------------------

class _ExportFormatPickerDialog extends StatefulWidget {
  const _ExportFormatPickerDialog({required this.animation});

  final Animation<double> animation;

  @override
  State<_ExportFormatPickerDialog> createState() =>
      _ExportFormatPickerDialogState();
}

class _ExportFormatPickerDialogState extends State<_ExportFormatPickerDialog> {
  int _highlightedIndex = 0;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'ExportFormatPicker');
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _select(ExportFormat format) {
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
          _orderedFormats.length - 1,
        );
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedIndex = (_highlightedIndex - 1).clamp(
          0,
          _orderedFormats.length - 1,
        );
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _select(_orderedFormats[_highlightedIndex]);
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
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: widget.animation, curve: Curves.easeOut));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = L10n.of(context);

    return Center(
      child: SlideTransition(
        position: slide,
        child: Material(
          color: Colors.transparent,
          child: Focus(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _onKey,
            child: Container(
              width: 420,
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.all(WpSpacing.lg),
              decoration: BoxDecoration(
                color: isDark
                    ? WpColorsDark.surfaceElevated
                    : WpColorsLight.surfaceElevated,
                borderRadius: WpRadius.borderLg,
                border: Border.all(
                  color: isDark
                      ? WpColorsDark.borderSubtle
                      : WpColorsLight.borderSubtle,
                ),
                boxShadow: WpShadows.elevated,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.exportFormatPickerTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: WpSpacing.sm),
                  for (var i = 0; i < _orderedFormats.length; i++)
                    // loam-ignore: a11y-interactive-semantics – semantics provided in _FormatOption.build
                    _FormatOption(
                      format: _orderedFormats[i],
                      label: _labelFor(_orderedFormats[i], l10n),
                      extension: _extensionFor(_orderedFormats[i]),
                      icon: _iconFor(_orderedFormats[i]),
                      highlighted: i == _highlightedIndex,
                      onTap: () => _select(_orderedFormats[i]),
                      onHover: () {
                        if (_highlightedIndex != i) {
                          setState(() => _highlightedIndex = i);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
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
    final isDark = theme.brightness == Brightness.dark;

    final highlightColor = isDark
        ? WpColorsDark.surfaceVariant
        : WpColorsLight.surfaceVariant;

    final mutedText = isDark ? WpColorsDark.textMuted : WpColorsLight.textMuted;

    return Semantics(
      label: label,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: WpSpacing.xxs / 2),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => onHover(),
          child: InkWell(
            borderRadius: WpRadius.borderMd,
            onTap: onTap,
            child: AnimatedContainer(
              duration: WpMotion.hoverOut,
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
    );
  }
}
