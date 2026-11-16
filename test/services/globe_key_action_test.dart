// #778: the macOS "Press 🌐 key to" setting decides whether Fn as hotkey
// conflicts. Read only; the app never changes the setting.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/globe_key_action.dart';
import 'package:whispaste/services/hotkey_conflicts.dart';
import 'package:whispaste/services/modifier_key_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('globeKeyActionFromRaw', () {
    test('maps AppleFnUsageType values', () {
      expect(globeKeyActionFromRaw(0), GlobeKeyAction.none);
      expect(globeKeyActionFromRaw(1), GlobeKeyAction.inputSource);
      expect(globeKeyActionFromRaw(2), GlobeKeyAction.emoji);
      expect(globeKeyActionFromRaw(3), GlobeKeyAction.dictation);
    });

    test('absent key is the system default, odd values unknown', () {
      expect(globeKeyActionFromRaw(null), GlobeKeyAction.systemDefault);
      expect(globeKeyActionFromRaw(7), GlobeKeyAction.unknown);
      expect(globeKeyActionFromRaw('2'), GlobeKeyAction.unknown);
    });

    test('only "Do Nothing" is free of conflict', () {
      for (final action in GlobeKeyAction.values) {
        expect(globeKeyConflicts(action), action != GlobeKeyAction.none);
      }
    });
  });

  group('globeKeyConflict', () {
    const fn = ConflictEntry(
      modifiers: '',
      key: 'Fn',
      note: ConflictNote.fnDoubleTap,
      action: ConflictAction.disableInSystem,
      doubleTapKey: 'fn',
    );

    test('"Do Nothing" shows no warning', () {
      expect(globeKeyConflict(fn, GlobeKeyAction.none), isNull);
    });

    test('a known action names itself and keeps the way out', () {
      final cases = {
        GlobeKeyAction.emoji: ConflictNote.globeEmoji,
        GlobeKeyAction.inputSource: ConflictNote.globeInputSource,
        GlobeKeyAction.dictation: ConflictNote.globeDictation,
      };
      cases.forEach((action, note) {
        final entry = globeKeyConflict(fn, action)!;
        expect(entry.note, note);
        expect(entry.action, ConflictAction.disableInSystem);
        expect(entry.doubleTapKey, 'fn');
      });
    });

    test('default or unreadable keeps the generic Fn warning', () {
      for (final action in [
        GlobeKeyAction.systemDefault,
        GlobeKeyAction.unknown,
      ]) {
        expect(globeKeyConflict(fn, action)!.note, ConflictNote.fnDoubleTap);
      }
    });
  });

  group('ModifierKeyMonitor.globeKeyAction', () {
    const channel = MethodChannel('com.whispaste.modifier_monitor');
    late List<String> calls;

    void answer(Future<Object?> Function() reply) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return reply();
          });
    }

    setUp(() => calls = []);
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('reads the value over the channel, never writes', () async {
      answer(() async => 2);
      final action = await ModifierKeyMonitor(isMacOS: true).globeKeyAction();
      expect(action, GlobeKeyAction.emoji);
      expect(calls, ['globeKeyAction']);
    });

    test('host error falls back to unknown (generic warning)', () async {
      answer(() async => throw PlatformException(code: 'FAIL'));
      expect(
        await ModifierKeyMonitor(isMacOS: true).globeKeyAction(),
        GlobeKeyAction.unknown,
      );
    });

    test('off macOS there is no conflict and no call', () async {
      answer(() async => 2);
      expect(
        await ModifierKeyMonitor(isMacOS: false).globeKeyAction(),
        GlobeKeyAction.none,
      );
      expect(calls, isEmpty);
    });
  });
}
