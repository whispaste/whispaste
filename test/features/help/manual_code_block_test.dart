/// A handbook command is a [ManualCode] block: selectable monospace text in
/// a left-to-right run, with a copy button that has a test id, a semantics
/// label and a 48 px tap area.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/features/help/manual/manual_model.dart';
import 'package:whispaste/features/help/manual/user_manual_view.dart';

import '../../fixtures/test_helpers.dart';

const _command =
    'sudo udevadm control --reload-rules && '
    'sudo udevadm trigger --subsystem-match=misc --sysname-match=uinput';

final _chapter = ManualChapter(
  slug: 'probe',
  title: (l) => 'Probe chapter',
  sections: [
    ManualSection(
      heading: (l) => 'Probe heading',
      blocks: [ManualCode('probe-cmd', (l) => _command)],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, {required String locale}) {
  return tester.pumpWidget(
    makeTestable(
      Scaffold(
        body: UserManualView(chapters: [_chapter], initialSlug: 'probe'),
      ),
      size: const Size(1280, 800),
      locale: Locale(locale),
    ),
  );
}

void main() {
  String? copied;

  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('the copy button copies the command and confirms it', (
    tester,
  ) async {
    await _pump(tester, locale: 'de');
    final l10n = await L10n.delegate.load(const Locale('de'));

    final copy = find.byKey(const ValueKey('manual-code-probe-cmd-copy'));
    expect(copy, findsOneWidget);
    expect(find.bySemanticsLabel(l10n.manualCodeCopy), findsOneWidget);
    expect(tester.getSize(copy).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(copy).height, greaterThanOrEqualTo(48));

    await tester.tap(copy);
    await tester.pump();

    expect(copied, _command);
    expect(find.text(l10n.manualCodeCopied), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  // UIA-HLP-02: the copy control is reachable and operable from the keyboard.
  testWidgets(
    'the copy button takes keyboard focus and copies on Enter (UIA-HLP-02)',
    (tester) async {
      await _pump(tester, locale: 'de');
      final l10n = await L10n.delegate.load(const Locale('de'));

      const copyKey = ValueKey('manual-code-probe-cmd-copy');
      // Tab through the page until the copy control holds the focus.
      var focused = false;
      for (var i = 0; i < 30 && !focused; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final ctx = FocusManager.instance.primaryFocus?.context;
        focused = ctx?.findAncestorWidgetOfExactType<InkWell>()?.key == copyKey;
      }
      expect(focused, isTrue, reason: 'Tab must reach the copy control.');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(copied, _command);
      expect(find.text(l10n.manualCodeCopied), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('a failed copy says so instead of confirming it', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'clipboard-unavailable');
          }
          return null;
        });
    await _pump(tester, locale: 'de');
    final l10n = await L10n.delegate.load(const Locale('de'));

    await tester.tap(find.byKey(const ValueKey('manual-code-probe-cmd-copy')));
    await tester.pump();

    expect(find.text(l10n.manualCodeCopied), findsNothing);
    expect(find.text(l10n.manualCodeCopyFailed), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
