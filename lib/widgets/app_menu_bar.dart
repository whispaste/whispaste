/// The macOS menu bar, built from Dart (MZ-02 to MZ-04).
///
/// `PlatformMenuBar` replaces the native main menu of `MainMenu.xib` while the
/// app runs (`FlutterMenuPlugin` sets `NSApp.mainMenu`), so every title comes
/// from the app's ARB files and follows the app language. Only macOS builds
/// the bar; Windows and Linux keep their own title bar (MZ-05/06).
///
/// Editing commands use Flutter's text intents, not custom actions: the menu
/// item only forwards Cmd+C/V/X/Z/A to the focused text field, so the keys
/// keep working as before.
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../core/config/selectable_speech_models.dart';
import '../core/config/settings_provider.dart';
import '../core/l10n/generated/app_localizations.dart';
import '../core/l10n/locale_provider.dart';
import '../core/navigation/help_target.dart';
import '../core/navigation/page_state.dart';
import '../core/platform/macos_lifecycle_channel.dart';
import '../core/recording/recording_state.dart';
import '../features/feedback/feedback_type.dart';
import '../services/app_commands/menu_bar_adapter.dart';
import '../services/app_commands/menu_bar_commands.dart';
import '../services/app_profiles/app_profile_choice.dart';
import '../services/app_profiles/app_profile_repository.dart';
import '../services/audio_service.dart';
import '../services/microphone_selection_service.dart';
import '../services/permissions/tcc_entry_reset_confirm.dart'
    show l10nForLocaleCode;
import '../services/app_commands/tray_command_catalog.dart';
import '../services/tray_service.dart';
import '../services/window_activation.dart';

/// Ids of the menu bar's own commands. Tray ids are reused where a command
/// exists in both surfaces, so an id means the same thing on both.
abstract final class WpMenuBarCommandIds {
  static const settings = 'settings';
  static const appAbout = 'app.about';
  static const appHide = 'app.hide';
  static const appHideOthers = 'app.hideOthers';
  static const appShowAll = 'app.showAll';
  static const helpManual = 'help.manual';
  static const helpFeedback = 'help.feedback';
  static const helpIdea = 'help.idea';
  static const quit = 'quit';
  static const minimize = 'window.minimize';
  static const zoom = 'window.zoom';
}

/// The app navigator. Its context sits under the app's toast overlay, so
/// notices raised from a menu command (a link that did not open) are visible.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Whether the menu bar is built on this platform.
bool get _menuBarPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// The menu bar of the app: the platform menu on macOS, the child elsewhere.
/// The Aufnahme menu entries, rebuilt whenever the state they show changes
/// (recording phase, settings, models, profiles, microphones, locale).
final menuBarRecordingCommandsProvider = Provider<List<MenuBarNode>>((ref) {
  final l10n = l10nForLocaleCode(ref.watch(localeProvider).languageCode);
  final settings = ref.watch(settingsProvider).value;
  final commands = trayCommandTree(
    l10n,
    recording: ref.watch(recordingProvider),
    micDeviceLabels:
        ref.watch(audioInputDevicesProvider).value ?? const [micDefaultLabel],
    settings: settings,
    choices: settings == null
        ? null
        : speechChoicesFor(
            l10n,
            models: ref.watch(selectableSpeechModelsProvider),
            missing: ref.watch(missingSelectedSpeechModelProvider),
          ),
    profiles: ref.watch(appProfilesProvider).value ?? const [],
    profileChoice: ref.watch(profileChoiceProvider),
    actionNeeded: null,
    sidePanelAvailable: false,
  );
  final labels = trayLabelsFor(l10n);
  return menuBarNodes(
    recordingMenuCommands(commands),
    labelOf: (key) => labels[key] ?? key,
  );
});

class WpAppMenuBarHost extends ConsumerWidget {
  const WpAppMenuBarHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_menuBarPlatform) return child;
    final l10n = l10nForLocaleCode(ref.watch(localeProvider).languageCode);
    final menus = buildAppMenus(
      l10n: l10n,
      recordingNodes: ref.watch(menuBarRecordingCommandsProvider),
      activate: (id) => unawaited(runMenuBarCommand(ref, id)),
    );
    return PlatformMenuBar(menus: menus, child: child);
  }
}

