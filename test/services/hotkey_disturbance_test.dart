import 'dart:async';

// Issue #775: which hotkey disturbance gets named, and how often.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:whispaste/core/l10n/generated/app_localizations.dart';
import 'package:whispaste/services/hotkey_disturbance.dart';
import 'package:whispaste/services/tap_disabled_evidence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InputDisturbance.fromMap', () {
    test('reads secure input with its holder and the keyboard taps', () {
      final reading = InputDisturbance.fromMap({
        'secureInput': true,
        'holder': {'pid': 42, 'name': 'Terminal', 'bundleId': ''},
        'keyboardTaps': [
          {'pid': 7, 'name': 'Tool', 'avgLatencyUs': 3600000.0},
          {'pid': 8, 'avgLatencyUs': -1},
          'junk',
        ],
      });
      expect(reading.secureInput, isTrue);
      expect(reading.holder?.name, 'Terminal');
      expect(reading.holder?.bundleId, isNull);
      expect(reading.holder?.pid, 42);
      expect(reading.keyboardTaps, hasLength(1));
      expect(reading.keyboardTaps.single.avgLatency.inMilliseconds, 3600);
    });

    test('a missing answer reads as nothing known', () {
      final reading = InputDisturbance.fromMap(null);
      expect(reading.secureInput, isFalse);
      expect(hotkeyDisturbanceNotice(reading), isNull);
    });
  });

  group('hotkeyDisturbanceNotice', () {
    test('secure input names the holder', () {
      final notice = hotkeyDisturbanceNotice(
        InputDisturbance.fromMap({
          'secureInput': true,
          'holder': {'pid': 42, 'name': 'Terminal'},
        }),
      );
      expect(notice?.cause, HotkeyDisturbanceCause.secureInput);
      expect(notice?.appName, 'Terminal');
    });

    test('secure input keeps the holder bundle id for the wording', () {
      final notice = hotkeyDisturbanceNotice(
        InputDisturbance.fromMap({
          'secureInput': true,
          'holder': {
            'pid': 9,
            'name': 'SecurityAgent',
            'bundleId': 'com.apple.SecurityAgent',
          },
        }),
      );
      expect(notice?.bundleId, 'com.apple.SecurityAgent');
    });

    test('secure input without a holder (sandbox) still gives a notice', () {
      final notice = hotkeyDisturbanceNotice(
        const InputDisturbance(secureInput: true),
      );
      expect(notice?.cause, HotkeyDisturbanceCause.secureInput);
      expect(notice?.appName, isNull);
    });

    test('secure input wins over a slow tap', () {
      final notice = hotkeyDisturbanceNotice(
        const InputDisturbance(
          secureInput: true,
          keyboardTaps: [
            KeyboardTapInfo(avgLatency: Duration(seconds: 3), name: 'Tool'),
          ],
        ),
      );
      expect(notice?.cause, HotkeyDisturbanceCause.secureInput);
    });

    test('names the slowest tap at or above the threshold', () {
      final notice = hotkeyDisturbanceNotice(
        const InputDisturbance(
          keyboardTaps: [
            KeyboardTapInfo(avgLatency: Duration(milliseconds: 5), name: 'A'),
            KeyboardTapInfo(avgLatency: kSlowKeyboardTapLatency, name: 'B'),
            KeyboardTapInfo(
              avgLatency: Duration(seconds: 2),
              bundleId: 'com.example.c',
            ),
          ],
        ),
      );
      expect(notice?.cause, HotkeyDisturbanceCause.slowKeyboardTap);
      expect(notice?.appName, 'com.example.c');
    });

    test('fast taps are no cause', () {
      final notice = hotkeyDisturbanceNotice(
        const InputDisturbance(
          keyboardTaps: [
            KeyboardTapInfo(avgLatency: Duration(milliseconds: 99), name: 'A'),
          ],
        ),
      );
      expect(notice, isNull);
    });
  });

  group('HotkeyDisturbanceGate', () {
    test(
      'the same notice passes once per repeat window, a new app at once',
      () {
        var now = DateTime(2026, 11, 6, 12);
        final gate = HotkeyDisturbanceGate(clock: () => now);
        const terminal = HotkeyDisturbanceNotice(
          HotkeyDisturbanceCause.secureInput,
          appName: 'Terminal',
          pid: 1,
        );
        const other = HotkeyDisturbanceNotice(
          HotkeyDisturbanceCause.secureInput,
          appName: 'Other',
          pid: 2,
        );
        expect(gate.allow(terminal), isTrue);
        expect(gate.allow(terminal), isFalse);
        expect(gate.allow(other), isTrue);
        now = now.add(kHotkeyDisturbanceRepeat);
        expect(gate.allow(terminal), isTrue);
      },
    );
  });

  group('slow tap gate (#915)', () {
    HotkeyDisturbanceNotice tap(int ms, {String app = 'Magnet'}) =>
        HotkeyDisturbanceNotice(
          HotkeyDisturbanceCause.slowKeyboardTap,
          appName: app,
          pid: ms, // the pid changes between readings and must not matter
          latency: Duration(milliseconds: ms),
        );

    test('announces once per app, not again after 30 minutes', () {
      var now = DateTime(2026, 11, 8, 16);
      final gate = HotkeyDisturbanceGate(
        clock: () => now,
        evidence: TapDisabledEvidence(),
      );
      expect(gate.allow(tap(120)), isTrue);
      now = now.add(const Duration(hours: 5));
      expect(gate.allow(tap(130)), isFalse);
      expect(gate.allow(tap(120, app: 'Other')), isTrue);
    });

    test('announces again at twice the latency, not below', () {
      final gate = HotkeyDisturbanceGate(evidence: TapDisabledEvidence());
      expect(gate.allow(tap(150)), isTrue);
      expect(gate.allow(tap(299)), isFalse);
      expect(gate.allow(tap(300)), isTrue);
      expect(gate.allow(tap(450)), isFalse);
    });

    test('announces again after a tapDisabled event, once', () {
      var now = DateTime(2026, 11, 8, 16);
      final evidence = TapDisabledEvidence();
      final gate = HotkeyDisturbanceGate(clock: () => now, evidence: evidence);
      expect(gate.allow(tap(120)), isTrue);
      now = now.add(const Duration(minutes: 1));
      evidence.record(now);
      now = now.add(const Duration(minutes: 1));
      expect(gate.allow(tap(120)), isTrue);
      expect(gate.allow(tap(120)), isFalse);
    });

    test('records survive a restart (persistence round trip)', () async {
      SharedPreferences.setMockInitialValues({});
      Future<HotkeyDisturbanceGate> open() async {
        final prefs = await SharedPreferences.getInstance();
        final gate = HotkeyDisturbanceGate(
          evidence: TapDisabledEvidence(),
          loadRecords: () async => prefs.getString(kSlowTapRecordsPrefKey),
          saveRecords: (json) => prefs.setString(kSlowTapRecordsPrefKey, json),
        );
        await gate.load();
        return gate;
      }

      expect((await open()).allow(tap(120)), isTrue);
      final restarted = await open();
      expect(restarted.allow(tap(130)), isFalse);
      expect(restarted.allow(tap(240)), isTrue);
    });

    test('an acknowledged app stays silent, even after tapDisabled and at '
        'twice the latency; another app is still named (#1607)', () async {
      var now = DateTime(2026, 11, 16, 9);
      final evidence = TapDisabledEvidence();
      final gate = HotkeyDisturbanceGate(clock: () => now, evidence: evidence);
      expect(gate.allow(tap(150, app: 'Siri')), isTrue);
      await gate.acknowledge(tap(150, app: 'Siri'));
      now = now.add(const Duration(minutes: 1));
      evidence.record(now);
      now = now.add(const Duration(minutes: 1));
      expect(gate.allow(tap(150, app: 'Siri')), isFalse);
      expect(gate.allow(tap(900, app: 'Siri')), isFalse);
      expect(gate.allow(tap(150, app: 'Magnet')), isTrue);
    });

    test('the acknowledgement survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      Future<HotkeyDisturbanceGate> open() async {
        final prefs = await SharedPreferences.getInstance();
        final gate = HotkeyDisturbanceGate(
          evidence: TapDisabledEvidence(),
          loadRecords: () async => prefs.getString(kSlowTapRecordsPrefKey),
          saveRecords: (json) => prefs.setString(kSlowTapRecordsPrefKey, json),
        );
        await gate.load();
        return gate;
      }

      final first = await open();
      expect(first.allow(tap(120, app: 'Siri')), isTrue);
      await first.acknowledge(tap(120, app: 'Siri'));
      final restarted = await open();
      expect(restarted.allow(tap(480, app: 'Siri')), isFalse);
    });

    test('records without the acknowledgement field read as open', () {
      final records = decodeSlowTapRecords('{"A":{"ms":120,"at":1}}');
      expect(records['A']!.acknowledged, isFalse);
      final roundTrip = decodeSlowTapRecords(
        encodeSlowTapRecords({
          'A': const SlowTapRecord(
            latencyMs: 120,
            announcedAtMs: 1,
            acknowledged: true,
          ),
        }),
      );
      expect(roundTrip['A']!.acknowledged, isTrue);
    });

    test('secure input is never acknowledged for good', () async {
      var now = DateTime(2026, 11, 16, 9);
      final gate = HotkeyDisturbanceGate(
        clock: () => now,
        evidence: TapDisabledEvidence(),
      );
      const secure = HotkeyDisturbanceNotice(
        HotkeyDisturbanceCause.secureInput,
        appName: 'Terminal',
      );
      expect(gate.allow(secure), isTrue);
      await gate.acknowledge(secure);
      now = now.add(kHotkeyDisturbanceRepeat);
      expect(gate.allow(secure), isTrue);
    });

    test('a damaged stored value reads as no record', () {
      expect(decodeSlowTapRecords('not json'), isEmpty);
      expect(decodeSlowTapRecords('{"A":{"ms":"x"}}'), isEmpty);
    });

    test('the log line carries app, latency and the decision', () {
      final line = slowTapLogLine(tap(340), announced: false);
      expect(line, contains('Magnet'));
      expect(line, contains('340 ms'));
      expect(line, contains('not announced'));
    });

    test('the watcher logs every reading but notifies once', () async {
      final shown = <HotkeyDisturbanceNotice>[];
      final watcher = HotkeyDisturbanceWatcher(
        read: () async => const InputDisturbance(
          keyboardTaps: [
            KeyboardTapInfo(
              avgLatency: Duration(milliseconds: 200),
              name: 'Magnet',
            ),
          ],
        ),
        notify: shown.add,
        gate: HotkeyDisturbanceGate(evidence: TapDisabledEvidence()),
      );
      await watcher.onHotkeyPressed();
      await watcher.onHotkeyPressed();
      expect(shown, hasLength(1));
      expect(shown.single.latency?.inMilliseconds, 200);
    });
  });

  group('HotkeyDisturbanceWatcher', () {
    test('notifies once for a repeated cause', () async {
      final shown = <HotkeyDisturbanceNotice>[];
      final watcher = HotkeyDisturbanceWatcher(
        read: () async => const InputDisturbance(secureInput: true),
        notify: shown.add,
      );
      await watcher.onHotkeyPressed();
      await watcher.onHotkeyPressed();
      expect(shown, hasLength(1));
    });

    test('nothing disturbing, no notice', () async {
      final shown = <HotkeyDisturbanceNotice>[];
      final watcher = HotkeyDisturbanceWatcher(
        read: () async => InputDisturbance.none,
        notify: shown.add,
      );
      await watcher.onHotkeyPressed();
      expect(shown, isEmpty);
    });
  });

  group('hotkeyDisturbanceNoticeProvider (#831)', () {
    test('publishes the notice the app shell turns into a toast', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(hotkeyDisturbanceNoticeProvider), isNull);
      const notice = HotkeyDisturbanceNotice(
        HotkeyDisturbanceCause.secureInput,
        appName: 'Terminal',
      );
      container.read(hotkeyDisturbanceNoticeProvider.notifier).publish(notice);
      expect(container.read(hotkeyDisturbanceNoticeProvider), same(notice));
    });
  });

  group('readInputDisturbance', () {
    const channel = MethodChannel('test.hotkey_disturbance');

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('a host without the method (Windows, Linux) reads as none', () async {
      final reading = await readInputDisturbance(channel: channel);
      expect(hotkeyDisturbanceNotice(reading), isNull);
    });

    test('a host error reads as none', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(code: 'X');
          });
      final reading = await readInputDisturbance(channel: channel);
      expect(hotkeyDisturbanceNotice(reading), isNull);
    });

    test('asks the inputDisturbance method', () async {
      String? asked;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            asked = call.method;
            return {'secureInput': true};
          });
      final reading = await readInputDisturbance(channel: channel);
      expect(asked, 'inputDisturbance');
      expect(reading.secureInput, isTrue);
    });

    testWidgets('a cancelled read leaves no deadline timer pending (#1008)', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) => Completer<Object?>().future,
          );
      final cancel = Completer<void>();
      final read = readInputDisturbance(
        channel: channel,
        cancelled: cancel.future,
      );
      cancel.complete();
      final reading = await tester.runAsync(() => read);
      expect(hotkeyDisturbanceNotice(reading!), isNull);
      // testWidgets fails the test when a timer is still pending here.
    });
  });

  group('hotkeyDisturbanceText for secure input (#1617)', () {
    late L10n de;
    setUpAll(() async {
      de = await L10n.delegate.load(const Locale('de'));
    });

    String body(HotkeyDisturbanceNotice n) => hotkeyDisturbanceText(de, n).body;

    test('a macOS password prompt is answered or closed, never quit', () {
      final text = body(
        const HotkeyDisturbanceNotice(
          HotkeyDisturbanceCause.secureInput,
          appName: 'SecurityAgent',
          bundleId: 'com.apple.SecurityAgent',
        ),
      );
      expect(text, startsWith(de.pasteSecureInputSystem));
      expect(text, endsWith(de.hotkeyDisturbanceSecureInputEffect));
      expect(text, isNot(contains('SecurityAgent')));
    });

    test('Terminal names its menu switch, another app is named', () {
      expect(
        body(
          const HotkeyDisturbanceNotice(
            HotkeyDisturbanceCause.secureInput,
            appName: 'Terminal',
            bundleId: 'com.apple.Terminal',
          ),
        ),
        startsWith(de.pasteSecureInputTerminal),
      );
      expect(
        body(
          const HotkeyDisturbanceNotice(
            HotkeyDisturbanceCause.secureInput,
            appName: 'Zoom',
          ),
        ),
        startsWith(de.pasteSecureInputNamed('Zoom')),
      );
    });

    test('without a holder the text names no app', () {
      expect(
        body(const HotkeyDisturbanceNotice(HotkeyDisturbanceCause.secureInput)),
        '${de.pasteSecureInputGeneric} ${de.hotkeyDisturbanceSecureInputEffect}',
      );
      expect(
        hotkeyDisturbanceText(
          de,
          const HotkeyDisturbanceNotice(HotkeyDisturbanceCause.secureInput),
        ).title,
        de.hotkeyDisturbanceSecureInputTitle,
      );
    });
  });
}
