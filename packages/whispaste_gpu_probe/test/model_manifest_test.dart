/// Tests for ModelManifest, ModelEntry, and acquireModel.
///
/// No real network. All downloads are driven by a fake [ModelDownloader] that
/// either writes controlled bytes, writes wrong bytes, or throws.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:whispaste_gpu_probe/whispaste_gpu_probe.dart';

// ---------------------------------------------------------------------------
// Test fixtures
// ---------------------------------------------------------------------------

/// The canonical byte payload used for the "correct" model.
final Uint8List _goodBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

/// Pre-computed SHA-256 of [_goodBytes].
final String _goodSha256 = sha256OfBytes(_goodBytes);

/// Some bytes that produce a different SHA-256.
final Uint8List _badBytes = Uint8List.fromList([9, 8, 7]);

/// A minimal [ModelEntry] pointing at a fake download URL.
ModelEntry _makeEntry() => ModelEntry(
  name: 'test-model',
  downloadUrl: Uri.parse('https://example.com/test-model.bin'),
  sha256: _goodSha256,
  targetFilename: 'test-model.bin',
  sizeBytes: 5,
);

// ---------------------------------------------------------------------------
// Fake downloaders
// ---------------------------------------------------------------------------

/// Writes [_goodBytes] to target — simulates a correct download.
int _goodDownloadCalls = 0;

Future<void> _goodDownloader(Uri url, File target) async {
  _goodDownloadCalls++;
  target.writeAsBytesSync(_goodBytes);
}

/// Writes [_badBytes] to target — simulates a corrupted download.
Future<void> _badBytesDownloader(Uri url, File target) async {
  target.writeAsBytesSync(_badBytes);
}

/// Throws unconditionally — simulates a network error.
Future<void> _throwingDownloader(Uri url, File target) async {
  throw Exception('network error: connection refused');
}

// ---------------------------------------------------------------------------
// Helper: build a working directory backed by a real temp dir.
// ---------------------------------------------------------------------------

Directory _makeTempDir() =>
    Directory.systemTemp.createTempSync('model_manifest_test_');

// ---------------------------------------------------------------------------
// AC1: ModelManifest shape
// ---------------------------------------------------------------------------

