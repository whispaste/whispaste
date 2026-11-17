/// Where the recording dock sits in the window (ticket, chat-08): inside the
/// content panel, right of the sidebar, on the panel's bottom edge, at every
/// window size and in focus mode. Measured from the laid-out boxes.
///
/// The store/website screenshot shell once carried its own copy of this
/// layout and drew the dock across the whole window below the sidebar; the
/// guard at the end keeps it on [WpAppShell].
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/app_shell.dart';

const _titleKey = ValueKey('title');
const _sidebarKey = ValueKey('sidebar');
const _contentKey = ValueKey('content');
const _dockKey = ValueKey('dock');

Widget _shell({bool focusMode = false}) => MaterialApp(
  home: WpAppShell(
    titleBar: const SizedBox(key: _titleKey, height: 40),
    sidebar: const SizedBox(
      key: _sidebarKey,
      width: 220,
      height: double.infinity,
    ),
    content: const SizedBox.expand(key: _contentKey),
    dock: const SizedBox(key: _dockKey, height: 76, width: double.infinity),
    contentDecoration: const BoxDecoration(color: Color(0xFFFFFFFF)),
    focusMode: focusMode,
  ),
);

void main() {
  for (final size in const [
    Size(800, 600),
    Size(1440, 900),
    Size(1920, 1080),
  ]) {
    testWidgets('dock sits inside the content panel at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_shell());

      final sidebar = tester.getRect(find.byKey(_sidebarKey));
      final title = tester.getRect(find.byKey(_titleKey));
      final content = tester.getRect(find.byKey(_contentKey));
      final dock = tester.getRect(find.byKey(_dockKey));

      // Right of the sidebar, never under it.
      expect(dock.left, sidebar.right);
      expect(dock.right, size.width);
      // Under the page, on the window's bottom edge, beside the sidebar.
      expect(dock.top, content.bottom);
      expect(dock.bottom, size.height);
      expect(dock.top, greaterThan(title.bottom));
      expect(sidebar.bottom, size.height);
      expect(content.left, dock.left);
    });
  }

  testWidgets('focus mode keeps the dock under the page', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_shell(focusMode: true));

    final content = tester.getRect(find.byKey(_contentKey));
    final dock = tester.getRect(find.byKey(_dockKey));
    expect(dock.top, content.bottom);
    expect(dock.left, content.left);
    expect(dock.right, content.right);
    expect(dock.bottom, 900);
  });

  test('the screenshot shell lays out with WpAppShell', () {
    final source = File(
      'generators/store/screenshot_shell.dart',
    ).readAsStringSync();
    expect(source, contains('WpAppShell('));
  });
}