/// Runs the action of the menu bar command [id].
Future<void> runMenuBarCommand(WidgetRef ref, String id) async {
  switch (id) {
    case WpMenuBarCommandIds.settings:
      await _showPage(ref, 'settings');
    case WpMenuBarCommandIds.appAbout:
      ref.read(settingsScrollTargetProvider.notifier).set('about');
      await _showPage(ref, 'settings');
    case WpMenuBarCommandIds.appHide:
      await windowManager.hide();
    case WpMenuBarCommandIds.appHideOthers:
      await MacOSLifecycleChannel.hideOtherApplications();
    case WpMenuBarCommandIds.appShowAll:
      await MacOSLifecycleChannel.unhideAllApplications();
    case WpMenuBarCommandIds.helpManual:
      ref
          .read(helpTargetProvider.notifier)
          .set(const HelpTarget(tab: HelpTab.manual));
      await _showPage(ref, 'help');
    case WpMenuBarCommandIds.helpFeedback:
      ref.read(feedbackPresetTypeProvider.notifier).set(null);
      await _showPage(ref, 'feedback');
    case WpMenuBarCommandIds.helpIdea:
      // The same form as Feedback, with the type set to Idea: it offers the
      // ideas board link itself.
      ref.read(feedbackPresetTypeProvider.notifier).set(FeedbackType.idea);
      await _showPage(ref, 'feedback');
    case WpMenuBarCommandIds.minimize:
      await windowManager.minimize();
    case WpMenuBarCommandIds.zoom:
      final maximized = await windowManager.isMaximized();
      await (maximized ? windowManager.unmaximize() : windowManager.maximize());
    default:
      ref.read(trayServiceProvider.notifier).activateCommand(id);
  }
}

/// Brings the window forward (it may be hidden in the tray) and shows [page].
Future<void> _showPage(WidgetRef ref, String page) async {
  await ref.read(windowActivatorProvider)();
  ref.read(activePageProvider.notifier).setPage(page);
}

/// The top-level menus, in macOS order: the app menu, the recording menu (when
/// [recordingNodes] is not empty), Edit and Window.
///
/// [activate] receives the id of every entry that is an action, see
/// [runMenuBarCommand]. Entries without an action are disabled.
List<PlatformMenu> buildAppMenus({
  required L10n l10n,
  required List<MenuBarNode> recordingNodes,
  required void Function(String id) activate,
}) => [
  PlatformMenu(
    label: 'WhisPaste',
    menus: [
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarAppAbout,
            onSelected: () => activate(WpMenuBarCommandIds.appAbout),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarAppSettings,
            shortcut: _key(LogicalKeyboardKey.comma),
            onSelected: () => activate(WpMenuBarCommandIds.settings),
          ),
        ],
      ),
      const PlatformMenuItemGroup(
        members: [
          PlatformProvidedMenuItem(
            type: PlatformProvidedMenuItemType.servicesSubmenu,
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarAppHide,
            shortcut: _key(LogicalKeyboardKey.keyH),
            onSelected: () => activate(WpMenuBarCommandIds.appHide),
          ),
          PlatformMenuItem(
            label: l10n.menuBarAppHideOthers,
            shortcut: _key(LogicalKeyboardKey.keyH, alt: true),
            onSelected: () => activate(WpMenuBarCommandIds.appHideOthers),
          ),
          PlatformMenuItem(
            label: l10n.menuBarAppShowAll,
            onSelected: () => activate(WpMenuBarCommandIds.appShowAll),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarAppQuit,
            shortcut: _key(LogicalKeyboardKey.keyQ),
            onSelected: () => activate(WpMenuBarCommandIds.quit),
          ),
        ],
      ),
    ],
  ),
  if (recordingNodes.isNotEmpty)
    PlatformMenu(
      label: l10n.menuBarMenuRecording,
      menus: _menuItems(recordingNodes, activate),
    ),
  PlatformMenu(
    label: l10n.menuBarMenuEdit,
    menus: [
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarEditUndo,
            shortcut: _key(LogicalKeyboardKey.keyZ),
            onSelected: () => _editIntent(const UndoTextIntent(_cause)),
          ),
          PlatformMenuItem(
            label: l10n.menuBarEditRedo,
            shortcut: _key(LogicalKeyboardKey.keyZ, shift: true),
            onSelected: () => _editIntent(const RedoTextIntent(_cause)),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarEditCut,
            shortcut: _key(LogicalKeyboardKey.keyX),
            onSelected: () =>
                _editIntent(const CopySelectionTextIntent.cut(_cause)),
          ),
          PlatformMenuItem(
            label: l10n.menuBarEditCopy,
            shortcut: _key(LogicalKeyboardKey.keyC),
            onSelected: () => _editIntent(CopySelectionTextIntent.copy),
          ),
          PlatformMenuItem(
            label: l10n.menuBarEditPaste,
            shortcut: _key(LogicalKeyboardKey.keyV),
            onSelected: () => _editIntent(const PasteTextIntent(_cause)),
          ),
        ],
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarEditSelectAll,
            shortcut: _key(LogicalKeyboardKey.keyA),
            onSelected: () => _editIntent(const SelectAllTextIntent(_cause)),
          ),
        ],
      ),
    ],
  ),
  PlatformMenu(
    label: l10n.menuBarMenuWindow,
    menus: [
      PlatformMenuItem(
        label: l10n.menuBarWindowMinimize,
        shortcut: _key(LogicalKeyboardKey.keyM),
        onSelected: () => activate(WpMenuBarCommandIds.minimize),
      ),
      PlatformMenuItem(
        label: l10n.menuBarWindowZoom,
        onSelected: () => activate(WpMenuBarCommandIds.zoom),
      ),
    ],
  ),
  PlatformMenu(
    label: l10n.navHelp,
    menus: [
      PlatformMenuItem(
        label: l10n.menuBarHelpManual,
        onSelected: () => activate(WpMenuBarCommandIds.helpManual),
      ),
      PlatformMenuItemGroup(
        members: [
          PlatformMenuItem(
            label: l10n.menuBarHelpFeedback,
            onSelected: () => activate(WpMenuBarCommandIds.helpFeedback),
          ),
          PlatformMenuItem(
            label: l10n.menuBarHelpIdea,
            onSelected: () => activate(WpMenuBarCommandIds.helpIdea),
          ),
        ],
      ),
    ],
  ),
];

