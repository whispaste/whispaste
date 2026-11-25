/// The editor text view (#648): text size, line length and line spacing of
/// the text body in the recording, note and snippet editors.
///
/// * [WpEditorText] wraps a whole editor block (toolbar, body, status line).
///   It hands the view down and answers Ctrl/Cmd+Plus, Minus and 0 wherever
///   the focus is inside the block — in the text and on the toolbar alike.
/// * [WpEditorTextBody] wraps only the text body: it scales the text by the
///   chosen size on top of the system text size and shows the reset chip
///   while the size is not the standard. The toolbar and the status line
///   keep their size, so every tool stays where it is at 200 % and beyond.
/// * [editorTextViewMenuActions] is the menu behind the toolbar's text view
///   button: the same choices for mouse, keyboard and screen readers.
///
/// Nothing here animates: a size or spacing change takes effect in one frame,
/// with or without "reduce motion".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/accessibility/announce.dart';
import '../core/config/command_shortcut.dart';
import '../core/editor/editor_text_view.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/theme/tokens.dart';
import 'searchable_list_page.dart' show WpListMenuAction;
import 'wp_button.dart';

/// The view the editors show right now; the standard view until the stored
/// one has loaded.
EditorTextView _current(ProviderContainer container) =>
    container.read(editorTextViewProvider).value ?? EditorTextView.standard;

/// Applies [view] in every editor and stores it; announces a new text size.
void _choose(BuildContext context, EditorTextView view) {
  final container = ProviderScope.containerOf(context, listen: false);
  final before = _current(container);
  if (before == view) return;
  container.read(editorTextViewProvider.notifier).choose(view);
  if (before.textSize != view.textSize) {
    announce(
      View.of(context),
      L10n.of(context).editorTextSizeAnnouncement(view.textSize),
      Directionality.of(context),
    );
  }
}

/// One text size step larger (+1), smaller (-1), or back to 100 % (0).
void stepEditorTextSize(BuildContext context, int direction) {
  final view = _current(ProviderScope.containerOf(context, listen: false));
  _choose(
    context,
    direction == 0
        ? view.copyWith(textSize: EditorTextView.standardTextSize)
        : view.stepTextSize(direction),
  );
}

/// Hands the view down to a whole editor block; see the library docs.
class WpEditorText extends ConsumerWidget {
  const WpEditorText({super.key, required this.child});

  final Widget child;

  /// The view in effect, or `null` outside an editor — every other text
  /// field keeps its own size, spacing and width.
  static EditorTextView? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_EditorTextViewScope>()?.view;

  /// [base] with the chosen line spacing inside an editor, unchanged
  /// elsewhere. For read views that style their own text.
  static TextStyle styleOf(BuildContext context, TextStyle base) {
    final view = maybeOf(context);
    return view == null ? base : base.copyWith(height: view.lineSpacing.factor);
  }

  /// The extra end inset that keeps a line of [fontSize] text within the
  /// chosen line length in a box [boxWidth] wide whose own inset is [base];
  /// 0 when the box is narrower or the length is not capped. The box itself
  /// keeps its width, so the card still fills the panel.
  static double extraEndInset(
    BuildContext context, {
    required EdgeInsets base,
    required double boxWidth,
    required double fontSize,
  }) {
    final view = maybeOf(context);
    if (view == null || !boxWidth.isFinite) return 0;
    final measure = view.maxWidthFor(
      MediaQuery.textScalerOf(context).scale(fontSize),
    );
    if (measure == null) return 0;
    final extra = boxWidth - base.horizontal - measure;
    return extra > 0 ? extra : 0;
  }

  /// [base] plus [extraEndInset].
  static EdgeInsetsGeometry paddingFor(
    BuildContext context, {
    required EdgeInsets base,
    required double boxWidth,
    required double fontSize,
  }) {
    final extra = extraEndInset(
      context,
      base: base,
      boxWidth: boxWidth,
      fontSize: fontSize,
    );
    if (extra == 0) return base;
    return EdgeInsetsDirectional.fromSTEB(
      base.left,
      base.top,
      base.right + extra,
      base.bottom,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view =
        ref.watch(editorTextViewProvider).value ?? EditorTextView.standard;
    return _EditorTextViewScope(
      view: view,
      child: Builder(
        builder: (context) => CallbackShortcuts(
          bindings: {
            for (final key in [
              LogicalKeyboardKey.equal,
              LogicalKeyboardKey.add,
              LogicalKeyboardKey.numpadAdd,
            ]) ...{
              commandActivator(key): () => stepEditorTextSize(context, 1),
              commandActivator(key, shift: true): () =>
                  stepEditorTextSize(context, 1),
            },
            commandActivator(LogicalKeyboardKey.minus): () =>
                stepEditorTextSize(context, -1),
            commandActivator(LogicalKeyboardKey.numpadSubtract): () =>
                stepEditorTextSize(context, -1),
            commandActivator(LogicalKeyboardKey.digit0): () =>
                stepEditorTextSize(context, 0),
            commandActivator(LogicalKeyboardKey.numpad0): () =>
                stepEditorTextSize(context, 0),
          },
          child: child,
        ),
      ),
    );
  }
}

class _EditorTextViewScope extends InheritedWidget {
  const _EditorTextViewScope({required this.view, required super.child});

