import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/desktop_paste/desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/macos_desktop_paste_controller.dart';
import 'package:whispaste/services/desktop_paste/windows_desktop_paste_controller.dart';
import 'package:whispaste/services/selection_edit/selection_edit_service.dart';

/// Records the history-excluded write and answers with [excludedResult].
class _Controller implements DesktopPasteController {
  _Controller(this.excludedResult);

  final bool excludedResult;
  final List<String> excludedCalls = [];

  @override
  Future<bool> writeClipboardTextExcludingHistory(String text) async {
    excludedCalls.add(text);
    return excludedResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final plainWrites = <String>[];

  setUp(() {
    plainWrites.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            plainWrites.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('writeTransient takes the history-excluded path first', () async {
    final controller = _Controller(true);
    await SystemSelectionClipboard(controller).writeTransient('selected');

    expect(controller.excludedCalls, ['selected']);
    expect(plainWrites, isEmpty);
  });

  test(
    'writeTransient falls back to a plain write when exclusion fails',
    () async {
      final controller = _Controller(false);
      await SystemSelectionClipboard(controller).writeTransient('selected');

      expect(controller.excludedCalls, ['selected']);
      expect(plainWrites, ['selected']);
    },
  );

  group('native channel answer decides the plain write', () {
    const channel = MethodChannel('com.whispaste.desktop_paste');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void answerWith(bool excluded, List<MethodCall> calls) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return call.method == 'writeClipboardText' ? excluded : null;
          });
    }

    for (final (name, make) in <(String, DesktopPasteController Function())>[
      ('macOS', MacOSDesktopPasteController.new),
      ('Windows', WindowsDesktopPasteController.new),
    ]) {
      test(
        '$name native false: exactly one plain write (no duplicate)',
        () async {
          final calls = <MethodCall>[];
          answerWith(false, calls);

          await SystemSelectionClipboard(make()).writeTransient('secret');

          expect(
            calls.where((c) => c.method == 'writeClipboardText'),
            hasLength(1),
          );
          expect(plainWrites, ['secret']);
        },
      );

      test('$name native true: history-excluded, no plain write', () async {
        final calls = <MethodCall>[];
        answerWith(true, calls);

        await SystemSelectionClipboard(make()).writeTransient('secret');

        expect(
          calls.where((c) => c.method == 'writeClipboardText'),
          hasLength(1),
        );
        expect(plainWrites, isEmpty);
      });
    }
  });
}
