import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gguf_model.dart';
import 'package:whispaste/services/stt_parakeet/parakeet_gpu_policy.dart';

void main() {
  group('parakeetBackendReason', () {
    ParakeetBackendReason reason({
      bool platform = true,
      bool allowed = true,
      bool library = true,
      bool crashed = false,
      int strikes = 0,
    }) => parakeetBackendReason(
      platformEnabled: platform,
      gpuAccelerationAllowed: allowed,
      libraryPresent: library,
      crashedLastLaunch: crashed,
      crashStrikes: strikes,
    );

    test('selects GPU only when every condition holds', () {
      expect(reason(), ParakeetBackendReason.gpuSelected);
      expect(parakeetBackendFor(reason()), ParakeetBackend.gpu);
    });

    test('each blocking condition falls back to sherpa with its reason', () {
      expect(reason(platform: false), ParakeetBackendReason.platformDisabled);
      expect(
        reason(allowed: false),
        ParakeetBackendReason.gpuAccelerationDisabled,
      );
      expect(reason(library: false), ParakeetBackendReason.libraryMissing);
      expect(reason(crashed: true), ParakeetBackendReason.crashedLastLaunch);
      expect(
        reason(strikes: parakeetGpuCrashStrikeThreshold),
        ParakeetBackendReason.crashStrikesExhausted,
      );
      for (final r in [
        reason(platform: false),
        reason(allowed: false),
        reason(library: false),
        reason(crashed: true),
        reason(strikes: parakeetGpuCrashStrikeThreshold),
      ]) {
        expect(parakeetBackendFor(r), ParakeetBackend.sherpaCpu);
      }
    });

    test('a single earlier strike does not block GPU for good', () {
      expect(
        reason(strikes: parakeetGpuCrashStrikeThreshold - 1),
        ParakeetBackendReason.gpuSelected,
      );
    });
  });

  group('ParakeetGpuCrashMarker', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pk_marker_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('no marker means no crash', () {
      final m = ParakeetGpuCrashMarker(dir: dir.path);
      expect(m.recoverFromPreviousLaunch(), isFalse);
      expect(m.readStrikes(), 0);
    });

    test('a marker left behind counts as one strike and is consumed', () {
      final m = ParakeetGpuCrashMarker(dir: dir.path)..markAttempt();
      // The process "dies" here: the marker is never cleared.
      final next = ParakeetGpuCrashMarker(dir: dir.path);
      expect(next.recoverFromPreviousLaunch(), isTrue);
      expect(next.readStrikes(), 1);
      expect(next.recoverFromPreviousLaunch(), isFalse);
      expect(m.readStrikes(), 1);
    });

    test('a confirmed healthy run resets the strikes', () {
      final m = ParakeetGpuCrashMarker(dir: dir.path)..markAttempt();
      ParakeetGpuCrashMarker(dir: dir.path).recoverFromPreviousLaunch();
      m
        ..markAttempt()
        ..confirmHealthy();
      expect(m.readStrikes(), 0);
      expect(m.recoverFromPreviousLaunch(), isFalse);
    });

    test('strikes expire, so an exhausted GPU gets another attempt', () {
      var now = DateTime(2026, 10, 1);
      ParakeetGpuCrashMarker crashOnce() {
        final m = ParakeetGpuCrashMarker(dir: dir.path, now: () => now)
          ..markAttempt();
        ParakeetGpuCrashMarker(
          dir: dir.path,
          now: () => now,
        ).recoverFromPreviousLaunch();
        return m;
      }

      crashOnce();
      final m = crashOnce();
      expect(m.readStrikes(), parakeetGpuCrashStrikeThreshold);

      now = now.add(parakeetGpuCrashStrikeExpiry - const Duration(minutes: 1));
      expect(m.readStrikes(), parakeetGpuCrashStrikeThreshold);

      now = now.add(const Duration(minutes: 1));
      expect(m.readStrikes(), 0);
    });

    test('a strike file without a timestamp still counts', () {
      File('${dir.path}/.parakeet_gpu_strikes').writeAsStringSync('2');
      expect(ParakeetGpuCrashMarker(dir: dir.path).readStrikes(), 2);
    });

    test('a catchable load failure leaves no strike', () {
      final m = ParakeetGpuCrashMarker(dir: dir.path)
        ..markAttempt()
        ..abandonAttempt();
      expect(m.recoverFromPreviousLaunch(), isFalse);
      expect(m.readStrikes(), 0);
    });
  });

  group('verifyParakeetGguf', () {
    late Directory dir;
    late List<int> content;
    late ParakeetGgufFile expected;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('pk_gguf_');
      content = utf8.encode('pretend this is a GGUF file' * 50);
      expected = ParakeetGgufFile(
        quant: ParakeetGgufQuant.q8Zero,
        sizeBytes: content.length,
        sha256: sha256.convert(content).toString(),
      );
    });
    tearDown(() => dir.deleteSync(recursive: true));

    String write(List<int> bytes) {
      final f = File('${dir.path}/model.bin')..writeAsBytesSync(bytes);
      return f.path;
    }

    test('accepts a file that matches size and SHA-256', () async {
      expect(
        await verifyParakeetGguf(write(content), expected),
        ParakeetGgufCheck.ok,
      );
    });

    test('reports a missing file', () async {
      expect(
        await verifyParakeetGguf('${dir.path}/absent.bin', expected),
        ParakeetGgufCheck.missing,
      );
    });

    test('rejects a truncated file before hashing it', () async {
      expect(
        await verifyParakeetGguf(write(content.sublist(0, 100)), expected),
        ParakeetGgufCheck.sizeMismatch,
      );
    });

    test('rejects a same-size file with different content', () async {
      final corrupt = List<int>.of(content)..[10] ^= 0xff;
      expect(
        await verifyParakeetGguf(write(corrupt), expected),
        ParakeetGgufCheck.hashMismatch,
      );
    });
  });

  group('pinned GGUF files', () {
    test('every pin is a 64-hex SHA-256 and a non-trivial size', () {
      for (final f in parakeetGgufFiles.values) {
        expect(f.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(f.sizeBytes, greaterThan(100 * 1024 * 1024));
        expect(f.url, contains(ParakeetGgufFile.revision));
      }
    });

    test('the default quant is pinned', () {
      expect(parakeetGgufFiles, contains(parakeetGgufDefaultQuant));
    });
  });
}
