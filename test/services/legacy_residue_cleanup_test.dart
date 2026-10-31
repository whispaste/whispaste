/// Unit tests for [isLegacyServerResidue], [sweepLegacyServerResidue], and
/// [sweepLegacyResidueIfNeeded].
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:whispaste/services/legacy_residue_cleanup.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // Pure function — isLegacyServerResidue
  // ──────────────────────────────────────────────────────────────────────────

  group('isLegacyServerResidue — pure decision function', () {
    test('whisper-server (macOS/Linux binary) → residue', () {
      expect(isLegacyServerResidue('whisper-server'), isTrue);
    });

    test('whisper-server.exe (Windows binary) → residue', () {
      expect(isLegacyServerResidue('whisper-server.exe'), isTrue);
    });

    test('.dll (Windows shared lib) → residue', () {
      expect(isLegacyServerResidue('ggml-cuda.dll'), isTrue);
    });

    test('.dylib (macOS shared lib) → residue', () {
      expect(isLegacyServerResidue('libwhisper.dylib'), isTrue);
    });

    test('.so (Linux shared lib) → residue', () {
      expect(isLegacyServerResidue('libggml.so'), isTrue);
    });

    test('.metallib (macOS Metal shader lib) → residue', () {
      expect(isLegacyServerResidue('default.metallib'), isTrue);
    });

    test('_whisper-server.zip (leftover temp download) → residue', () {
      expect(isLegacyServerResidue('_whisper-server.zip'), isTrue);
    });

    test('matches case-insensitively', () {
      expect(isLegacyServerResidue('WHISPER-SERVER.EXE'), isTrue);
    });

    test('ggml model file → NOT residue', () {
      expect(isLegacyServerResidue('ggml-small-q5_1.bin'), isFalse);
    });

    test('Parakeet ONNX model file → NOT residue', () {
      expect(isLegacyServerResidue('encoder.onnx'), isFalse);
    });

    test('Parakeet tokens file → NOT residue', () {
      expect(isLegacyServerResidue('tokens.txt'), isFalse);
    });

    test('unrelated file → NOT residue', () {
      expect(isLegacyServerResidue('readme.md'), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // I/O wrapper — sweepLegacyServerResidue
  // ──────────────────────────────────────────────────────────────────────────

  group('sweepLegacyServerResidue — I/O wrapper', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_legacy_residue_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes the legacy server binary and its shared libs', () async {
      final binary = File(p.join(tempDir.path, 'whisper-server'));
      final dylib = File(p.join(tempDir.path, 'libwhisper.dylib'));
      await binary.writeAsBytes([1]);
      await dylib.writeAsBytes([2]);

      final deleted = await sweepLegacyServerResidue(directory: tempDir.path);

      expect(deleted, 2);
      expect(binary.existsSync(), isFalse);
      expect(dylib.existsSync(), isFalse);
    });

    test('leaves model files untouched', () async {
      final model = File(p.join(tempDir.path, 'ggml-small-q5_1.bin'));
      final binary = File(p.join(tempDir.path, 'whisper-server.exe'));
      await model.writeAsBytes([1]);
      await binary.writeAsBytes([2]);

      final deleted = await sweepLegacyServerResidue(directory: tempDir.path);

      expect(deleted, 1);
      expect(model.existsSync(), isTrue);
      expect(binary.existsSync(), isFalse);
    });

    test('mixed directory: only residue files are removed', () async {
      // Maps filename → whether it's residue (and thus expected to be
      // deleted — the assertion below checks the INVERSE: still-exists).
      final isResidue = {
        'whisper-server': true,
        'ggml-medium-q5_0.bin': false,
        'encoder.onnx': false,
        'tokens.txt': false,
        'decoder.onnx': false,
        'libggml-cuda.so': true,
        '_whisper-server.zip': true,
      };
      for (final entry in isResidue.entries) {
        await File(p.join(tempDir.path, entry.key)).writeAsBytes([0]);
      }

      final deleted = await sweepLegacyServerResidue(directory: tempDir.path);

      expect(deleted, 3);
      for (final entry in isResidue.entries) {
        final exists = File(p.join(tempDir.path, entry.key)).existsSync();
        expect(exists, !entry.value, reason: entry.key);
      }
    });

    test('returns 0 when directory does not exist', () async {
      final nonexistent = p.join(tempDir.path, 'does_not_exist');
      final deleted = await sweepLegacyServerResidue(directory: nonexistent);
      expect(deleted, 0);
    });

    test('returns 0 when directory has no residue files', () async {
      await File(p.join(tempDir.path, 'ggml-small-q5_1.bin')).writeAsBytes([1]);

      final deleted = await sweepLegacyServerResidue(directory: tempDir.path);
      expect(deleted, 0);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Version gate — sweepLegacyResidueIfNeeded
  // ──────────────────────────────────────────────────────────────────────────

  group('sweepLegacyResidueIfNeeded — version gate', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wp_legacy_gate_');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'sweeps on first run for a version (no persisted value yet)',
      () async {
        final binary = File(p.join(tempDir.path, 'whisper-server'));
        await binary.writeAsBytes([1]);

        await sweepLegacyResidueIfNeeded(
          directory: tempDir.path,
          currentVersion: '1.2.51',
        );

        expect(binary.existsSync(), isFalse);
      },
    );

    test('persists the version after a successful sweep', () async {
      await sweepLegacyResidueIfNeeded(
        directory: tempDir.path,
        currentVersion: '1.2.51',
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('legacy_residue_cleanup_version'), '1.2.51');
    });

    test(
      'does NOT re-scan the directory on a second run of the same version',
      () async {
        await sweepLegacyResidueIfNeeded(
          directory: tempDir.path,
          currentVersion: '1.2.51',
        );

        // A residue file appears after the first (already-gated) run —
        // e.g. hypothetically re-created by something else. The second call
        // on the SAME version must skip the scan entirely and leave it be.
        final binary = File(p.join(tempDir.path, 'whisper-server'));
        await binary.writeAsBytes([1]);

        await sweepLegacyResidueIfNeeded(
          directory: tempDir.path,
          currentVersion: '1.2.51',
        );

        expect(binary.existsSync(), isTrue);
      },
    );

    test('re-scans when the app version changes', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('legacy_residue_cleanup_version', '1.2.50');

      final binary = File(p.join(tempDir.path, 'whisper-server'));
      await binary.writeAsBytes([1]);

      await sweepLegacyResidueIfNeeded(
        directory: tempDir.path,
        currentVersion: '1.2.51',
      );

      expect(binary.existsSync(), isFalse);
      expect(prefs.getString('legacy_residue_cleanup_version'), '1.2.51');
    });

    test('does not throw when the directory does not exist', () async {
      final nonexistent = p.join(tempDir.path, 'does_not_exist');
      await expectLater(
        sweepLegacyResidueIfNeeded(
          directory: nonexistent,
          currentVersion: '1.2.51',
        ),
        completes,
      );
    });
  });
}
