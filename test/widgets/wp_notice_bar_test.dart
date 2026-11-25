// What a click, a key or the clock does to the notice bar (#455): the logic
// behind the notice that replaced the toasts, not its look.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/widgets/wp_notice_bar.dart';

late BuildContext _context;

Widget _host({Widget? field, Locale locale = const Locale('en')}) =>
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              _context = context;
              return Column(
                children: [
                  Expanded(child: field ?? const SizedBox.expand()),
                  const WpNoticeBar(),
                ],
              );
            },
          ),
        ),
      ),
    );

Finder _notice(String id) => find.byKey(ValueKey('notice-bar-$id'));

Future<void> _show(WidgetTester tester, WpNotice notice) async {
  showWpNotice(_context, notice);
  await tester.pumpAndSettle();
}

WpNotice _undo(String id, {VoidCallback? onAction, VoidCallback? onGone}) =>
    WpNotice(
      id: id,
      message: 'Moved to trash',
      kind: WpNoticeKind.undo,
      actionLabel: 'Undo',
      onAction: onAction,
      onDismissed: onGone,
    );

void main() {
  testWidgets('a lasting notice follows a language switch (#1845)', (
    tester,
  ) async {
    await tester.pumpWidget(_host(locale: const Locale('de')));
    final de = L10n.of(_context);
    await _show(
      tester,
      WpNotice(
        id: 'tray',
        kind: WpNoticeKind.warning,
        message: de.trayLinuxNoTrayHost,
        messageFor: (l10n) => l10n.trayLinuxNoTrayHost,
        actionLabel: de.settingsChangeHotkey,
        actionLabelFor: (l10n) => l10n.settingsChangeHotkey,
        onAction: () {},
      ),
    );
    expect(find.textContaining(de.trayLinuxNoTrayHost), findsOneWidget);

    // Same ProviderScope state: only the app language changes.
    await tester.pumpWidget(_host(locale: const Locale('en')));
    await tester.pumpAndSettle();
    final en = L10n.of(_context);
    expect(en.trayLinuxNoTrayHost, isNot(de.trayLinuxNoTrayHost));
    expect(find.textContaining(en.trayLinuxNoTrayHost), findsOneWidget);
    expect(find.textContaining(de.trayLinuxNoTrayHost), findsNothing);
    expect(find.text(en.settingsChangeHotkey), findsOneWidget);
  });

  testWidgets('the action runs once and closes the notice', (tester) async {
    await tester.pumpWidget(_host());
    var runs = 0;
    var gone = 0;
    await _show(
      tester,
      _undo('a', onAction: () => runs++, onGone: () => gone++),
    );

    await tester.tap(find.byKey(const ValueKey('notice-bar-action-a')));
    await tester.pumpAndSettle();

    expect(runs, 1);
    expect(gone, 1);
    expect(_notice('a'), findsNothing);
  });

  testWidgets('the close button closes only its notice', (tester) async {
    await tester.pumpWidget(_host());
    await _show(
      tester,
      const WpNotice(
        id: 'w',
        message: 'Hotkey lost',
        kind: WpNoticeKind.warning,
      ),
    );
    await _show(
      tester,
      const WpNotice(id: 'e', message: 'Save failed', kind: WpNoticeKind.error),
    );

    await tester.tap(find.byKey(const ValueKey('notice-bar-close-w')));
    await tester.pumpAndSettle();

    expect(_notice('w'), findsNothing);
    expect(_notice('e'), findsOneWidget);
  });

  testWidgets('a newer undo replaces the older one and ends it', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    var oldGone = 0;
    await _show(tester, _undo('old', onAction: () {}, onGone: () => oldGone++));
    await _show(tester, _undo('new', onAction: () {}));

    expect(_notice('old'), findsNothing);
    expect(_notice('new'), findsOneWidget);
    expect(oldGone, 1);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('a full bar never pushes out an error', (tester) async {
    await tester.pumpWidget(_host());
    await _show(
      tester,
      const WpNotice(id: 'e', message: 'Save failed', kind: WpNoticeKind.error),
    );
    for (final id in ['h1', 'h2', 'h3']) {
      await _show(tester, WpNotice(id: id, message: id));
    }

    expect(_notice('e'), findsOneWidget);
    expect(_notice('h1'), findsNothing);
    expect(_notice('h3'), findsOneWidget);
  });

  testWidgets('an undo closes itself after its minimum time', (tester) async {
    await tester.pumpWidget(_host());
    var gone = 0;
    await _show(tester, _undo('a', onAction: () {}, onGone: () => gone++));

    await tester.pump(kWpNoticeUndoMinimum - const Duration(seconds: 1));
    expect(_notice('a'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(_notice('a'), findsNothing);
    expect(gone, 1);
  });

  testWidgets('the pointer holds an undo; it closes after it leaves', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await _show(tester, _undo('a', onAction: () {}));

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(_notice('a')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(_notice('a'), findsOneWidget);

    await pointer.moveTo(const Offset(1, 1));
    await tester.pump();
    await tester.pump(kWpNoticeUndoAfterHold + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(_notice('a'), findsNothing);
  });

  testWidgets('a hint with a duration closes itself, a warning stays', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await _show(
      tester,
      const WpNotice(
        id: 'h',
        message: 'Migration done',
        duration: Duration(seconds: 2),
      ),
    );
    await _show(
      tester,
      const WpNotice(
        id: 'w',
        message: 'Hotkey lost',
        kind: WpNoticeKind.warning,
      ),
    );

    await tester.pump(const Duration(minutes: 5));
    await tester.pumpAndSettle();
    expect(_notice('h'), findsNothing);
    expect(_notice('w'), findsOneWidget);
  });

  testWidgets('the message carries the next step', (tester) async {
    await tester.pumpWidget(_host());
    await _show(
      tester,
      const WpNotice(
        id: 'e',
        message: 'The link could not be opened.',
        nextStep: 'Copy it and open it in your browser.',
        kind: WpNoticeKind.error,
      ),
    );

    expect(
      find.descendant(
        of: _notice('e'),
        matching: find.textContaining('Copy it and open it'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the notice is read out to screen readers', (tester) async {
    final spoken = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      SystemChannels.accessibility.name,
      (message) async {
        final decoded =
            const StandardMessageCodec().decodeMessage(message)
                as Map<Object?, Object?>?;
        final data = decoded?['data'] as Map<Object?, Object?>?;
        final text = data?['message'];
        if (text is String) spoken.add(text);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        SystemChannels.accessibility.name,
        null,
      ),
    );
    await tester.pumpWidget(_host());
    await _show(tester, _undo('a', onAction: () {}));

    expect(spoken.single, contains('Moved to trash'));
    expect(spoken.single, contains('Undo'));
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('Ctrl+Z runs the open undo', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_host());
    var runs = 0;
    await _show(tester, _undo('a', onAction: () => runs++));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(runs, 1);
    expect(_notice('a'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Ctrl+Z in a text field stays with the text', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      _host(field: const TextField(key: ValueKey('field'))),
    );
    var runs = 0;
    await _show(tester, _undo('a', onAction: () => runs++));
    await tester.tap(find.byKey(const ValueKey('field')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(runs, 0);
    expect(_notice('a'), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the menu shortcut runs the open undo', (tester) async {
    await tester.pumpWidget(_host());
    var runs = 0;
    expect(WpNoticeBar.undoByShortcut(), isFalse);
    await _show(tester, _undo('a', onAction: () => runs++));

    expect(WpNoticeBar.undoByShortcut(), isTrue);
    await tester.pumpAndSettle();
    expect(runs, 1);
  });

  test('Cmd is the undo key on macOS only', () {
    expect(wpNoticeUndoUsesMeta(TargetPlatform.macOS), isTrue);
    expect(wpNoticeUndoUsesMeta(TargetPlatform.windows), isFalse);
    expect(wpNoticeUndoUsesMeta(TargetPlatform.linux), isFalse);
  });
}
