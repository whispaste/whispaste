import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/history/widgets/smart_mode_undo_actions.dart';
import 'package:whispaste/services/paste/paster.dart';
import 'package:whispaste/services/selection_edit/selection_undo.dart';
import 'package:whispaste/services/smart_mode/smart_mode_name_change_notice.dart';

/// Paster with the undo bridge. The frontmost app and the hardware-key answer
/// are settable (DEV-165, DEV-185).
class _UndoPaster implements Paster, UndoKeystrokeSender {
  _UndoPaster({this.hardwareKeyDown = false});

  final bool hardwareKeyDown;
  int keystrokes = 0;
  final copied = <String>[];

  @override
  int? get cleanPasteSerial => 1;

  @override
  Future<InputIdleSnapshot?> inputIdleSnapshot() async => InputIdleSnapshot(
    keyIdle: hardwareKeyDown ? 0 : 1e9,
    mouseIdle: 1e9,
    syntheticIdle: 1e9,
  );

  @override
  Future<bool> sendUndoShortcut() async {
    keystrokes++;
    return true;
  }

  @override
  Future<bool> copyOriginalToClipboard(String text) async {
    copied.add(text);
    return true;
  }

  @override
  Future<String?> getTargetBundleId() async => 'com.example.editor';

  @override
  Future<void> prime() async {}

  @override
  Future<PasteOutcome> paste(String text, PasteOptions options) async =>
      PasteOutcome.success;

  @override
  Future<PasteOutcome> typeText(String text, PasteOptions options) async =>
      PasteOutcome.failed;

  @override
  Future<PasteCapability> checkCapability({
    bool promptIfMissing = false,
  }) async => const PasteCapability(status: PasteCapabilityStatus.ready);
}

SelectionUndoTicket _ticket() => SelectionUndoTicket(
  originalText: 'Ich habe Müller gesehen.',
  targetBundleId: 'com.example.editor',
  insertSerial: 1,
  sinceInsert: Stopwatch()..start(),
);

