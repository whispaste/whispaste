/// UX-108 and UX-109: the Wayland hint ("the desktop sets the shortcut") is
/// left-aligned at body size like the other dialog hints, and the hotkey
/// recorder's one-line `show()` passes `isWayland` through so the hint is
/// reachable and testable. No goldens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../fixtures/test_helpers.dart';

const _hintKey = Key('hotkeyDesktopBindingHint');

void main() {
  testWidgets('show() passes isWayland through: the hint appears (UX-109)', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  WpHotkeyRecorderDialog.show(context, isWayland: true),
              child: const Text('open-recorder'),
            ),
          ),
        ),
        size: const Size(800, 716),
        locale: const Locale('en'),
      ),
    );

    await tester.tap(find.text('open-recorder'));
    await tester.pumpAndSettle();

    expect(find.byKey(_hintKey), findsOneWidget);
  });

  testWidgets('show() with isWayland false keeps the hint away', (
    tester,
  ) async {
    await tester.pumpWidget(
      makeTestable(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  WpHotkeyRecorderDialog.show(context, isWayland: false),
              child: const Text('open-recorder'),
            ),
          ),
        ),
        size: const Size(800, 716),
        locale: const Locale('en'),
      ),
    );

    await tester.tap(find.text('open-recorder'));
    await tester.pumpAndSettle();

    expect(find.byKey(_hintKey), findsNothing);
  });
}