  final EditorTextView view;

  @override
  bool updateShouldNotify(_EditorTextViewScope oldWidget) =>
      oldWidget.view != view;
}

/// Scales the text body of an editor; see the library docs.
class WpEditorTextBody extends StatelessWidget {
  const WpEditorTextBody({
    super.key,
    required this.testIdPrefix,
    required this.child,
  });

  /// The editor's test ID: the reset chip is `<testIdPrefix>-zoom-reset`.
  final String testIdPrefix;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final view = WpEditorText.maybeOf(context);
    if (view == null) return child;
    final media = MediaQuery.of(context);
    return Stack(
      // The parent's constraints as they are: a fixed editor area (notes,
      // snippets) or a text that grows in a scrolling page (recordings).
      fit: StackFit.passthrough,
      children: [
        MediaQuery(
          data: media.copyWith(
            textScaler: _EditorTextScaler(media.textScaler, view.textScale),
          ),
          child: child,
        ),
        if (!view.isStandardTextSize)
          PositionedDirectional(
            top: WpSpacing.xs,
            end: WpSpacing.md,
            child: WpButton(
              testId: '$testIdPrefix-zoom-reset',
              label: L10n.of(context).editorTextSizeReset(view.textSize),
              variant: WpButtonVariant.ghost,
              size: WpButtonSize.dense,
              onPressed: () => stepEditorTextSize(context, 0),
            ),
          ),
      ],
    );
  }
}

/// The editor text size on top of the system's: the system scaling stays in
/// force, the chosen factor multiplies it.
class _EditorTextScaler extends TextScaler {
  const _EditorTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use -- TextScaler still requires this override.
  double get textScaleFactor => base.scale(16) / 16 * factor;

  @override
  bool operator ==(Object other) =>
      other is _EditorTextScaler &&
      other.base == base &&
      other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// The entries of the toolbar's text view menu. testIDs are
/// `editor-text-view-<entry>`.
List<WpListMenuAction> editorTextViewMenuActions(BuildContext context) {
  final l10n = L10n.of(context);
  final view = _current(ProviderScope.containerOf(context, listen: false));
  void choose(EditorTextView next) => _choose(context, next);
  String lengthLabel(EditorLineLength length) => switch (length) {
    EditorLineLength.full => l10n.editorTextViewLineFull,
    EditorLineLength.wide => l10n.editorTextViewLineWide,
    EditorLineLength.medium => l10n.editorTextViewLineMedium,
    EditorLineLength.narrow => l10n.editorTextViewLineNarrow,
  };
  String spacingLabel(EditorLineSpacing spacing) => switch (spacing) {
    EditorLineSpacing.compact => l10n.editorTextViewSpacingCompact,
    EditorLineSpacing.normal => l10n.editorTextViewSpacingNormal,
    EditorLineSpacing.relaxed => l10n.editorTextViewSpacingRelaxed,
  };
  final current = l10n.editorTextViewCurrentSize(view.textSize);
  return [
    WpListMenuAction(
      itemKey: const ValueKey('editor-text-view-larger'),
      label: l10n.editorTextViewLarger(commandShortcutLabel('+', l10n: l10n)),
      hint: current,
      icon: LucideIcons.zoomIn,
      enabled: view.canGrow,
      onSelected: () => choose(view.stepTextSize(1)),
    ),
    WpListMenuAction(
      itemKey: const ValueKey('editor-text-view-smaller'),
      label: l10n.editorTextViewSmaller(commandShortcutLabel('-', l10n: l10n)),
      hint: current,
      icon: LucideIcons.zoomOut,
      enabled: view.canShrink,
      onSelected: () => choose(view.stepTextSize(-1)),
    ),
    WpListMenuAction(
      itemKey: const ValueKey('editor-text-view-reset'),
      label: l10n.editorTextViewResetSize(
        commandShortcutLabel('0', l10n: l10n),
      ),
      icon: LucideIcons.rotateCcw,
      enabled: !view.isStandardTextSize,
      onSelected: () =>
          choose(view.copyWith(textSize: EditorTextView.standardTextSize)),
    ),
    for (final length in EditorLineLength.values)
      WpListMenuAction(
        itemKey: ValueKey('editor-text-view-line-${length.name}'),
        label: lengthLabel(length),
        icon: LucideIcons.wrapText,
        checked: view.lineLength == length,
        onSelected: () => choose(view.copyWith(lineLength: length)),
      ),
    for (final spacing in EditorLineSpacing.values)
      WpListMenuAction(
        itemKey: ValueKey('editor-text-view-spacing-${spacing.name}'),
        label: spacingLabel(spacing),
        icon: LucideIcons.listCollapse,
        checked: view.lineSpacing == spacing,
        onSelected: () => choose(view.copyWith(lineSpacing: spacing)),
      ),
  ];
}
