/// The menu button of the custom title bar on Windows and Linux (MZ-05,
/// MZ-06). It opens the same command tree as the macOS menu bar: the
/// Aufnahme entries, Settings and Help. Alt or F10 open it from the keyboard.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/config/settings_labels.dart' show formatHotkeyShortcut;
import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/locale_provider.dart';
import '../core/theme/tokens.dart';
import '../services/app_commands/menu_bar_adapter.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart'
    show l10nForLocaleCode;
import 'app_menu_bar.dart';
import 'wp_focus_ring.dart';

/// Ids of the title bar's own groups. The entries inside keep the menu bar's
/// ids, so an action runs the same command on both surfaces.
abstract final class WpTitleBarMenuGroupIds {
  static const recording = 'title-bar.recording';
  static const help = 'title-bar.help';
}

/// The title bar menu as nodes: the Aufnahme group, Settings, then the Help
/// group. [recording] is the menu bar's Aufnahme entries.
List<MenuBarNode> titleBarMenuNodes({
  required L10n l10n,
  required List<MenuBarNode> recording,
}) {
  final settingsShortcut = formatHotkeyShortcut(
    'ctrl',
    ',',
    l10n: l10n,
    isMacOS: false,
  );
  return [
    MenuBarNode(
      id: WpTitleBarMenuGroupIds.recording,
      label: l10n.menuBarMenuRecording,
      children: recording,
    ),
    const MenuBarNode.separator(),
    MenuBarNode(
      id: WpMenuBarCommandIds.settings,
      label: '${l10n.menuBarAppSettings} ($settingsShortcut)',
    ),
    const MenuBarNode.separator(),
    MenuBarNode(
      id: WpTitleBarMenuGroupIds.help,
      label: l10n.navHelp,
      children: [
        MenuBarNode(
          id: WpMenuBarCommandIds.helpManual,
          label: l10n.menuBarHelpManual,
        ),
        const MenuBarNode.separator(),
        MenuBarNode(
          id: WpMenuBarCommandIds.helpFeedback,
          label: l10n.menuBarHelpFeedback,
        ),
        MenuBarNode(
          id: WpMenuBarCommandIds.helpIdea,
          label: l10n.menuBarHelpIdea,
        ),
      ],
    ),
  ];
}

/// The title bar's menu button, in the actions slot left of the window
/// controls. Its menu is [titleBarMenuNodes] rendered as Material menus.
class WpTitleBarMenuButton extends ConsumerStatefulWidget {
  const WpTitleBarMenuButton({super.key});

  @override
  ConsumerState<WpTitleBarMenuButton> createState() =>
      _TitleBarMenuButtonState();
}

class _TitleBarMenuButtonState extends ConsumerState<WpTitleBarMenuButton> {
  final MenuController _controller = MenuController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'WpTitleBarMenuButton');
  final FocusNode _firstItemFocus = FocusNode(debugLabel: 'TitleBarMenuFirst');

  /// Alt went down and no other key followed: a bare Alt press opens the menu
  /// on release, so Alt combinations do not open it.
  bool _altAlone = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
    _focusNode.dispose();
    _firstItemFocus.dispose();
    super.dispose();
  }

  bool _onKeyEvent(KeyEvent event) {
    if (!mounted) return false;
    final key = event.logicalKey;
    final isAlt =
        key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight;
    if (event is KeyDownEvent) {
      if (key == LogicalKeyboardKey.f10) {
        _altAlone = false;
        _toggle();
        return true;
      }
      _altAlone = isAlt;
    } else if (event is KeyUpEvent && isAlt) {
      if (_altAlone) _toggle();
      _altAlone = false;
    }
    return false;
  }

  void _toggle() {
    if (_controller.isOpen) {
      _controller.close();
    } else {
      _controller.open();
      // Focus moves into the menu once its entries are built, so the arrow
      // keys, Enter and Escape work from the keyboard.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.isOpen) _firstItemFocus.requestFocus();
      });
    }
  }

  void _activate(MenuBarNode node) {
    unawaited(runMenuBarCommand(ref, node.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nForLocaleCode(ref.watch(localeProvider).languageCode);
    final nodes = titleBarMenuNodes(
      l10n: l10n,
      recording: ref.watch(menuBarRecordingCommandsProvider),
    );
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      menuChildren: _entries(nodes, firstFocus: _firstItemFocus),
      builder: (context, controller, child) => Semantics(
        identifier: 'title-bar-menu-button',
        label: l10n.titleBarMenuLabel,
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: WpFocusRing(
            focusNode: _focusNode,
            radius: 6,
            child: InkWell(
              key: const ValueKey('title-bar-menu-button'),
              focusNode: _focusNode,
              borderRadius: BorderRadius.circular(6),
              onTap: _toggle,
              child: const SizedBox(
                width: 40,
                height: 32,
                child: Icon(LucideIcons.menu, size: WpIconSize.sm),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _entries(List<MenuBarNode> nodes, {FocusNode? firstFocus}) {
    final first = nodes.indexWhere((n) => !n.isSeparator);
    return [
      for (final (index, node) in nodes.indexed)
        if (node.isSeparator)
          const Divider(height: 1)
        else
          _entry(node, focusNode: index == first ? firstFocus : null),
    ];
  }

  Widget _entry(MenuBarNode node, {FocusNode? focusNode}) {
    if (node.isSubmenu) {
      return SubmenuButton(
        focusNode: focusNode,
        key: ValueKey('title-bar-menu-group-${node.id}'),
        menuChildren: _entries(node.children),
        child: Semantics(
          identifier: 'title-bar-menu-group-${node.id}',
          child: Text(_plainLabel(node)),
        ),
      );
    }
    return MenuItemButton(
      focusNode: focusNode,
      key: ValueKey('title-bar-menu-item-${node.id}'),
      leadingIcon: node.checked == true
          ? const Icon(LucideIcons.check, size: WpIconSize.sm)
          : null,
      onPressed: node.enabled ? () => _activate(node) : null,
      child: Semantics(
        identifier: 'title-bar-menu-item-${node.id}',
        child: Text(_plainLabel(node)),
      ),
    );
  }
}

/// The label without the text checkmark: a checked entry gets a check icon.
String _plainLabel(MenuBarNode node) {
  if (node.checked != true || !node.label.startsWith(kMenuBarCheckMark)) {
    return node.label;
  }
  return node.label.substring(kMenuBarCheckMark.length);
}
