import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/data/database.dart';
import 'package:whispaste/features/notes/data/writing_focus.dart';
import 'package:whispaste/features/notes/widgets/note_markup_controller.dart';

class _FakeWindow implements WindowFullScreen {
  _FakeWindow({this.fullScreen = false});

  bool fullScreen;
  final calls = <bool>[];

  @override
  Future<bool> isFullScreen() async => fullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    calls.add(value);
    fullScreen = value;
  }
}

void main() {
  group('focusParagraphRange', () {
    const text = 'One line\n\nSecond paragraph\n\nThird';

    test('lights the paragraph holding the caret', () {
      final range = focusParagraphRange(text, text.indexOf('paragraph'));
      expect(range.textInside(text).trim(), 'Second paragraph');
      expect(range.start, text.indexOf('Second'));
    });

    test('first and last paragraph reach the text edges', () {
      expect(focusParagraphRange(text, 0).start, 0);
      expect(focusParagraphRange(text, text.length).end, text.length);
      expect(focusParagraphRange(text, text.length).textInside(text), 'Third');
    });

    test('empty text gives an empty range', () {
      expect(focusParagraphRange('', 0), const TextRange(start: 0, end: 0));
    });
  });

  group('dimOutsideRange', () {
    const dim = TextStyle(color: Color(0x80000000));
    const bold = TextStyle(fontWeight: FontWeight.bold);

    List<(String, TextStyle?)> parts(TextSpan span) => [
      for (final c in span.children!.cast<TextSpan>()) (c.text!, c.style),
    ];

    test('dims everything outside the lit range, across child spans', () {
      const span = TextSpan(
        children: [
          TextSpan(text: 'abc'),
          TextSpan(text: 'def', style: bold),
        ],
      );
      final out = dimOutsideRange(span, const TextRange(start: 2, end: 4), dim);
      expect(out.toPlainText(), 'abcdef');
      expect(parts(out), [
        ('ab', dim),
        ('c', null),
        ('d', bold),
        ('ef', bold.merge(dim)),
      ]);
    });

    test('a root text span is split as well', () {
      final out = dimOutsideRange(
        const TextSpan(text: 'hello'),
        const TextRange(start: 0, end: 2),
        dim,
      );
      expect(parts(out), [('he', null), ('llo', dim)]);
    });

    test('nested spans are left unchanged', () {
      const span = TextSpan(
        children: [
          TextSpan(children: [TextSpan(text: 'x')]),
        ],
      );
      expect(
        identical(
          dimOutsideRange(span, const TextRange(start: 0, end: 1), dim),
          span,
        ),
        isTrue,
      );
    });
  });

  group('WritingFocusNotifier', () {
    ProviderContainer containerWith(_FakeWindow window) {
      final container = ProviderContainer(
        overrides: [windowFullScreenProvider.overrideWithValue(window)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('entering sets full screen, leaving restores it', () async {
      final window = _FakeWindow();
      final container = containerWith(window);
      final notifier = container.read(writingFocusProvider.notifier);

      await notifier.toggle();
      expect(container.read(writingFocusProvider), isTrue);
      expect(window.fullScreen, isTrue);

      await notifier.toggle();
      expect(container.read(writingFocusProvider), isFalse);
      expect(window.calls, [true, false]);
    });

    test('a window already full screen stays so after leaving', () async {
      final window = _FakeWindow(fullScreen: true);
      final container = containerWith(window);
      final notifier = container.read(writingFocusProvider.notifier);

      await notifier.enter();
      await notifier.exit();
      expect(window.calls, isEmpty);
      expect(window.fullScreen, isTrue);
    });

    test('exit without focus mode touches nothing', () async {
      final window = _FakeWindow();
      final container = containerWith(window);
      await container.read(writingFocusProvider.notifier).exit();
      expect(window.calls, isEmpty);
    });
  });

  group('paragraph focus', () {
    test('off by default, remembered, dims only inside focus mode', () async {
      final db = HistoryDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ProviderContainer open() {
        final c = ProviderContainer(
          overrides: [
            historyDatabaseProvider.overrideWithValue(db),
            windowFullScreenProvider.overrideWithValue(_FakeWindow()),
          ],
        );
        addTearDown(c.dispose);
        return c;
      }

      final first = open();
      expect(await first.read(paragraphFocusProvider.future), isFalse);
      await first.read(paragraphFocusProvider.notifier).toggle();
      expect(first.read(paragraphDimProvider), isFalse);
      await first.read(writingFocusProvider.notifier).enter();
      expect(first.read(paragraphDimProvider), isTrue);

      final second = open();
      expect(await second.read(paragraphFocusProvider.future), isTrue);
    });
  });

  test('shortcut is Cmd+Shift+Enter on macOS, Ctrl+Shift+Enter elsewhere', () {
    final mac = writingFocusActivator(isMacOS: true);
    final other = writingFocusActivator(isMacOS: false);
    expect(mac.trigger, LogicalKeyboardKey.enter);
    expect((mac.meta, mac.control, mac.shift), (true, false, true));
    expect((other.meta, other.control, other.shift), (false, true, true));
  });

  test('paragraph focus setter repaints only on a change', () {
    final controller = NoteMarkupController()..text = 'One\n\nTwo';
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 6);
    var notified = 0;
    controller.addListener(() => notified++);
    controller
      ..paragraphFocus = true
      ..paragraphFocus = true;
    expect(notified, 1);
  });
}