/// A page with a button that raises the name toast for [count] names.
Widget _page({
  required ProviderContainer container,
  required int count,
  int serial = 1,
  SelectionUndoTicket? ticket,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showSmartModeNameChangeToast(
                context: context,
                ref: ref,
                notice: SmartModeNameChangeNotice(
                  count: count,
                  ticket: ticket ?? _ticket(),
                  serial: serial,
                ),
              ),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  var left = duration;
  while (left > Duration.zero) {
    const step = Duration(milliseconds: 500);
    final next = left < step ? left : step;
    await tester.pump(next);
    left -= next;
  }
}

Finder get _message =>
    find.byKey(const ValueKey<String>('toast-smart-name-changes'));

void main() {
  test('the notice counts up and clears (DEV-165)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(smartModeNameChangeNoticeProvider.notifier);

    notifier.announce(count: 1, ticket: _ticket());
    final first = container.read(smartModeNameChangeNoticeProvider);
    expect(first?.count, 1);
    notifier.announce(count: 1, ticket: _ticket());
    expect(
      container.read(smartModeNameChangeNoticeProvider)?.serial,
      isNot(first?.serial),
    );
    notifier.clear();
    expect(container.read(smartModeNameChangeNoticeProvider), isNull);
  });

  test('clearIfSerial leaves a newer notice alone (GS-048)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(smartModeNameChangeNoticeProvider.notifier)
      ..announce(count: 1, ticket: _ticket());
    final old = container.read(smartModeNameChangeNoticeProvider)!.serial;
    notifier.announce(count: 2, ticket: _ticket());

    notifier.clearIfSerial(old);
    expect(container.read(smartModeNameChangeNoticeProvider)?.count, 2);
  });

  for (final (count, expected) in [
    (1, '1 name changed'),
    (3, '3 names changed'),
  ]) {
    testWidgets('the toast says the count, not the names ($count)', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _page(container: container, count: count, ticket: _ticket()),
      );
      await tester.tap(find.text('show'));
      await _pumpFor(tester, const Duration(seconds: 1));

      expect(tester.widget<Text>(_message).data, expected);
      expect(find.text('Müller'), findsNothing);
      await tester.pumpAndSettle(const Duration(seconds: 30));
    });
  }

  testWidgets('the undo sends the keystroke when every condition holds', (
    tester,
  ) async {
    final paster = _UndoPaster();
    final container = ProviderContainer(
      overrides: [pasterProvider.overrideWithValue(paster)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(_page(container: container, count: 1));
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(
      find.byKey(const ValueKey<String>('toast-smart-name-undo')),
    );
    await tester.pump();

    expect(paster.keystrokes, 1);
    expect(paster.copied, isEmpty);
    await tester.pumpAndSettle(const Duration(seconds: 30));
  });

  testWidgets(
    'a hardware key since the insert copies the original and says so',
    (tester) async {
      final paster = _UndoPaster(hardwareKeyDown: true);
      final container = ProviderContainer(
        overrides: [pasterProvider.overrideWithValue(paster)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_page(container: container, count: 1));
      await tester.tap(find.text('show'));
      await _pumpFor(tester, const Duration(seconds: 1));

      await tester.tap(
        find.byKey(const ValueKey<String>('toast-smart-name-undo')),
      );
      await tester.pump();

      expect(paster.keystrokes, 0);
      expect(paster.copied.single, 'Ich habe Müller gesehen.');
      // The fallback names the platform key and says the clipboard was replaced.
      expect(
        find.text(
          'Original copied to the clipboard – paste it with Ctrl+V. '
          'The previous clipboard content was replaced.',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 30));
    },
  );

  testWidgets('the pointer holds an actionable toast past its timer', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_page(container: container, count: 1));
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 1));

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(tester.getCenter(_message));
    await tester.pump();

    await _pumpFor(tester, const Duration(seconds: 30));
    expect(_message, findsOneWidget);

    await pointer.moveTo(const Offset(1, 1));
    await _pumpFor(tester, const Duration(seconds: 4));
    expect(_message, findsOneWidget);
    await _pumpFor(tester, const Duration(seconds: 8));
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(_message, findsNothing);
  });

  testWidgets('keyboard focus holds an actionable toast past its timer', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(_page(container: container, count: 1));
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 1));

    // Tab to the undo action (its focus node is labelled WpButton).
    for (var i = 0; i < 6; i++) {
      if (FocusManager.instance.primaryFocus?.debugLabel == 'WpButton') break;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'WpButton');

    await _pumpFor(tester, const Duration(seconds: 30));
    expect(_message, findsOneWidget);

    FocusManager.instance.primaryFocus?.unfocus();
    await _pumpFor(tester, const Duration(seconds: 12));
    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(_message, findsNothing);
  });

  testWidgets('expiry drops the offer and its original text (GS-048)', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(smartModeNameChangeNoticeProvider.notifier)
        .announce(count: 1, ticket: _ticket());
    final serial = container.read(smartModeNameChangeNoticeProvider)!.serial;
    await tester.pumpWidget(
      _page(container: container, count: 1, serial: serial),
    );
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 1));

    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(container.read(smartModeNameChangeNoticeProvider), isNull);
  });

  testWidgets('an older toast expiring keeps a newer offer', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(smartModeNameChangeNoticeProvider.notifier)
      ..announce(count: 1, ticket: _ticket());
    final oldSerial = container.read(smartModeNameChangeNoticeProvider)!.serial;
    await tester.pumpWidget(
      _page(container: container, count: 1, serial: oldSerial),
    );
    await tester.tap(find.text('show'));
    await _pumpFor(tester, const Duration(seconds: 1));
    notifier.announce(count: 2, ticket: _ticket());

    await tester.pumpAndSettle(const Duration(seconds: 30));
    expect(container.read(smartModeNameChangeNoticeProvider)?.count, 2);
  });

  // UIA-HIS-26: without a paste target, Undo says so instead of doing nothing.
  testWidgets(
    'undo without a paste target says it is not possible (UIA-HIS-26)',
    (tester) async {
      final container = ProviderContainer(
        overrides: [pasterProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(_page(container: container, count: 1));
      await tester.tap(find.text('show'));
      await _pumpFor(tester, const Duration(seconds: 1));

      await tester.tap(
        find.byKey(const ValueKey<String>('toast-smart-name-undo')),
      );
      await tester.pump();

      expect(find.text('Undo is not possible right now.'), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 30));
    },
  );
}
