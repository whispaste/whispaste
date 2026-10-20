/// Missing audio-enumeration tool (Linux: `pactl`) must degrade to the system
/// default microphone with a single info note, never a SEVERE log.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:record/record.dart' show InputDevice;
import 'package:whispaste/services/audio/input_device_lookup.dart';

ProcessException _missingTool() =>
    const ProcessException('pactl', ['list', 'sources'], 'No such file', 2);

void main() {
  setUp(resetInputDeviceLookupNoticeForTest);

  test('returns the devices when enumeration succeeds', () async {
    final devices = [const InputDevice(id: '1', label: 'USB Mic')];

    final result = await lookupInputDevices(() async => devices);

    expect(result, devices);
  });

  test('missing enumeration tool yields null, not a SEVERE log', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final result = await lookupInputDevices(() async => throw _missingTool());

    expect(result, isNull);
    expect(records.where((r) => r.level >= Level.SEVERE), isEmpty);
    expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
  });

  test('the missing-tool note is logged once, not on every lookup', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    for (var i = 0; i < 3; i++) {
      await lookupInputDevices(() async => throw _missingTool());
    }

    final notes = records.where((r) => r.message.contains('not available'));
    expect(notes, hasLength(1));
    expect(notes.single.level, Level.INFO);
  });

  test('other enumeration failures yield null with a warning', () async {
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);

    final result = await lookupInputDevices(
      () async => throw Exception('boom'),
    );

    expect(result, isNull);
    expect(records.single.level, Level.WARNING);
  });

  test('a hanging enumeration gives up and records with the default', () async {
    // RE2-09: `pactl` (Linux) or a stuck audio driver can block the listing.
    // It sits in front of the recording start, so the hotkey must not wait
    // for it indefinitely.
    final records = <LogRecord>[];
    final sub = Logger.root.onRecord.listen(records.add);
    addTearDown(sub.cancel);
    final never = Completer<List<InputDevice>>();

    final watch = Stopwatch()..start();
    final result = await lookupInputDevices(
      () => never.future,
      timeout: const Duration(milliseconds: 50),
    );

    expect(result, isNull);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    expect(records.single.level, Level.WARNING);
    expect(records.single.message, contains('timed out'));
  });

  test(
    'a stuck listing is not started again while it is still running',
    () async {
      // record_linux starts a new `pactl` process per call and never kills it,
      // so a stuck listing plus a retry per recording start piles up processes
      // and makes every start wait for the timeout again.
      final never = Completer<List<InputDevice>>();
      var starts = 0;
      Future<List<InputDevice>> stuck() {
        starts++;
        return never.future;
      }

      final first = await lookupInputDevices(
        stuck,
        timeout: const Duration(milliseconds: 50),
      );
      expect(first, isNull);
      expect(starts, 1);

      final watch = Stopwatch()..start();
      final second = await lookupInputDevices(
        stuck,
        timeout: const Duration(seconds: 5),
      );
      expect(second, isNull);
      expect(starts, 1, reason: 'no second enumeration while the first runs');
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));

      never.complete(const [InputDevice(id: '1', label: 'USB Mic')]);
      await Future<void>.delayed(Duration.zero);
      final third = await lookupInputDevices(
        () async => const [InputDevice(id: '1', label: 'USB Mic')],
      );
      expect(third!.map((d) => d.label), ['USB Mic']);
    },
  );

  test('waits up to 1.5 s by default', () {
    expect(inputDeviceLookupTimeout, const Duration(milliseconds: 1500));
  });

  test('Linux node names lose the quotes pactl prints around them', () async {
    // record_linux 2.1.1 keeps them and starts `parecord --device="wp_mic2"`
    // without a shell; PipeWire then finds no source and silently records
    // the system default instead of the selected microphone (XP-5-15).
    final result = await lookupInputDevices(
      () async => [
        const InputDevice(id: '"wp_mic2"', label: 'Testmikro-2'),
        const InputDevice(id: 'plain_id', label: 'USB Mic'),
      ],
    );

    expect(result!.map((d) => d.id), ['wp_mic2', 'plain_id']);
    expect(result.map((d) => d.label), ['Testmikro-2', 'USB Mic']);
  });

  test('labels fall back to Default when enumeration is unavailable', () {
    expect(inputDeviceLabelsFrom(null), ['Default']);
    expect(
      inputDeviceLabelsFrom([
        const InputDevice(id: '', label: ''),
        const InputDevice(id: '1', label: 'USB Mic'),
      ]),
      ['Default', 'USB Mic'],
    );
  });
}
