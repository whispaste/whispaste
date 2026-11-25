/// Smart Mode on the selection (#650), the editor half: the toolbar's menu,
/// the Ctrl/Cmd+J key and the field's context menu all offer the same four
/// [EditorSmartAction]s and hand the pick to the host's callback. What the
/// action then does (asking, the lock, the engine, the undo step) lives in
/// `features/smart_actions/`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/command_shortcut.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../services/smart_mode/editor_smart_action.dart';
import 'searchable_list_page.dart' show WpListMenuAction;

/// Name of [action] in menus; the two that ask first end in an ellipsis.
String editorSmartActionMenuLabel(L10n l10n, EditorSmartAction action) =>
    switch (action) {
      EditorSmartAction.cleanUp => l10n.smartModePresetCleanup,
      EditorSmartAction.shorten => l10n.smartModePresetConcise,
      EditorSmartAction.translate => l10n.editorSmartActionTranslate,
      EditorSmartAction.custom => l10n.editorSmartActionCustom,
    };

IconData editorSmartActionIcon(EditorSmartAction action) => switch (action) {
  EditorSmartAction.cleanUp => LucideIcons.wandSparkles,
  EditorSmartAction.shorten => LucideIcons.shrink,
  EditorSmartAction.translate => LucideIcons.languages,
  EditorSmartAction.custom => LucideIcons.penLine,
};

/// Ctrl/Cmd+J: opens the Smart Mode menu of the editor. Free in every editor
/// and on both pages; Ctrl/Cmd+Shift+J and the dictation hotkeys stay
/// untouched.
SingleActivator get editorSmartActionActivator =>
    commandActivator(LogicalKeyboardKey.keyJ);

/// How [editorSmartActionActivator] is spelled in a tooltip.
String editorSmartActionShortcutLabel(L10n l10n) =>
    commandShortcutLabel('J', l10n: l10n);

/// The four actions as menu rows, each with the testID
/// `<testIdPrefix>-toolbar-smart-<action>`.
List<WpListMenuAction> editorSmartActionMenuActions(
  BuildContext context, {
  required String testIdPrefix,
  required ValueChanged<EditorSmartAction> onAction,
}) {
  final l10n = L10n.of(context);
  return [
    for (final action in EditorSmartAction.values)
      WpListMenuAction(
        itemKey: ValueKey('$testIdPrefix-toolbar-smart-${action.name}'),
        label: editorSmartActionMenuLabel(l10n, action),
        icon: editorSmartActionIcon(action),
        onSelected: () => onAction(action),
      ),
  ];
}

/// The Smart Mode menu key of one editor: [WpTextEditor] owns the object and
/// binds Ctrl/Cmd+J in its text, the toolbar answers by opening the menu
/// under its button. Same attach/detach contract as `WpFindCommands`: the
/// toolbar is remounted per note.
class WpSmartActionCommands {
  VoidCallback? _open;
  Object? _owner;

  void attach(Object owner, {required VoidCallback open}) {
    _owner = owner;
    _open = open;
  }

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _open = null;
  }

  /// Opens the menu; false when no toolbar is there to show it.
  bool open() {
    final open = _open;
    if (open == null) return false;
    open();
    return true;
  }
}

/// Hands the editor's Smart Mode callback down to the text field, which
/// adds the four actions to its context menu. Without the scope, or on a
/// read-only field, the context menu stays the platform's.
class WpEditorSmartActionScope extends InheritedWidget {
  const WpEditorSmartActionScope({
    super.key,
    required this.onAction,
    required this.testIdPrefix,
    required super.child,
  });

  final ValueChanged<EditorSmartAction> onAction;

  /// The editor's testID prefix; the context menu rows carry
  /// `<testIdPrefix>-context-smart-<action>`.
  final String testIdPrefix;

  static WpEditorSmartActionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WpEditorSmartActionScope>();

  @override
  bool updateShouldNotify(WpEditorSmartActionScope oldWidget) =>
      onAction != oldWidget.onAction || testIdPrefix != oldWidget.testIdPrefix;
}

/// The platform's own context menu, what a [TextField] shows by default.
Widget editorDefaultContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) => AdaptiveTextSelectionToolbar.editableText(
  editableTextState: editableTextState,
);

/// One editor context menu: [leading] first (e.g. spell suggestions, #670),
/// then the platform's own entries, then the four Smart Mode actions when
/// [onSmartAction] is set (#650). Each Smart Mode row carries the testID
/// `<testIdPrefix>-context-smart-<action>`.
Widget editorContextMenu(
  BuildContext context,
  EditableTextState editableTextState, {
  List<ContextMenuButtonItem> leading = const [],
  ValueChanged<EditorSmartAction>? onSmartAction,
  String testIdPrefix = '',
}) {
  if (leading.isEmpty && onSmartAction == null) {
    return editorDefaultContextMenu(context, editableTextState);
  }
  final l10n = L10n.of(context);
  final head = [...leading, ...editableTextState.contextMenuButtonItems];
  final items = [
    ...head,
    if (onSmartAction != null)
      for (final action in EditorSmartAction.values)
        ContextMenuButtonItem(
          label: l10n.editorSmartActionContext(
            editorSmartActionMenuLabel(l10n, action),
          ),
          onPressed: () {
            // The caret and the selection stay; the action reads them.
            editableTextState.hideToolbar();
            onSmartAction(action);
          },
        ),
  ];
  // The platform's own look per system, plus a testID on each of ours.
  final buttons = AdaptiveTextSelectionToolbar.getAdaptiveButtons(
    context,
    items,
  ).toList();
  return AdaptiveTextSelectionToolbar(
    anchors: editableTextState.contextMenuAnchors,
    children: [
      for (var i = 0; i < buttons.length; i++)
        i < head.length
            ? buttons[i]
            : Semantics(
                identifier:
                    '$testIdPrefix-context-smart-'
                    '${EditorSmartAction.values[i - head.length].name}',
                child: buttons[i],
              ),
    ],
  );
}

/// Builds the context menu of a field from [leading] entries; see
/// [editorContextMenu].
typedef WpEditorContextMenuBuilder =
    Widget Function(
      BuildContext context,
      EditableTextState editableTextState,
      List<ContextMenuButtonItem> leading,
    );

/// The [WpEditorContextMenuBuilder] for a field: with the Smart Mode actions
/// below an [WpEditorSmartActionScope] and for an editable field, otherwise
/// the platform's entries only.
///
/// The scope is looked up from [fieldContext] (the field's own build
/// context): the builder itself runs in the overlay, outside the editor.
WpEditorContextMenuBuilder editorContextMenuFor(
  BuildContext fieldContext, {
  required bool readOnly,
}) {
  final scope = readOnly
      ? null
      : WpEditorSmartActionScope.maybeOf(fieldContext);
  return (context, editableTextState, leading) => editorContextMenu(
    context,
    editableTextState,
    leading: leading,
    onSmartAction: scope?.onAction,
    testIdPrefix: scope?.testIdPrefix ?? '',
  );
}

/// The context menu builder for a field below [WpEditorSmartActionScope]: the
/// platform's own entries, then the four Smart Mode actions. Null outside a
/// scope or for a read-only field, so the field keeps its default menu.
EditableTextContextMenuBuilder? editorSmartActionContextMenuBuilder(
  BuildContext fieldContext, {
  required bool readOnly,
}) {
  final scope = WpEditorSmartActionScope.maybeOf(fieldContext);
  if (scope == null || readOnly) return null;
  final menu = editorContextMenuFor(fieldContext, readOnly: readOnly);
  return (context, editableTextState) =>
      menu(context, editableTextState, const []);
}