const _cause = SelectionChangedCause.keyboard;

/// A Cmd shortcut, with Shift when [shift] is set.
SingleActivator _key(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) => SingleActivator(key, meta: true, shift: shift, alt: alt);

/// Runs [intent] on the focused widget, as a key press would. Does nothing
/// when no widget has focus, so an unfocused Cmd+C is a no-op rather than a
/// null-check failure (the framework's own handler assumes a focus).
void _editIntent(Intent intent) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context != null) Actions.maybeInvoke(context, intent);
}

/// Menu items for [nodes], with separators turned into item groups.
List<PlatformMenuItem> _menuItems(
  List<MenuBarNode> nodes,
  void Function(String id) activate,
) {
  final groups = <PlatformMenuItem>[];
  var current = <PlatformMenuItem>[];
  void flush() {
    if (current.isEmpty) return;
    groups.add(PlatformMenuItemGroup(members: current));
    current = <PlatformMenuItem>[];
  }

  for (final node in nodes) {
    if (node.isSeparator) {
      flush();
    } else {
      current.add(_itemFor(node, activate));
    }
  }
  flush();
  return groups;
}

PlatformMenuItem _itemFor(MenuBarNode node, void Function(String id) activate) {
  if (node.isSubmenu) {
    return PlatformMenu(
      label: node.label,
      menus: _menuItems(node.children, activate),
    );
  }
  return PlatformMenuItem(
    label: node.label,
    shortcut: _activatorFor(node.keyEquivalent),
    onSelected: node.enabled ? () => activate(node.id) : null,
  );
}

/// The key equivalent of a logical shortcut such as `mod+,`, or null.
SingleActivator? _activatorFor(String? logical) {
  if (logical == null) return null;
  // Only single characters are bound (see menu_bar_adapter.dart), so the key
  // is the character after the `mod+` prefix, and its key id is its code unit.
  final key = LogicalKeyboardKey.findKeyByKeyId(
    logical.codeUnitAt(logical.length - 1),
  );
  return key == null ? null : SingleActivator(key, meta: true);
}
