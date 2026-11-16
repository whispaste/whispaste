import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The file access of the recording pipeline's capture step: the WAV the
/// audio service wrote is probed, sized and read through this seam.
///
/// Production uses [RealRecordingFiles] (plain `dart:io`). Journey tests
/// override [recordingFilesProvider] with an in-memory fake, so the
/// pipeline finishes under the fake clock without real I/O (#173).
abstract interface class RecordingFiles {
  Future<bool> exists(String path);
  Future<int> length(String path);
  Future<List<int>> readAsBytes(String path);
  Future<bool> directoryExists(String path);
  Future<void> createDirectory(String path);
}

/// `dart:io` implementation, behaviour identical to the former direct calls.
class RealRecordingFiles implements RecordingFiles {
  const RealRecordingFiles();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<List<int>> readAsBytes(String path) => readFileChunked(path);

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<void> createDirectory(String path) =>
      Directory(path).create(recursive: true);
}

/// Bytes read per step by [readFileChunked].
const int _readChunkBytes = 1024 * 1024;

/// Reads the file at [path] into one buffer of its size, [_readChunkBytes] at
/// a time (#1642). `File.readAsBytes` left about 40 MB more resident memory
/// behind than the file itself for a 60-minute recording (110 MB, measured in
/// `internal-notes`). A file that grows
/// while it is read is cut at the length it had when the read began, one
/// that shrinks ends where its data ends.
Future<Uint8List> readFileChunked(String path) async {
  final file = await File(path).open();
  try {
    final bytes = Uint8List(await file.length());
    var filled = 0;
    while (filled < bytes.length) {
      final end = math.min(filled + _readChunkBytes, bytes.length);
      final read = await file.readInto(bytes, filled, end);
      if (read <= 0) break;
      filled += read;
    }
    return filled == bytes.length
        ? bytes
        : Uint8List.sublistView(bytes, 0, filled);
  } finally {
    await file.close();
  }
}

final recordingFilesProvider = Provider<RecordingFiles>(
  (ref) => const RealRecordingFiles(),
);
