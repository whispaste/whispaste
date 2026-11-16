/// #825: the restart behind the cards "model cannot start" and "hotkey stopped
/// responding". Logic only: every platform effect is a spy, no process starts.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/app_restart_service.dart';

class _Spy {
  bool busy = false;
  final calls = <String>[];
  String? spawnedExecutable;
  List<String>? spawnedArguments;
  String? appImage;
  Object? spawnError;

  AppRestartService service({required bool mac}) => AppRestartService(
    isDictationBusy: () => busy,
    shutdown: () async => calls.add('shutdown'),
    releaseInstanceLock: () async => calls.add('release'),
    macRelaunch: () async => calls.add('mac'),
    spawn: (exe, args) async {
      if (spawnError != null) throw spawnError!;
      calls.add('spawn');
      spawnedExecutable = exe;
      spawnedArguments = args;
    },
    endProcess: () => calls.add('exit'),
    appImagePath: () => appImage,
    resolvedExecutable: '/opt/whispaste/whispaste',
    isMacOS: mac,
  );
}

void main() {
  test(
    'macOS hands over to the native relaunch after freeing the lock',
    () async {
      final spy = _Spy();
      final result = await spy.service(mac: true).requestRestart();
      expect(result, AppRestartResult.started);
      expect(spy.calls, ['shutdown', 'release', 'mac']);
    },
  );

  test('Windows and Linux start a fresh copy, then end the process', () async {
    final spy = _Spy();
    final result = await spy.service(mac: false).requestRestart();
    expect(result, AppRestartResult.started);
    expect(spy.calls, ['shutdown', 'release', 'spawn', 'exit']);
    expect(spy.spawnedExecutable, '/opt/whispaste/whispaste');
    expect(spy.spawnedArguments, isEmpty);
  });

  test('an AppImage starts again from the image file', () async {
    final spy = _Spy()..appImage = '/home/u/WhisPaste.AppImage';
    await spy.service(mac: false).requestRestart();
    expect(spy.spawnedExecutable, '/home/u/WhisPaste.AppImage');
  });

  test('a running dictation is never cut off: the restart waits', () async {
    final spy = _Spy()..busy = true;
    final service = spy.service(mac: false);
    expect(await service.requestRestart(), AppRestartResult.deferred);
    expect(service.isPending, isTrue);
    expect(spy.calls, isEmpty);

    // Still busy (the next phase of the same dictation): nothing happens.
    await service.dictationEnded();
    expect(spy.calls, isEmpty);

    spy.busy = false;
    await service.dictationEnded();
    expect(spy.calls, ['shutdown', 'release', 'spawn', 'exit']);
    expect(service.isPending, isFalse);
  });

  test(
    'without a waiting request the end of a dictation does nothing',
    () async {
      final spy = _Spy();
      await spy.service(mac: false).dictationEnded();
      expect(spy.calls, isEmpty);
    },
  );

  test(
    'a second request while the restart runs starts nothing twice',
    () async {
      final spy = _Spy();
      final service = spy.service(mac: false);
      final first = service.requestRestart();
      final second = service.requestRestart();
      await Future.wait([first, second]);
      expect(spy.calls.where((c) => c == 'spawn'), hasLength(1));
    },
  );

  test('a failed start keeps this process running', () async {
    final spy = _Spy()..spawnError = Exception('no exec');
    final result = await spy.service(mac: false).requestRestart();
    expect(result, AppRestartResult.failed);
    expect(spy.calls, isNot(contains('exit')));
  });
}
