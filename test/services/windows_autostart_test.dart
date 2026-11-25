import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/autostart_backend.dart';
import 'package:whispaste/services/windows_autostart.dart';

class _Unpacked implements AutostartBackend {
  bool enabled = false;
  int calls = 0;
  @override
  Future<bool> isEnabled() async {
    calls++;
    return enabled;
  }

  @override
  Future<void> enable() async {
    calls++;
    enabled = true;
  }

  @override
  Future<void> disable() async {
    calls++;
    enabled = false;
  }

  @override
  Future<bool> requiresApproval() async => false;
  @override
  Future<void> openLoginItems() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Unpacked unpacked;
  late WindowsAutostartBackend backend;
  late bool packaged;
  late bool enabled;
  late bool blocked;
  late List<String> calls;

  setUp(() {
    unpacked = _Unpacked();
    backend = WindowsAutostartBackend(unpacked);
    packaged = true;
    enabled = false;
    blocked = false;
    calls = [];
    messenger.setMockMethodCallHandler(WindowsAutostartBackend.channel, (
      call,
    ) async {
      calls.add(call.method);
      switch (call.method) {
        case 'isPackaged':
          return packaged;
        case 'isEnabled':
          return enabled;
        case 'enable':
          if (blocked) throw PlatformException(code: 'autostart_blocked');
          return enabled = true;
        case 'disable':
          return enabled = false;
      }
      throw MissingPluginException();
    });
  });
  tearDown(
    () => messenger.setMockMethodCallHandler(
      WindowsAutostartBackend.channel,
      null,
    ),
  );

  test(
    'Store uses package task for enable, read and disable, never Run key',
    () async {
      expect(await backend.isEnabled(), isFalse);
      await backend.enable();
      expect(await backend.isEnabled(), isTrue);
      await backend.disable();
      expect(await backend.isEnabled(), isFalse);
      expect(unpacked.calls, 0);
      expect(calls, containsAll(['enable', 'disable']));
    },
  );

  test('unpackaged installation uses registry backend', () async {
    packaged = false;
    await backend.enable();
    expect(await backend.isEnabled(), isTrue);
    await backend.disable();
    expect(await backend.isEnabled(), isFalse);
    expect(unpacked.calls, 4);
    expect(calls.toSet(), {'isPackaged'});
  });

  test(
    'user or policy refusal is surfaced, without fallback to registry',
    () async {
      blocked = true;
      await expectLater(backend.enable(), throwsA(isA<PlatformException>()));
      expect(await backend.isEnabled(), isFalse);
      expect(unpacked.calls, 0);
    },
  );

  test('unsuccessful native enable cannot be reported as success', () async {
    messenger.setMockMethodCallHandler(
      WindowsAutostartBackend.channel,
      (call) async => call.method == 'isPackaged',
    );
    await expectLater(backend.enable(), throwsStateError);
  });

  test('unsuccessful native disable cannot be reported as success', () async {
    messenger.setMockMethodCallHandler(
      WindowsAutostartBackend.channel,
      (_) async => true,
    );
    await expectLater(backend.disable(), throwsStateError);
    expect(unpacked.calls, 0);
  });

  test('identity lookup failure never falls back to versioned EXE', () async {
    messenger.setMockMethodCallHandler(
      WindowsAutostartBackend.channel,
      (_) async => throw PlatformException(code: 'identity_error'),
    );
    await expectLater(backend.enable(), throwsA(isA<PlatformException>()));
    expect(unpacked.calls, 0);
  });

  test('Run command quotes EXE including spaces before autostart argument', () {
    const path = r'C:\Users\Jane Doe\AppData\Local\WhisPaste\whispaste.exe';
    expect(
      '${windowsAutostartExecutable(path)} --autostart',
      '"$path" --autostart',
    );
  });

  test(
    'MSIX declares opt-in task with matching native ID and startup argument',
    () {
      final config = File('pubspec.yaml').readAsStringSync();
      expect(
        config,
        contains(
          '  startup_task:\n'
          '    task_id: WhisPasteStartup\n'
          '    enabled: false\n'
          '    parameters: --autostart\n',
        ),
        reason: 'Store autostart requires an opt-in manifest extension',
      );
      final native = File(
        'windows/runner/autostart_host.cpp',
      ).readAsStringSync();
      expect(native, contains('StartupTask::GetAsync(L"WhisPasteStartup")'));
    },
  );
}
