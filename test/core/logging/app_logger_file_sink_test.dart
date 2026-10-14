/// Tests for the persistent log-file sink in `AppLogger`: rotation,
/// write-time secret redaction, and log-injection protection.
///
/// `configureLogging()` wires a single `Logger.root.onRecord` listener and
/// is not designed to be called more than once per process — all scenarios
/// below therefore live in one `test()` body that calls it exactly once,
/// pointed at an isolated temp directory via `appDataDirOverride`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/app_logger.dart';
import 'package:whispaste/services/path_service.dart' as paths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('log file sink: rotates by size, redacts secrets, blocks log injection, '
      'releases for deletion', () async {
    final tempDir = Directory.systemTemp.createTempSync('wp_app_logger_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    paths.appDataDirOverride = tempDir.path;
    addTearDown(() => paths.appDataDirOverride = null);
    // Windows locks open files: the sink's RandomAccessFile must be
    // closed before tempDir.deleteSync() above, or deletion throws
    // PathAccessException. addTearDown runs LIFO, so registering this
    // last makes it run first.
    addTearDown(closeLogFileSinkForTest);

    await configureLogging();
    final log = AppLogger('AppLoggerFileSinkTest');

    // --- Redaction -----------------------------------------------------
    // Built from parts so this fixture isn't itself a literal secret that
    // repo-wide secret scanners would flag.
    const fakeSecret =
        'sk-'
        'abcdefghijklmnop1234567890';
    log.error('Login failed for token: api_key="$fakeSecret"');

    // --- Log-injection protection ---------------------------------------
    log.info('Attacker payload: line1\nFAKE [SEVERE] Injected: pwned\r\nend');

    // --- Rotation: cross the 2 MB threshold twice ------------------------
    // ~1100 bytes per line; ~2000 lines crosses 2 MB once per rotation.
    final filler = 'x' * 1080;
    for (var i = 0; i < 2200; i++) {
      log.info('filler-$i-$filler');
    }
    for (var i = 0; i < 2200; i++) {
      log.info('filler2-$i-$filler');
    }

    final logDir = Directory('${tempDir.path}${Platform.pathSeparator}logs');
    final primary = File(
      '${logDir.path}${Platform.pathSeparator}whispaste.log',
    );
    final rotated1 = File('${primary.path}.1');
    final rotated2 = File('${primary.path}.2');

    expect(primary.existsSync(), isTrue);
    expect(
      rotated1.existsSync(),
      isTrue,
      reason: 'first rotation should have created whispaste.log.1',
    );
    expect(
      rotated2.existsSync(),
      isTrue,
      reason:
          'second rotation should have shifted .1 → .2 and created a '
          'fresh .1',
    );

    // Redaction: secret substring never reaches disk, in any rotated file.
    final allContent = [
      primary,
      rotated1,
      rotated2,
    ].where((f) => f.existsSync()).map((f) => f.readAsStringSync()).join();
    expect(allContent.contains(fakeSecret), isFalse);
    expect(allContent.contains('<redacted>'), isTrue);

    // Log injection: the forged "[SEVERE] Injected: pwned" never appears
    // as its own log line — it must be escaped inline instead.
    final lines = allContent.split('\n');
    expect(
      lines.any((l) => l.trim() == 'FAKE [SEVERE] Injected: pwned'),
      isFalse,
      reason: 'attacker-controlled newlines must not forge a fake log line',
    );
    expect(allContent.contains(r'Attacker payload: line1\nFAKE'), isTrue);

    // --- Release for deletion (factory reset, Sentry 123406956) ----------
    // The logs directory can be deleted while the handle is released, and
    // logging resumes into a freshly created file afterwards.
    await withLogFileReleased(() async => logDir.deleteSync(recursive: true));
    log.info('after-release');
    expect(primary.existsSync(), isTrue);
    expect(primary.readAsStringSync(), contains('after-release'));
  });
}
