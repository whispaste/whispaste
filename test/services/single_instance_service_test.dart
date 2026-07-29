import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/single_instance_service.dart';

void main() {
  // These exercise real TCP sockets on loopback (no platform channel/mock
  // needed) — SingleInstanceService is pure dart:io.
  tearDown(() async {
    // Leave the port clean for the next test regardless of outcome.
    await SingleInstanceService.release();
  });

  test(
    'release() frees the port so a later instance can become primary',
    () async {
      final first = await SingleInstanceService.ensureSingleInstance();
      expect(first, isTrue, reason: 'first caller should claim the lock');

      final second = await SingleInstanceService.ensureSingleInstance();
      expect(
        second,
        isFalse,
        reason: 'a second caller while the lock is held must not also claim it',
      );

      await SingleInstanceService.release();

      final third = await SingleInstanceService.ensureSingleInstance();
      expect(
        third,
        isTrue,
        reason:
            'after release(), the port must be truly free — this is the exact '
            'guarantee a self-relaunch depends on: the freshly-spawned '
            'replacement process must be able to claim the lock immediately, '
            'or it treats itself as a duplicate launch and exits, leaving '
            'nothing running (observed live: native restart alert fired, app '
            'just closed instead of relaunching).',
      );
    },
  );

  test('release() is a no-op when the lock was never acquired', () async {
    // Must not throw for a process that never became primary (e.g. it lost
    // ensureSingleInstance() and is about to exit anyway).
    await SingleInstanceService.release();
  });
}