void main() {
  group('ModelEntry / ModelManifest (AC1)', () {
    test('ModelEntry holds all required fields', () {
      final entry = _makeEntry();
      expect(entry.name, equals('test-model'));
      expect(
        entry.downloadUrl,
        equals(Uri.parse('https://example.com/test-model.bin')),
      );
      expect(entry.sha256, isNotEmpty);
      expect(entry.targetFilename, equals('test-model.bin'));
      expect(entry.sizeBytes, equals(5));
    });

    test('ModelManifest.find returns the matching entry', () {
      final manifest = ModelManifest(entries: [_makeEntry()]);
      final found = manifest.find('test-model');
      expect(found, isNotNull);
      expect(found!.name, equals('test-model'));
    });

    test('ModelManifest.find returns null for unknown name', () {
      final manifest = ModelManifest(entries: [_makeEntry()]);
      expect(manifest.find('nonexistent'), isNull);
    });
  });

  // -------------------------------------------------------------------------
  // AC2 + AC4a: existing file with correct checksum → reuse, no download call
  // -------------------------------------------------------------------------

  group('acquireModel — reuse on checksum match (AC2, AC4a)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _makeTempDir();
      _goodDownloadCalls = 0; // reset counter
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'returns null (success) when file already exists with correct checksum',
      () async {
        final entry = _makeEntry();
        // Pre-populate the file with correct bytes.
        File(
          p.join(tempDir.path, entry.targetFilename),
        ).writeAsBytesSync(_goodBytes);

        final result = await acquireModel(
          entry: entry,
          workDir: tempDir.path,
          downloader: _goodDownloader,
          candidateId: 'test-candidate',
        );

        expect(result, isNull, reason: 'null means success/reuse');
      },
    );

    test(
      'does NOT call the downloader when checksum already matches (AC4a)',
      () async {
        final entry = _makeEntry();
        File(
          p.join(tempDir.path, entry.targetFilename),
        ).writeAsBytesSync(_goodBytes);

        _goodDownloadCalls = 0;
        await acquireModel(
          entry: entry,
          workDir: tempDir.path,
          downloader: _goodDownloader,
          candidateId: 'test-candidate',
        );

        expect(
          _goodDownloadCalls,
          equals(0),
          reason: 'downloader must not be called on cache hit',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC2: missing file → download + verify → success
  // -------------------------------------------------------------------------

  group('acquireModel — download on missing file (AC2)', () {
    late Directory tempDir;

    setUp(() => tempDir = _makeTempDir());
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns null (success) when download writes correct bytes', () async {
      final entry = _makeEntry();

      final result = await acquireModel(
        entry: entry,
        workDir: tempDir.path,
        downloader: _goodDownloader,
        candidateId: 'test-candidate',
      );

      expect(result, isNull, reason: 'download + verify succeeded');
      // The file must now exist on disk.
      expect(
        File(p.join(tempDir.path, entry.targetFilename)).existsSync(),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC2 + AC4b: file exists but wrong checksum → download, then verify fails
  // (downloader writes bad bytes → mismatch → skipped)
  // -------------------------------------------------------------------------

  group('acquireModel — checksum mismatch → skipped (AC2, AC4b)', () {
    late Directory tempDir;

    setUp(() => tempDir = _makeTempDir());
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'returns skipped result when downloaded file has wrong checksum (AC4b)',
      () async {
        final entry = _makeEntry();

        final result = await acquireModel(
          entry: entry,
          workDir: tempDir.path,
          downloader: _badBytesDownloader,
          candidateId: 'test-candidate',
        );

        expect(result, isNotNull);
        expect(result!.outcome, equals(Outcome.skipped));
        expect(result.errorDetail, contains('Checksum mismatch'));
        expect(result.candidateId, equals('test-candidate'));
      },
    );

    test(
      'returns skipped when existing file has wrong checksum and download also returns wrong bytes',
      () async {
        final entry = _makeEntry();
        // Pre-seed a file with wrong bytes.
        File(
          p.join(tempDir.path, entry.targetFilename),
        ).writeAsBytesSync(_badBytes);

        final result = await acquireModel(
          entry: entry,
          workDir: tempDir.path,
          downloader: _badBytesDownloader,
          candidateId: 'test-candidate',
        );

        expect(result, isNotNull);
        expect(result!.outcome, equals(Outcome.skipped));
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4c: download throws → failedToStart, orchestrator continues
  // -------------------------------------------------------------------------

  group('acquireModel — download exception → failedToStart (AC3, AC4c)', () {
    late Directory tempDir;

    setUp(() => tempDir = _makeTempDir());
    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('returns failedToStart when downloader throws (AC4c)', () async {
      final entry = _makeEntry();

      final result = await acquireModel(
        entry: entry,
        workDir: tempDir.path,
        downloader: _throwingDownloader,
        candidateId: 'test-candidate',
      );

      expect(result, isNotNull);
      expect(result!.outcome, equals(Outcome.failedToStart));
      expect(result.errorDetail, contains('network error'));
      expect(result.candidateId, equals('test-candidate'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3 + AC4c: orchestrator continues when one candidate acquisition fails
  // -------------------------------------------------------------------------

  group('orchestrator continues after acquisition failure (AC3, AC4c)', () {
    late Directory tempDir;
    late Directory outputDir;

    setUp(() {
      tempDir = _makeTempDir();
      outputDir = _makeTempDir();
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
    });

    test('matrix runs to completion even when acquisition throws', () async {
      final entry = _makeEntry();

      // A candidate that uses acquireModel internally: if acquisition fails it
      // returns the failure result; otherwise it returns Outcome.ok.
      final failingCandidate = _AcquiringCandidate(
        id: 'failing-candidate',
        entry: entry,
        downloader: _throwingDownloader,
      );
      final okCandidate = _FakeOkCandidate();

      final zipPath = await runProbeOrchestrator(
        candidates: [failingCandidate, okCandidate],
        context: ProbeContext(
          referenceWavPath: '/fake/ref.wav',
          modelPath: '/fake/model.bin',
          workDir: tempDir.path,
        ),
        outputDir: outputDir.path,
        version: '0.0.0-test',
      );

      // ZIP must exist — orchestrator completed.
      expect(
        File(zipPath).existsSync(),
        isTrue,
        reason: 'orchestrator must write ZIP even when one candidate fails',
      );

      // Both candidates must have produced results.
      expect(failingCandidate.runCount, equals(1));
      expect(okCandidate.runCount, equals(1));

      // Failing candidate's result must be failedToStart.
      expect(failingCandidate.lastOutcome, equals(Outcome.failedToStart));
      // OK candidate's result must be ok.
      expect(okCandidate.lastOutcome, equals(Outcome.ok));
    });
  });
}

// ---------------------------------------------------------------------------
// Helpers used in AC4c integration test
// ---------------------------------------------------------------------------

/// A [ProbeCandidate] that calls [acquireModel] for its model and returns the
/// acquisition failure (or [Outcome.ok] on success).
class _AcquiringCandidate implements ProbeCandidate {
  _AcquiringCandidate({
    required this.id,
    required this.entry,
    required this.downloader,
  });

  @override
  final String id;

  final ModelEntry entry;
  final ModelDownloader downloader;

  int runCount = 0;
  Outcome? lastOutcome;

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    runCount++;
    final failure = await acquireModel(
      entry: entry,
      workDir: ctx.workDir,
      downloader: downloader,
      candidateId: id,
    );
    if (failure != null) {
      lastOutcome = failure.outcome;
      return failure;
    }
    lastOutcome = Outcome.ok;
    return CandidateResult(candidateId: id, outcome: Outcome.ok);
  }
}

/// Simple always-ok candidate.
class _FakeOkCandidate implements ProbeCandidate {
  int runCount = 0;
  Outcome? lastOutcome;

  @override
  String get id => 'fake-ok';

  @override
  Future<CandidateResult> run(ProbeContext ctx) async {
    runCount++;
    lastOutcome = Outcome.ok;
    return const CandidateResult(candidateId: 'fake-ok', outcome: Outcome.ok);
  }
}
