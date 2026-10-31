// Menu bar structure, the standard Edit commands and the disabled-entry rule.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/navigation/help_target.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/features/feedback/feedback_type.dart';
import 'package:whispaste/services/app_commands/menu_bar_adapter.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/app_menu_bar.dart';

Iterable<PlatformMenuItem> _allItems(List<PlatformMenuItem> items) sync* {
  for (final item in items) {
    yield item;
    if (item is PlatformMenu) yield* _allItems(item.menus);
    if (item is PlatformMenuItemGroup) yield* _allItems(item.members);
  }
}

PlatformMenuItem _item(List<PlatformMenu> menus, String label) => _allItems(
  menus,
).singleWhere((item) => item is! PlatformMenu && item.label == label);

void main() {
  final en = lookupL10n(const Locale('en'));
  final de = lookupL10n(const Locale('de'));

  test('the Edit menu has the standard commands with their shortcuts', () {
    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [],
      activate: (_) {},
    );
    final edit = menus.singleWhere((m) => m.label == en.menuBarMenuEdit);
    final labels = [
      for (final item in _allItems(edit.menus))
        if (item is! PlatformMenuItemGroup) item.label,
    ];

    expect(labels, [
      en.menuBarEditUndo,
      en.menuBarEditRedo,
      en.menuBarEditCut,
      en.menuBarEditCopy,
      en.menuBarEditPaste,
      en.menuBarEditSelectAll,
    ]);
    SingleActivator shortcut(String label) =>
        _item([edit], label).shortcut! as SingleActivator;
    expect(shortcut(en.menuBarEditUndo).trigger, LogicalKeyboardKey.keyZ);
    expect(shortcut(en.menuBarEditUndo).meta, isTrue);
    expect(shortcut(en.menuBarEditRedo).shift, isTrue);
    expect(shortcut(en.menuBarEditCut).trigger, LogicalKeyboardKey.keyX);
    expect(shortcut(en.menuBarEditCopy).trigger, LogicalKeyboardKey.keyC);
    expect(shortcut(en.menuBarEditPaste).trigger, LogicalKeyboardKey.keyV);
    expect(shortcut(en.menuBarEditSelectAll).trigger, LogicalKeyboardKey.keyA);
  });

  test('the menus come in macOS order and the app language', () {
    final menus = buildAppMenus(
      l10n: de,
      recordingNodes: const [],
      activate: (_) {},
    );
    expect(menus.map((m) => m.label), [
      'WhisPaste',
      de.menuBarMenuEdit,
      de.menuBarMenuWindow,
      de.navHelp,
    ]);
    expect(_item(menus, de.menuBarEditSelectAll).label, 'Alles auswählen');
  });

  test('Quit goes through the activate callback and binds Cmd+Q', () {
    final activated = <String>[];
    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [],
      activate: activated.add,
    );
    final quit = _item(menus, en.menuBarAppQuit);
    final shortcut = quit.shortcut! as SingleActivator;
    expect(shortcut.trigger, LogicalKeyboardKey.keyQ);
    expect(shortcut.meta, isTrue);
    quit.onSelected!();
    expect(activated, ['quit']);
  });

  test('recording entries follow the enabled flag', () {
    final activated = <String>[];
    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [
        MenuBarNode(id: 'toggle_recording', label: 'Start'),
        MenuBarNode(id: 'stt-locked', label: 'Locked', enabled: false),
      ],
      activate: activated.add,
    );
    final recording = menus.singleWhere(
      (m) => m.label == en.menuBarMenuRecording,
    );
    final start = _item([recording], 'Start');
    expect(start.onSelected, isNotNull);
    start.onSelected!();
    expect(activated, ['toggle_recording']);
    expect(_item([recording], 'Locked').onSelected, isNull);
  });

  testWidgets('Select All from the menu selects the focused text field', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'hello world');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      ),
    );
    await tester.pump();

    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [],
      activate: (_) {},
    );
    _item(menus, en.menuBarEditSelectAll).onSelected!();
    await tester.pump();

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 11),
    );
  });

  testWidgets('Cmd+, brings the window forward and opens the settings page', (
    tester,
  ) async {
    var windowActivated = 0;
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          windowActivatorProvider.overrideWithValue(() async {
            windowActivated++;
          }),
        ],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );

    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [],
      activate: (_) {},
    );
    final settings = _item(menus, en.menuBarAppSettings);
    final shortcut = settings.shortcut! as SingleActivator;
    expect(shortcut.trigger, LogicalKeyboardKey.comma);
    expect(shortcut.meta, isTrue);

    await runMenuBarCommand(ref, WpMenuBarCommandIds.settings);

    expect(windowActivated, 1);
    expect(ref.read(activePageProvider), 'settings');
  });

  testWidgets('the Help menu opens the manual and the feedback page', (
    tester,
  ) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [windowActivatorProvider.overrideWithValue(() async {})],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );

    final menus = buildAppMenus(
      l10n: en,
      recordingNodes: const [],
      activate: (_) {},
    );
    final help = menus.firstWhere((m) => m.label == en.navHelp);
    final helpLabels = [
      for (final m in help.menus)
        if (m is PlatformMenuItemGroup) ...m.members else m,
    ].map((i) => i.label);
    expect(helpLabels, [
      en.menuBarHelpManual,
      en.menuBarHelpContact,
      en.menuBarHelpFeedback,
      en.menuBarHelpIdea,
    ]);

    await runMenuBarCommand(ref, WpMenuBarCommandIds.helpManual);
    expect(ref.read(helpTargetProvider)?.tab, HelpTab.manual);
    expect(ref.read(activePageProvider), 'help');

    await runMenuBarCommand(ref, WpMenuBarCommandIds.helpFeedback);
    expect(ref.read(activePageProvider), 'feedback');
  });

  testWidgets('Contact us from the Help menu opens the contact form', (
    tester,
  ) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [windowActivatorProvider.overrideWithValue(() async {})],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );

    await runMenuBarCommand(ref, WpMenuBarCommandIds.helpContact);
    expect(ref.read(activePageProvider), 'feedback');
    expect(ref.read(feedbackPresetTypeProvider), isNull);
  });

  test(
    'About, Hide, Hide Others and Show All are own entries with actions',
    () {
      final activated = <String>[];
      final menus = buildAppMenus(
        l10n: de,
        recordingNodes: const [],
        activate: activated.add,
      );
      final app = menus.first;
      for (final label in [
        de.menuBarAppAbout,
        de.menuBarAppHide,
        de.menuBarAppHideOthers,
        de.menuBarAppShowAll,
      ]) {
        _item([app], label).onSelected!();
      }
      expect(activated, [
        WpMenuBarCommandIds.appAbout,
        WpMenuBarCommandIds.appHide,
        WpMenuBarCommandIds.appHideOthers,
        WpMenuBarCommandIds.appShowAll,
      ]);
      final hideOthers =
          _item([app], de.menuBarAppHideOthers).shortcut! as SingleActivator;
      expect(hideOthers.trigger, LogicalKeyboardKey.keyH);
      expect(hideOthers.alt, isTrue);
    },
  );

  testWidgets('About opens Settings on the About area', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [windowActivatorProvider.overrideWithValue(() async {})],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const SizedBox();
          },
        ),
      ),
    );

    await runMenuBarCommand(ref, WpMenuBarCommandIds.appAbout);

    expect(ref.read(activePageProvider), 'settings');
    expect(ref.read(settingsScrollTargetProvider), 'about');
  });
}
