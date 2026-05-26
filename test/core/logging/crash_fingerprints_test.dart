/// Unit tests for the central crash-fingerprint inventory.
///
/// These tests pin the canonical Sentry-fingerprint string values from
/// `.scratch/reliability-sprint/prd.md` — Modul 6 „CrashFingerprint".
///
/// Goal: protect the inventory against silent renames or typos that would
/// break Sentry issue grouping (the entire reason for the migration away
/// from inline string literals).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:whispaste/core/logging/crash_fingerprints.dart';

void main() {
  group('CrashFingerprints — PRD inventory', () {
    // The canonical inventory from the PRD table (Modul 6).
    // Format: <constant ref> → <expected string value>.
    final inventory = <String, String>{
      'sttExitDllMissing': sttExitDllMissing,
      'sttExitGpuFatal': sttExitGpuFatal,
      'sttExitHeapCorruption': sttExitHeapCorruption,
      'sttExitOther': sttExitOther,
      'sttModelAbiMismatch': sttModelAbiMismatch,
      'sttModelCorrupted': sttModelCorrupted,
      'historyWriteFailed': historyWriteFailed,
      'historyWriteOther': historyWriteOther,
      'serverDownloadFailed': serverDownloadFailed,
      'serverDownloadStalled': serverDownloadStalled,
      'modelDownloadFailed': modelDownloadFailed,
      'updateCheckFailed': updateCheckFailed,
      'factoryResetFailed': factoryResetFailed,
    };

    test('all 13 PRD constants resolve to the canonical wire values', () {
      // These string values are part of the public Sentry-grouping contract:
      // changing them silently re-shards historical issues. If the PRD
      // inventory changes, this test must be updated deliberately.
      expect(sttExitDllMissing, 'stt-exit-dll-missing');
      expect(sttExitGpuFatal, 'stt-exit-gpu-fatal');
      expect(sttExitHeapCorruption, 'stt-exit-heap-corruption');
      expect(sttExitOther, 'stt-exit-other');
      expect(sttModelAbiMismatch, 'stt-model-abi-mismatch');
      expect(sttModelCorrupted, 'stt-model-corrupted');
      expect(historyWriteFailed, 'history-write-failed');
      expect(historyWriteOther, 'history-write-other');
      expect(serverDownloadFailed, 'server-download-failed');
      expect(serverDownloadStalled, 'server-download-stalled');
      expect(modelDownloadFailed, 'model-download-failed');
      expect(updateCheckFailed, 'update-check-failed');
      expect(factoryResetFailed, 'factory-reset-failed');
    });

    test('inventory exposes exactly 13 PRD constants', () {
      expect(inventory.length, 13);
    });

    test('no two PRD constants share the same wire value', () {
      final values = inventory.values.toList();
      final unique = values.toSet();
      expect(
        unique.length,
        values.length,
        reason:
            'Duplicate fingerprint detected in inventory — '
            'Sentry would collapse two distinct error classes into one issue.',
      );
    });

    test('allCrashFingerprints exposes all 13 PRD constants', () {
      // Sanity guard for any future test/tool that iterates the canonical
      // list (e.g. „verify no inline literal is missing from the inventory").
      for (final value in inventory.values) {
        expect(
          allCrashFingerprints,
          contains(value),
          reason:
              'allCrashFingerprints must contain every PRD-inventory value '
              '— missing: $value',
        );
      }
    });
  });

  group('CrashFingerprints — W1 inference inventory', () {
    // The five inference-error fingerprints added by the wartung-2026-05 W1
    // sprint. They classify HTTP-status responses from the local
    // `whisper-server` into Sentry buckets so `InferenceErrorClassifier`
    // (Issue 02) and the STT call-site (Issue 04) can attach class-specific
    // fingerprints to captures.
    final inferenceInventory = <String, String>{
      'inferenceBadRequest': inferenceBadRequest,
      'inferencePayloadTooLarge': inferencePayloadTooLarge,
      'inferenceUnsupportedMedia': inferenceUnsupportedMedia,
      'inferenceServerError': inferenceServerError,
      'inferenceUnknownStatus': inferenceUnknownStatus,
    };

    test('each inference constant resolves to a non-empty wire value', () {
      for (final entry in inferenceInventory.entries) {
        expect(
          entry.value,
          isNotEmpty,
          reason:
              '${entry.key} must expose a non-empty Sentry wire value — '
              'empty strings would collapse into Sentry default grouping.',
        );
      }
    });

    test('allCrashFingerprints contains every inference constant', () {
      for (final entry in inferenceInventory.entries) {
        expect(
          allCrashFingerprints,
          contains(entry.value),
          reason:
              'allCrashFingerprints must include ${entry.key} '
              '(wire value: ${entry.value}) — otherwise tooling that '
              'iterates the list cannot see it.',
        );
      }
    });
  });

  group('CrashFingerprints — global uniqueness', () {
    test('every wire value in allCrashFingerprints is unique', () {
      // Sentry treats fingerprints as a set: duplicates silently collapse
      // two distinct error classes into one issue, sharding diagnosis and
      // burning Free-Tier quota. This guard catches typos and copy-paste
      // collisions across the full inventory (PRD + pre-existing +
      // W1-inference).
      const values = allCrashFingerprints;
      final unique = values.toSet();
      expect(
        unique.length,
        values.length,
        reason:
            'Duplicate fingerprint detected in allCrashFingerprints — '
            'two constants share a wire value. Inspect the list and '
            'rename one of the colliding entries.',
      );
    });
  });
}
