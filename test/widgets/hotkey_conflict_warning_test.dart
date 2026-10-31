/// Widget tests for [WpHotkeyConflictWarning], the one warning both the hotkey
/// recorder and the dictation trigger dialog show: the reserved function and
/// the one next step. Covers text scale 1.3 at 800 px and RTL. No goldens.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/widgets/hotkey_recorder.dart';

import '../fixtures/test_helpers.dart';

const _fnEntry = ConflictEntry(
  modifiers: '',
  key: 'Fn',
  note: ConflictNote.fnDoubleTap,
  action: ConflictAction.disableInSystem,
  doubleTapKey: 'fn',
);

const _winHEntry = ConflictEntry(
  modifiers: 'meta',
  key: 'H',
  note: ConflictNote.windowsDictation,
);

Future<void> _pump(
  WidgetTester tester,
  ConflictEntry entry, {
  required Locale locale,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = const Size(800, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    makeTestable(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SizedBox(
          width: 360,
          child: WpHotkeyConflictWarning(
            conflict: entry,
            l10n: lookupL10n(locale),
          ),
        ),
      ),
      size: const Size(800, 900),
      locale: locale,
    ),
  );
  await tester.pump();
}

void main() {
  final en = lookupL10n(const Locale('en'));

  testWidgets('Linux names the desktop as the reserving party (PAR-063)', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      makeTestable(
        SizedBox(
          width: 360,
          child: WpHotkeyConflictWarning(
            conflict: const ConflictEntry(
              modifiers: 'meta',
              key: 'Space',
              note: ConflictNote.inputSourceGnome,
            ),
            l10n: en,
            isLinux: true,
          ),
        ),
        size: const Size(800, 900),
        locale: const Locale('en'),
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'This key combination is reserved by your desktop: '
        'Switch input source (GNOME). It may not work.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('reserved by Linux'), findsNothing);
  });

  testWidgets('Wayland: the dialog says the desktop sets the shortcut before '
      'Save (PAR-060); elsewhere it does not', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> pump({required bool isWayland}) => tester.pumpWidget(
      makeTestable(
        WpHotkeyRecorderDialog(
          initialKey: 'D',
          initialModifiers: 'ctrl+shift',
          isWayland: isWayland,
        ),
        size: const Size(800, 900),
        locale: const Locale('en'),
      ),
    );

    await pump(isWayland: true);
    await tester.pump();
    expect(find.byKey(const Key('hotkeyDesktopBindingHint')), findsOneWidget);
    expect(find.text(en.waylandHotkeyBoundNoTrigger), findsOneWidget);

    await pump(isWayland: false);
    await tester.pump();
    expect(find.byKey(const Key('hotkeyDesktopBindingHint')), findsNothing);
  });

  testWidgets('names the reserved function and the disable action', (
    tester,
  ) async {
    await _pump(tester, _fnEntry, locale: const Locale('en'));

    expect(
      find.textContaining(en.hotkeyConflictNoteFnDoubleTap),
      findsOneWidget,
    );
    expect(
      find.text(en.hotkeyConflictActionDisableMacDictation),
      findsOneWidget,
    );
    expect(find.text(en.hotkeyConflictActionChooseOther), findsOneWidget);
  });

  testWidgets('a combination shows the choose-another action', (tester) async {
    await _pump(tester, _winHEntry, locale: const Locale('en'));

    expect(
      find.textContaining(en.hotkeyConflictNoteWindowsDictation),
      findsOneWidget,
    );
    expect(find.text(en.hotkeyConflictActionChooseOther), findsOneWidget);
  });
}
