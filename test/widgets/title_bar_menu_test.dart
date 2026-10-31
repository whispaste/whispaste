import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/core/l10n/locale_provider.dart';
import 'package:whispaste/core/navigation/page_state.dart';
import 'package:whispaste/services/app_commands/app_command.dart';
import 'package:whispaste/services/app_commands/menu_bar_adapter.dart';
import 'package:whispaste/services/app_commands/tray_command_catalog.dart';
import 'package:whispaste/services/window_activation.dart';
import 'package:whispaste/widgets/app_menu_bar.dart';
import 'package:whispaste/widgets/title_bar_menu.dart';

/// The Aufnahme entries the way the tray tree produces them.
List<MenuBarNode> _recordingNodes({required bool checkedDe}) => menuBarNodes([
  const AppCommand(
    id: TrayCommandIds.toggleRecording,
    labelKey: 'start',
    shortcut: '⌃⌥D',
  ),
  const AppCommand.separator(),
  AppCommand(
    id: TrayCommandIds.language,
    labelKey: 'lang',
    children: [
      AppCommand(id: 'lang:de', labelKey: 'de', checked: checkedDe),
      const AppCommand(id: 'lang:en', labelKey: 'en'),
    ],
  ),
], labelOf: (key) => key);

Widget _app({required List<MenuBarNode> recording, required Widget child}) {
  return ProviderScope(
    overrides: [
      localeProvider.overrideWithValue(const Locale('en')),
      menuBarRecordingCommandsProvider.overrideWithValue(recording),
      windowActivatorProvider.overrideWithValue(() async {}),
    ],
    child: MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: child),
      ),
    ),
  );
}

void main() {
  final en = lookupL10n(const Locale('en'));

  test('the title bar menu carries the menu bar ids and checkmarks', () {
    final recording = _recordingNodes(checkedDe: true);
    final nodes = titleBarMenuNodes(l10n: en, recording: recording);

    expect(nodes.where((n) => !n.isSeparator).map((n) => n.id), [
      WpTitleBarMenuGroupIds.recording,
      WpMenuBarCommandIds.settings,
      WpTitleBarMenuGroupIds.help,
    ]);
    final groupChildren = nodes.first.children;
    expect(
      groupChildren.map((n) => n.id),
      recording.map((n) => n.id),
      reason: 'same ids and order as the menu bar Aufnahme entries',
    );
    final language = groupChildren.firstWhere((n) => n.id == 'lang-submenu');
    expect(language.children.map((n) => n.checked), [
      true,
      null,
    ], reason: 'same checked state as the menu bar');
    expect(
      language.children.map((n) => n.label),
      recording
          .firstWhere((n) => n.id == 'lang-submenu')
          .children
          .map((n) => n.label),
    );
  });

  test('Help holds Manual, Contact, Feedback and Idea in that order', () {
    final help = titleBarMenuNodes(
      l10n: en,
      recording: const [],
    ).firstWhere((n) => n.id == WpTitleBarMenuGroupIds.help);

    expect(help.children.where((n) => !n.isSeparator).map((n) => n.id), [
      WpMenuBarCommandIds.helpManual,
      WpMenuBarCommandIds.helpContact,
      WpMenuBarCommandIds.helpFeedback,
      WpMenuBarCommandIds.helpIdea,
    ]);
  });

  testWidgets('F10 opens the menu and Escape closes it', (tester) async {
    await tester.pumpWidget(
      _app(
        recording: _recordingNodes(checkedDe: false),
        child: const WpTitleBarMenuButton(),
      ),
    );
    expect(find.text(en.menuBarAppSettings, skipOffstage: false), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(find.textContaining(en.menuBarAppSettings), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.textContaining(en.menuBarAppSettings), findsNothing);
  });

  testWidgets('a bare Alt press opens the menu, Alt with a key does not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        recording: _recordingNodes(checkedDe: false),
        child: const WpTitleBarMenuButton(),
      ),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining(en.menuBarAppSettings), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.textContaining(en.menuBarAppSettings), findsNothing);
  });

  testWidgets('arrow keys and Enter run Settings and show the page', (
    tester,
  ) async {
    late WidgetRef ref;
    var activated = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWithValue(const Locale('en')),
          menuBarRecordingCommandsProvider.overrideWithValue(
            _recordingNodes(checkedDe: false),
          ),
          windowActivatorProvider.overrideWithValue(() async {
            activated++;
          }),
        ],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return const MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: WpTitleBarMenuButton(),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    // Entries: the Aufnahme group first, then Settings.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(activated, 1);
    expect(ref.read(activePageProvider), 'settings');
  });

  testWidgets('every entry has a stable test id', (tester) async {
    await tester.pumpWidget(
      _app(
        recording: _recordingNodes(checkedDe: false),
        child: const WpTitleBarMenuButton(),
      ),
    );
    expect(find.bySemanticsIdentifier('title-bar-menu-button'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(
        'title-bar-menu-item-${WpMenuBarCommandIds.settings}',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(
        'title-bar-menu-group-${WpTitleBarMenuGroupIds.help}',
      ),
      findsOneWidget,
    );
  });
}
